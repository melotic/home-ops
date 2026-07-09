# Firefly III — Operator Handoff & SimpleFIN Setup

Self-hosted personal finance on the Zion cluster, wired to Hermes for
MCP queries and event-driven transaction classification.

## What's deployed

| Component | Endpoint / Location | Status |
|---|---|---|
| Firefly III core | `https://firefly.melotic.dev` | Running (2/2 pod) |
| Data Importer | `https://firefly-import.melotic.dev` | Running (1/1 pod) |
| MCP server (219 tools) | `https://firefly-mcp.melotic.dev/mcp` | Running (in core pod) |
| Postgres DB | CNPG `firefly` db + role | Applied |
| Secrets | 1Password vault **Zion**, items `firefly` + `firefly-postgres` | Synced |
| Hermes MCP | `mcp_servers.firefly` in config.yaml | Connected, 219 tools |
| Hermes webhook | `firefly-txn` → classify/reconcile loop | Subscribed |
| Tailscale Serve | `/hooks/firefly-txn` → `127.0.0.1:8644` | Live |

Manifests: `kubernetes/apps/default/firefly/`. Shipped via GitOps
(PRs #1698, #1700, #1701, #1702, #1703, #1704).

## Admin account (already created)

The admin account was bootstrapped during deployment:
- Email: `justinmp215@gmail.com`
- Password: **1Password → Zion → `firefly` → `ADMIN_PASSWORD`**

A Firefly Personal Access Token was also created and stored at
**1Password → Zion → `firefly` → `FIREFLY_PAT`**. The Data Importer and
MCP server use it automatically (synced from 1Password every 5 min).

## The ONE thing you must do: connect SimpleFIN

SimpleFIN is the read-only bank feed. It physically cannot move money —
by protocol there is no write path back to your bank.

### Step 1 — Get your SimpleFIN token (~5 min, ~$15/yr)
1. Go to **https://bridge.simplefin.org** and sign up.
2. Click **Add Account** for each institution. All confirmed supported:
   - USAA, Ally Bank, American Express, Chase, Wealthfront
3. Complete each bank's OAuth/credential handoff (SimpleFIN never shares
   your bank password downstream).
4. Click **Get API Access** → copy the **one-time setup token**
   (a long base64 string). It is consumed on first use — save it now.

### Step 2 — Store the token
Paste it into **1Password → Zion → `firefly` → field `SIMPLEFIN_TOKEN`**,
replacing the `REPLACE_ME_paste_SimpleFIN...` placeholder.

Within 5 minutes the ExternalSecret syncs it into the cluster. The
importer picks it up automatically (it has `reloader` auto-restart).

### Step 3 — Run the first import
1. Open **https://firefly-import.melotic.dev**
2. Choose **SimpleFIN** (the token is read from env).
3. Select the accounts to import. First import pulls ~90 days.
4. **CRITICAL SETTING — Duplicate Detection → "Content-based"**
   (NOT the default "Identifier-based"). SimpleFIN's transaction IDs are
   unstable; identifier-based detection silently drops most transactions.

### Step 4 — Wire the reconcile webhook (in Firefly, one-time)
Firefly UI → **Options → Webhooks → New webhook**:
- Trigger: **After transaction creation**
- Response: **Transaction details**
- URL: `https://disco-ninja.tail88eb4.ts.net/hooks/firefly-txn`
- Secret: **1Password → Zion → `firefly` → `WEBHOOK_SECRET`**

Now every new transaction fires → Hermes classifies + reconciles it →
replies in Discord.

## Load the MCP tools into the live Hermes agent

The MCP server is configured and connection-tested, but the running
gateway must restart once to load the 219 tools into the live session
(the agent cannot restart itself from inside the gateway):

```bash
hermes gateway restart
```

After that, ask Hermes things like "what's my net worth" or "why is $88k
sitting in checking" and it answers off real synced data.

## Recurring bank re-auth
Banks periodically require re-authentication. If a feed goes stale,
re-auth that institution from the SimpleFIN dashboard. No changes needed
on the Hermes/cluster side.

## Security notes
- SimpleFIN is read-only upstream: no MCP tool can move real money. Worst
  case from a bad tool call is a recoverable local-ledger edit that
  re-syncs from the bank feed. That is why the MCP tool surface is
  unfiltered (all 219 tools).
- `firefly-mcp.melotic.dev` is served via envoy-internal (private
  `10.60.88.1`, tailnet/LAN-only, NOT internet-facing) — same trust
  boundary as the Firefly UI.
- Do NOT rotate `APP_KEY` casually: it encrypts Firefly's stored fields;
  rotating makes them unreadable.

## 1Password `firefly` item — field reference
| Field | Purpose | Set by |
|---|---|---|
| `APP_KEY` | Firefly encryption key | auto (valid) |
| `STATIC_CRON_TOKEN` | Firefly cron auth | auto (valid) |
| `FIREFLY_PAT` | Importer + MCP auth to Firefly | **bootstrapped** |
| `MCP_BEARER_TOKEN` | reserved | auto (valid) |
| `WEBHOOK_SECRET` | webhook HMAC + importer autoimport | auto (valid) |
| `ADMIN_EMAIL` / `ADMIN_PASSWORD` | Firefly login | **bootstrapped** |
| `SIMPLEFIN_TOKEN` | bank feed | **← YOU replace this** |
