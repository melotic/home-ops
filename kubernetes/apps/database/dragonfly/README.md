# Dragonfly (shared Redis)

Single Dragonfly instance replacing per-app Redis pods. Configured with `--dbnum 16` (indexes 0-15).

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

Next available: **8** (bump `--dbnum` in the HelmRelease if you need more than 16)

## Adding a new service

Pick the next free index, update this table, and point the app at `dragonfly.database.svc.cluster.local:6379` with the allocated index. Some apps take a `redis://` URL with the DB in the path (Forgejo, Paperless), others use separate host/port and index fields (Harbor).

## Notes

- Authentik 2025.10+ dropped Redis entirely, uses Postgres for everything.
- Harbor used to run its own `harbor-redis` StatefulSet. Removed when we switched to Dragonfly.
- Dragonfly is wire-compatible with Redis.
