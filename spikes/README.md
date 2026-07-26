# Stateful service spikes

| Spike | Verdict | Recommendation |
|---|---|---|
| [001: Central Meilisearch](./001-central-meilisearch/README.md) | REJECTED | Keep application-owned instances. Sharing saves one small pod but couples failures, upgrades, tasks, credentials, and restores. |
| [002: Dragonfly Operator](./002-dragonfly-operator/README.md) | PARTIAL | Harden and restore-test Dragonfly first. Use its official operator only when automatic node-loss failover justifies three replicas. |
| [003: FerretDB for LibreChat](./003-ferretdb-librechat/README.md) | PARTIAL | Compatibility is real, but require a production-shaped E2E and restore test before replacing MongoDB. |

## Order

1. Fix Dragonfly durability now: schedule and replicate snapshots, alert on snapshot age, then prove restore.
2. Run a production-shaped FerretDB E2E while LibreChat still has no user data.
3. Split durable/job-like Dragonfly users from disposable caches before deciding whether HA needs an operator.
4. Leave each Meilisearch instance with its application.
