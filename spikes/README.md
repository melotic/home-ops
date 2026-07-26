# Stateful service spikes

| Spike | Verdict | Recommendation |
|---|---|---|
| [001: Central Meilisearch](./001-central-meilisearch/README.md) | ACCEPTED | Centralize in `database`; the operational consolidation is worth the known shared failure and upgrade boundary. |
| [002: Dragonfly Operator](./002-dragonfly-operator/README.md) | ACCEPTED | Keep Dragonfly and migrate the shared instance to its official operator with three replicas. |
| [003: FerretDB for LibreChat](./003-ferretdb-librechat/README.md) | REJECTED | Keep MongoDB. FerretDB requires another PostgreSQL cluster, which costs more complexity than it removes. |

## Order

1. Centralize Meilisearch and move Karakeep and LibreChat to it.
2. Install the Dragonfly Operator, prove failover and restore, then migrate the shared service.
3. Keep LibreChat's bundled MongoDB.
