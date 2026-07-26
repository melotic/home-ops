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

## Minimal production shape

- One app-template Meilisearch workload in `database` at `meilisearch.database.svc.cluster.local:7700`.
- One master key held only by an administrative bootstrap job.
- Two application keys:
  - Karakeep: `bookmarks`
  - LibreChat: `convos`, `messages`
- Each key gets only search, document, index, and settings actions needed by that app.
- Keep a small Ceph PVC. Prefer tested rebuild procedures over treating the search index as primary data.
- Disable LibreChat's bundled subchart and Karakeep's sidecar after each app passes a search/reindex check.

## Verdict: VALIDATED

Centralize it. The index names are disjoint, both apps support a remote endpoint, and the data is reconstructable. The win is simpler upgrades and removal of the brittle LibreChat subchart, not large resource savings.
