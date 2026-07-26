# 001: Central Meilisearch

## Question

Given Karakeep and LibreChat each run Meilisearch v1.50.0, when they use one instance in `database`, then can they remain isolated without creating a worse operational boundary?

## Evidence

- Karakeep runs Meilisearch as a sidecar and uses the fixed `bookmarks` index. Live state: one index, about 42 MB used.
- LibreChat uses fixed `convos` and `messages` indexes in v0.8.7. Its new instance currently has no indexes and about 20 KB used.
- Both clients already accept a remote URL and API key: Karakeep uses `MEILI_ADDR`/`MEILI_MASTER_KEY`; LibreChat uses `MEILI_HOST`/`MEILI_MASTER_KEY`.
- Meilisearch API keys can restrict actions and indexes. The master key should only manage keys, not be shared with applications: [Meilisearch key model](https://www.meilisearch.com/docs/learn/security/master_api_keys).
- Tenant tokens are search-only and do not isolate indexing/settings operations, so they are not the right boundary between these two backends: [tenant tokens](https://www.meilisearch.com/docs/learn/security/tenant_tokens).
- Current requests total 125m CPU and 512 MiB memory, with 2 GiB combined memory limits. A shared 100m/512 MiB instance removes one container and 1 GiB of combined limit without materially changing requested memory.
- Both indexes are derived state. Karakeep can rebuild `bookmarks` from SQLite; LibreChat can rebuild `convos` and `messages` from its document database.

## Risks

- A shared restart affects both applications.
- A shared master key would let either app alter or delete the other's indexes.
- Upgrade cadence becomes shared, although both are already on the same release.
- Karakeep currently backs its index up with the app PVC. Centralization must either add a Meilisearch dump/snapshot job or explicitly treat indexes as rebuildable caches.

## Accepted tradeoff

- One process couples CPU, memory, the [serial task queue](https://www.meilisearch.com/docs/capabilities/indexing/tasks_and_batches/async_operations), upgrades, and backups.
- Both applications receive the shared master key initially because their upstream integrations expect `MEILI_MASTER_KEY`.
- [Dumps and snapshots](https://www.meilisearch.com/docs/learn/data_backup/snapshots_vs_dumps) cover the entire instance rather than one application.
- This is acceptable here because both indexes are small, derived, rebuildable, and currently use the same Meilisearch release.

## Minimal production shape

- One app-template Meilisearch workload in `database`.
- One master key from 1Password consumed by both applications.
- Karakeep points `MEILI_ADDR` at the shared service and drops its sidecar.
- LibreChat disables its bundled Meilisearch dependency and sets `MEILI_HOST` explicitly.
- Treat indexes as rebuildable projections. Back up Karakeep SQLite/assets and LibreChat's MongoDB data rather than the shared search index.

## Decision: ACCEPTED

Centralize it in `database`. This knowingly accepts a shared failure, task, upgrade, and restore boundary in exchange for one managed search service and removal of duplicate application-owned deployments. Karakeep uses `bookmarks`; LibreChat uses `convos` and `messages`, so current index names do not collide.
