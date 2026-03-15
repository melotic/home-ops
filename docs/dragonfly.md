# Dragonfly (shared Redis)

We run a single Dragonfly instance (`dragonfly.database.svc.cluster.local:6379`) instead of per-app Redis pods. Each component gets its own DB index so they don't step on each other.

Dragonfly is configured with `--dbnum 16`, so valid indexes are **0–15**.

## DB Index Allocation

| Index | Service | Component |
|-------|---------|-----------|
| 0 | Paperless-ngx | Task queue, caching |
| 1 | Harbor | Core |
| 2 | Harbor | Job service |
| 3 | Harbor | Registry |
| 4 | Harbor | Trivy adapter |
| 5 | Forgejo | Cache |
| 6 | Forgejo | Sessions |
| 7 | Forgejo | Task queue |

Next available: **8** (max 15 — bump `--dbnum` in the Dragonfly HelmRelease if you need more)

## Adding a new service

Pick the next available index and update this table. Point the service at `dragonfly.database.svc.cluster.local:6379` with the allocated index. How you set the index depends on the app — some take a `redis://` URL with the DB number in the path (e.g. Forgejo, Paperless), others use separate host/port and index fields (e.g. Harbor's `addr` + `*DatabaseIndex` values).

## Notes

- Authentik (2025.10+) doesn't use Redis at all — it migrated everything to Postgres.
- Harbor previously ran its own `harbor-redis` StatefulSet. That was removed when we switched to Dragonfly.
- Dragonfly is wire-compatible with Redis, so standard `redis://` connection strings work everywhere.
