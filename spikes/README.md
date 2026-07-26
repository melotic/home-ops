# Stateful service spikes

| Spike | Verdict | Recommendation |
|---|---|---|
| [001: Central Meilisearch](./001-central-meilisearch/README.md) | VALIDATED | Run one shared Meilisearch in `database`; isolate apps with index-scoped API keys. |
| [002: Dragonfly Operator](./002-dragonfly-operator/README.md) | PARTIAL | Keep Dragonfly, adopt its official operator after an isolated failover/cutover rehearsal. Do not switch engines. |
| [003: FerretDB for LibreChat](./003-ferretdb-librechat/README.md) | PARTIAL | Replace bundled MongoDB now, before user data exists, using FerretDB plus a separate CNPG DocumentDB cluster. |

## Order

1. FerretDB now: LibreChat has zero users, conversations, and messages, so rollback is cheap.
2. Centralize Meilisearch: both applications are already on v1.50.0 and their index names do not collide.
3. Operator-manage Dragonfly: it has the largest blast radius and needs a rehearsed state transfer.
