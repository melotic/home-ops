# Kyverno Cluster Policies

ClusterPolicies and typed PolicyExceptions for the cluster's security posture. Every
policy here is in **Audit** mode (report-only) unless explicitly promoted. This document
records *why* each policy stays in Audit (KYV-05) and the runbook for promoting a policy
to Enforce per-rule with rollback granularity preserved (KYV-04).

## Disposition buckets

Every residual Audit finding falls into exactly one of three buckets:

| Bucket | Meaning | Where it lives |
|--------|---------|----------------|
| **Manifest fix** | The workload can be hardened to pass (add `securityContext`, `tmp` emptyDir, non-root user). | The app's own HelmRelease/manifest |
| **Typed exception** | The workload legitimately cannot comply; the violation is accepted-risk and scoped to the exact failing rule. | `app/exceptions/*.yaml` (in the `kyverno` namespace, where exceptions are honored) |
| **Leave in Audit** | The policy is metrics-only or cannot be Enforced; it surfaces signal but never blocks. | Documented below |

## How to query the census

The census is the live set of PolicyReport results. It is **reproducible from metrics**,
not from a committed script or a hand-authored dashboard.

- **VictoriaMetrics / Grafana** — policy-reporter ships its own metrics and
  `GrafanaDashboard` CRs (Grafana folder **"kyverno"**). Query:

  ```promql
  # full census, grouped
  sum by (policy, rule, status, namespace) (policy_report_result)
  # fail-only variant
  sum by (policy, rule, namespace) (policy_report_result{status="fail"})
  ```

- **policy-reporter UI** — <https://policy-reporter.melotic.dev> for ad-hoc browsing.

- **Ad-hoc kubectl snapshot** (no metrics needed):

  ```bash
  kubectl get policyreport,clusterpolicyreport -A -o json \
    | jq -r '.items[].results[]? | select(.result=="fail") | "\(.policy)\t\(.rule)"' \
    | sort | uniq -c | sort -rn
  ```

> Background-scan report entries lag pod entries. Restarting
> `kyverno-background-controller` + `kyverno-reports-controller` forces an immediate
> rescan instead of waiting out the 1h interval.

## Policies intentionally left in Audit (KYV-05)

Each rationale below is **case-specific** and is also pinned to the policy resource via a
`home-ops.melotic.dev/audit-rationale` annotation (closure is paired doc + annotation, not
README-only).

| Policy | Why it stays in Audit |
|--------|-----------------------|
| `require-image-digest-pin` (02) | Metrics-only. Renovate owns remediation via a surgical `pinDigests` rule that pins container images (`helmrelease.yaml`) but deliberately not chart OCI refs (`ocirepository.yaml`). Flipping to Enforce would block every Helm chart upgrade. |
| `require-non-root-and-readonly-fs` (03) | Large legitimate-exception surface (rook-ceph daemons, s6/LSIO apps, host-net infra). Per-namespace/per-rule exceptions must dwell clean before any promotion; promote per-rule only after the exception set is stable. |
| `require-network-policy-per-namespace` (04) | **Can never be Enforced** (CR-02). A Namespace is admitted as a single object before any NetworkPolicy can exist inside it, so an admission-time check always sees zero NetworkPolicies and would permanently block all namespace creation. Background-scan-only by design. |
| `verify-image-signature-cosign` (06) | Trust roots not yet nailed down. The current `subject:` is a wildcard that accepts any GitHub repo's signature (WR-06); `required: true` / Enforce is unsafe until the subject is narrowed and a tested verifier endpoint is in place. |

The remaining live `fail` results are **only** these documented Audit leftovers
(`require-image-digest-pin`, `verify-image-signature-cosign`,
`require-network-policy-per-namespace`) — deliberate signal, not noise.

## Enforce promotion runbook (KYV-04)

Promotion is **per policy/per rule, after a clean dwell window, with rollback granularity
preserved.** No policy is promoted as part of documenting this runbook.

### Mechanism — reversible, per-rule

Prefer a per-rule override to flipping the whole policy. This keeps every other rule in
Audit and makes rollback a one-line `git revert`:

```yaml
spec:
  validationFailureAction: Audit
  validationFailureActionOverrides:
    - action: Enforce
      rules: [check-no-host-namespaces]   # only this rule enforces; others stay Audit
```

Whole-policy promotion (`validationFailureAction: Enforce`) is also supported but loses
per-rule granularity; only use it for single-rule policies.

### Dwell criteria (must all hold before flipping)

1. **0 residual fails** for the target rule, sustained across the dwell window — re-query
   the census:
   ```promql
   sum by (rule) (policy_report_result{policy="disallow-host-namespaces", status="fail"})
   ```
   or the ad-hoc `kubectl get policyreport,clusterpolicyreport -A -o json | jq ...` snapshot.
2. **No new in-scope workload** appeared during the window (e.g. no new host-namespace
   pod for `disallow-host-namespaces`).
3. The exceptions covering the rule are stable (no recent widening).

### Rollback

`git revert` the commit that added the `validationFailureActionOverrides` entry. Flux
reconciles the policy back to Audit within the reconcile interval.

### `disallow-host-namespaces` (05) — promotion-ready, flip deferred

This is the only near-term promotion candidate. As of the Phase 20 census it shows
**0 residual fails**: the only host-namespace workloads are node-exporter and the
Rook-Ceph CSI **nodeplugins** (which require host network to mount devices on the node),
all covered by `app/exceptions/host-namespace-infra.yaml`. The CSI **controller plugins**
run on the pod network (`controllerPlugin.hostNetwork: false`) and do not trip the policy.

The policy carries a `home-ops.melotic.dev/promotion-readiness` annotation noting this.
The **live Enforce flip is an explicit deferred follow-up** — it must wait for a clean
dwell window and must NOT ship in the same change that documents this readiness.
