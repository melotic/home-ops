# Stateful service spikes

| Spike | Verdict | Recommendation |
|---|---|---|
| [001: Central Meilisearch](./001-central-meilisearch/README.md) | REJECTED | Keep Karakeep and LibreChat Meilisearch instances application-owned. |
| [002: Dragonfly Operator](./002-dragonfly-operator/README.md) | ACCEPTED | Keep Dragonfly and migrate the shared instance to its official operator with three replicas. |
| [003: FerretDB for LibreChat](./003-ferretdb-librechat/README.md) | REJECTED | Keep MongoDB. FerretDB requires another PostgreSQL cluster, which costs more complexity than it removes. |

## Order

1. Restore Karakeep and LibreChat to their application-owned Meilisearch instances.
2. Install the Dragonfly Operator, prove failover and restore, then migrate the shared service.
3. Keep LibreChat's bundled MongoDB.
