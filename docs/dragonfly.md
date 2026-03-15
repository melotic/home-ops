# Dragonfly (shared Redis)

We run a single Dragonfly instance (`dragonfly.database.svc.cluster.local:6379`) instead of per-app Redis pods. Each service gets its own DB index so they don't step on each other.

## DB Index Allocation

| Index | Service | What it's used for |
|-------|---------|-------------------|
| 0 | Paperless-ngx | Task queue, caching |
| 1 | Harbor | Core |
| 2 | Harbor | Job service |
| 3 | Harbor | Registry |
| 4 | Harbor | Trivy adapter |
| 5 | Forgejo | Cache |
| 6 | Forgejo | Sessions |
| 7 | Forgejo | Task queue |

Next available: **8**

## Adding a new service

Pick the next available index and update this doc. Configure the service to point at `redis://dragonfly.database.svc.cluster.local:6379/<index>`.

## Notes

- Authentik (2025.10+) doesn't use Redis at all — it migrated everything to Postgres.
- Harbor previously ran its own `harbor-redis` StatefulSet. That was removed when we switched to Dragonfly.
- Dragonfly is wire-compatible with Redis, so standard `redis://` connection strings work everywhere.
