# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy>=1.26"]
# ///
"""
hvac_mv.py: measurement & verification for the HVAC optimizations.

Answers "is this actually saving money, and what does it cost in comfort?"
using a switchback experiment:
  * input_boolean.hvac_optimizations flips randomly each day at 03:00 (see
    config/packages/hvac_savings.yaml)
  * each "day" here is the 24h window ending 03:00 local, so it lines up with the flip
  * per thermostat, fit:  cooling_hours = a + b*CDH + d*away_hours + c*optimizations_on
    c is the weather- and schedule-adjusted effect (negative = runtime saved)

It also fits a baseline on control days (optimizations OFF) and prints the
PrometheusRule constants that power the dashboard's live "savings" panel.

Prometheus retention here is 31d, which is shorter than the 4-8 weeks of cooling
days a 10% effect needs. Pass --csv: daily rows are appended to it and the
analysis runs over the union, so a run survives retention.

Usage (fish-safe):
  kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090 &
  uv run hvac_mv.py --prom http://localhost:9090 --days 30 --csv hvac-days.csv
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import math
import sys
import urllib.parse
import urllib.request
from zoneinfo import ZoneInfo

import numpy as np

Z90 = 1.645  # two-sided 90% interval

CSV_FIELDS = ["day", "entity", "cooling_hours", "cdh", "away_hours", "flag_share", "comfort"]


# ---------------------------------------------------------------- Prometheus
def query(prom: str, expr: str, at: dt.datetime) -> dict[str, float]:
    """Instant query -> {entity or '': value}."""
    url = f"{prom.rstrip('/')}/api/v1/query?" + urllib.parse.urlencode(
        {"query": expr, "time": at.timestamp()}
    )
    with urllib.request.urlopen(url, timeout=30) as r:
        body = json.load(r)
    if body.get("status") != "success":
        raise RuntimeError(f"query failed: {expr}: {body}")
    out: dict[str, float] = {}
    for s in body["data"]["result"]:
        v = float(s["value"][1])
        if math.isfinite(v):
            out[s["metric"].get("entity", "")] = v
    return out


def collect(prom: str, days: int, tz: ZoneInfo, flip_hour: int) -> list[dict]:
    now = dt.datetime.now(tz)
    end = now.replace(hour=flip_hour, minute=0, second=0, microsecond=0)
    if end > now:
        end -= dt.timedelta(days=1)
    rows = []
    for i in range(days, 0, -1):
        t = end - dt.timedelta(days=i - 1)
        cdh = query(prom, "hvac:cdh:24h", t).get("")
        flag = query(prom, "avg_over_time(hvac:optimizations_on[24h])", t).get("")
        occ = query(prom, "sum_over_time(hvac:occupied[24h]) / 60", t).get("")
        if cdh is None or flag is None or occ is None:
            continue  # before instrumentation existed, or a scrape gap
        cool = query(prom, "hvac:cooling_hours:24h", t)
        comfort = query(prom, "hvac:comfort_ratio:24h", t)
        for entity, hours in cool.items():
            rows.append(
                {
                    "day": (t - dt.timedelta(days=1)).date().isoformat(),
                    "entity": entity,
                    "cooling_hours": hours,
                    "cdh": cdh,
                    "away_hours": max(0.0, 24.0 - occ),
                    "flag_share": flag,
                    "comfort": comfort.get(entity, float("nan")),
                }
            )
    return rows


# ---------------------------------------------------------------- CSV accumulation
def load_csv(path: str) -> list[dict]:
    try:
        with open(path, newline="") as f:
            out = []
            for row in csv.DictReader(f):
                out.append(
                    {
                        "day": row["day"],
                        "entity": row["entity"],
                        "cooling_hours": float(row["cooling_hours"]),
                        "cdh": float(row["cdh"]),
                        "away_hours": float(row["away_hours"]),
                        "flag_share": float(row["flag_share"]),
                        "comfort": float(row["comfort"]) if row.get("comfort") else float("nan"),
                    }
                )
            return out
    except FileNotFoundError:
        return []


def merge_rows(old: list[dict], new: list[dict]) -> list[dict]:
    """Newest wins, keyed on (day, entity)."""
    merged = {(r["day"], r["entity"]): r for r in old}
    for r in new:
        merged[(r["day"], r["entity"])] = r
    return [merged[k] for k in sorted(merged)]


def write_csv(path: str, rows: list[dict]) -> None:
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=CSV_FIELDS)
        w.writeheader()
        w.writerows(rows)


# ---------------------------------------------------------------- statistics
def ols(X: np.ndarray, y: np.ndarray) -> tuple[np.ndarray, np.ndarray, float]:
    """Return (beta, standard errors, residual std)."""
    n, k = X.shape
    beta, *_ = np.linalg.lstsq(X, y, rcond=None)
    resid = y - X @ beta
    dof = max(n - k, 1)
    sigma2 = float(resid @ resid) / dof
    cov = sigma2 * np.linalg.pinv(X.T @ X)
    return beta, np.sqrt(np.clip(np.diag(cov), 0, None)), math.sqrt(sigma2)


def analyze_entity(rows: list[dict], min_cdh: float) -> dict:
    r = [
        x
        for x in rows
        if x["cdh"] >= min_cdh and (x["flag_share"] <= 0.05 or x["flag_share"] >= 0.95)
    ]
    on = [x for x in r if x["flag_share"] >= 0.95]
    off = [x for x in r if x["flag_share"] <= 0.05]
    res: dict = {"n_on": len(on), "n_off": len(off)}
    if len(on) < 5 or len(off) < 5:
        res["status"] = "insufficient"
        return res

    y = np.array([x["cooling_hours"] for x in r])
    X = np.column_stack(
        [
            np.ones(len(r)),
            [x["cdh"] for x in r],
            [x["away_hours"] for x in r],
            [1.0 if x["flag_share"] >= 0.95 else 0.0 for x in r],
        ]
    )
    beta, se, _ = ols(X, y)
    c, c_se = float(beta[3]), float(se[3])

    # Baseline on control days only: runtime = a + b*CDH (what the dashboard uses).
    yb = np.array([x["cooling_hours"] for x in off])
    Xb = np.column_stack([np.ones(len(off)), [x["cdh"] for x in off]])
    bb, _, _ = ols(Xb, yb)

    mean_off_pred = float(np.mean(X[:, :3] @ beta[:3]))  # counterfactual "off" runtime
    comfort_on = float(np.nanmean([x["comfort"] for x in on]))
    comfort_off = float(np.nanmean([x["comfort"] for x in off]))

    # Days per arm needed to resolve a 10% effect, derived from this fit's own
    # standard error: se(c) scales as 1/sqrt(n), so scaling n scales se.
    target = 0.10 * max(mean_off_pred, 1e-6)
    if c_se > 0:
        n_needed = math.ceil(len(r) * (c_se * Z90 / target) ** 2 / 2)
    else:
        n_needed = 0

    res.update(
        status="ok",
        effect_h=c,
        ci_h=(c - Z90 * c_se, c + Z90 * c_se),
        significant=(c + Z90 * c_se) < 0 or (c - Z90 * c_se) > 0,
        mean_off_h=mean_off_pred,
        baseline_a=float(bb[0]),
        baseline_b=float(bb[1]),
        comfort_on=comfort_on,
        comfort_off=comfort_off,
        n_needed_per_arm=n_needed,
    )
    return res


def self_test() -> int:
    """Planted-effect check on the statistics. Fails if the fit stops recovering it."""
    rng = np.random.default_rng(7)
    true_effect = -0.9
    rows = []
    for day in range(40):
        cdh = 100 + 8 * day + float(rng.normal(0, 20))
        flag = 1.0 if day % 2 else 0.0
        hours = 1.5 + 0.012 * cdh + true_effect * flag + float(rng.normal(0, 0.3))
        rows.append(
            {
                "day": f"2026-06-{day % 28 + 1:02d}",
                "entity": "climate.main_floor",
                "cooling_hours": max(hours, 0.0),
                "cdh": cdh,
                "away_hours": 8.0,
                "flag_share": flag,
                "comfort": 0.9,
            }
        )
    res = analyze_entity(rows, min_cdh=0)
    assert res is not None and res["status"] == "ok", res
    assert res["significant"], f"planted effect not significant: {res}"
    lo, hi = res["ci_h"]
    assert lo <= true_effect <= hi, f"true effect {true_effect} outside CI {res['ci_h']}"
    assert abs(res["effect_h"] - true_effect) < 0.3, res
    print(f"self-test OK: recovered {res['effect_h']:+.2f} h/day (truth {true_effect:+.2f}), "
          f"90% CI {lo:+.2f}…{hi:+.2f}")
    return 0


# ---------------------------------------------------------------- report
def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--prom", help="Prometheus base URL")
    ap.add_argument("--days", type=int, default=30, help="days to fetch (retention is 31d)")
    ap.add_argument("--tz", default="America/Chicago")
    ap.add_argument("--flip-hour", type=int, default=3, help="local hour the switchback flips")
    ap.add_argument(
        "--min-cdh", type=float, default=50, help="skip mild days below this many degree-hours"
    )
    ap.add_argument("--cooling-days-per-year", type=int, default=200, help="for annualizing")
    ap.add_argument("--csv", help="accumulate daily rows here and analyze the union")
    ap.add_argument("--self-test", action="store_true", help="check the statistics and exit")
    a = ap.parse_args()

    if a.self_test:
        return self_test()
    if not a.prom:
        ap.error("--prom is required (or use --self-test)")

    tz = ZoneInfo(a.tz)
    fetched = collect(a.prom, a.days, tz, a.flip_hour)
    if a.csv:
        rows = merge_rows(load_csv(a.csv), fetched)
        write_csv(a.csv, rows)
        print(f"accumulated {len(rows)} rows in {a.csv} (fetched {len(fetched)} from Prometheus)\n")
    else:
        rows = fetched
    if not rows:
        print("No data. Are the hvac:* recording rules loaded and HA being scraped?")
        return 1

    now = dt.datetime.now(tz)
    kw = query(a.prom, "hvac:cooling_kw", now)
    rate = query(a.prom, "hvac:marginal_rate_usd_per_kwh", now).get("", 0.12)

    print(f"Window: last {a.days} days ending {a.flip_hour:02d}:00 {a.tz}; "
          f"days below {a.min_cdh:g} CDH skipped\n")
    snippet = []
    total_day = 0.0
    for entity in sorted({r["entity"] for r in rows}):
        res = analyze_entity([r for r in rows if r["entity"] == entity], a.min_cdh)
        print(f"== {entity}")
        print(f"   usable days: {res['n_on']} ON, {res['n_off']} OFF")
        if res["status"] != "ok":
            print("   not enough days in each arm yet (need 5+ each)\n")
            continue
        k = kw.get(entity, 0.0)
        usd_day = -res["effect_h"] * k * rate
        total_day += usd_day
        lo, hi = res["ci_h"]
        pct = -res["effect_h"] / res["mean_off_h"] * 100 if res["mean_off_h"] > 0 else float("nan")
        verdict = "real" if res["significant"] else "not yet distinguishable from noise"
        print(f"   runtime effect: {res['effect_h']:+.2f} h/day (90% CI {lo:+.2f} … {hi:+.2f}) → {verdict}")
        print(f"   ≈ {pct:.0f}% of control-day runtime, ≈ ${usd_day:.2f}/day at {k:g} kW × ${rate:.3f}/kWh")
        print(f"   comfort (occupied, ±1°F): ON {res['comfort_on']:.0%} vs OFF {res['comfort_off']:.0%}")
        if not res["significant"]:
            print(f"   to resolve a 10% effect: ~{res['n_needed_per_arm']} usable days per arm")
        print()
        snippet += [
            f"        - record: hvac:baseline_intercept_h\n"
            f"          expr: vector({res['baseline_a']:.4f})\n"
            f"          labels: {{entity: {entity}}}",
            f"        - record: hvac:baseline_slope_h_per_cdh\n"
            f"          expr: vector({res['baseline_b']:.6f})\n"
            f"          labels: {{entity: {entity}}}",
        ]

    if total_day:
        print(f"Combined: ≈ ${total_day:.2f}/day → ≈ ${total_day * a.cooling_days_per_year:.0f}/yr "
              f"over {a.cooling_days_per_year} cooling days\n")
    if snippet:
        print("Baseline constants for prometheusrule.yaml (hvac.constants group), fitted on OFF days:")
        print("\n".join(snippet))
    return 0


if __name__ == "__main__":
    sys.exit(main())