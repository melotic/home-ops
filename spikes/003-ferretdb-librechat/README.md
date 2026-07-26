# 003: FerretDB for LibreChat

## Question

Given LibreChat v0.8.7 expects MongoDB, when pointed at FerretDB v2.7.0 backed by PostgreSQL DocumentDB, then does it start and expose a healthy API without compatibility errors?

## Experiment

A disposable Podman network ran:

- `ghcr.io/ferretdb/postgres-documentdb:17-0.107.0-ferretdb-2.7.0`
- `ghcr.io/ferretdb/ferretdb:2.7.0`
- `ghcr.io/danny-avila/librechat:v0.8.7`

LibreChat used `mongodb://username:password@ferretdb:27017/LibreChat`.

Observed result:

```text
LibreChat v0.8.7 + FerretDB v2.7.0 startup/health: pass
health=OK
ferretdb_warnings=0
librechat_db_errors=0
```

The containers were destroyed after the test.

## Supporting evidence

- FerretDB v2.7 explicitly lists LibreChat as a tested compatible application: [compatible applications](https://github.com/FerretDB/FerretDB/blob/v2.7.0/website/versioned_docs/version-v2.7/compatible-applications/applications.js).
- Current LibreChat source includes FerretDB-specific multitenancy and deadlock-retry tests.
- FerretDB supports the normal CRUD, aggregation, and index commands LibreChat uses: [compatibility matrix](https://github.com/FerretDB/FerretDB/blob/v2.7.0/website/versioned_docs/version-v2.7/migration/compatibility.md).
- MongoDB transaction commit/abort commands remain unsupported. LibreChat probes transaction support and falls back when unavailable.
- FerretDB v2 requires PostgreSQL with the DocumentDB extension. It cannot simply use the existing minimal PostgreSQL image. The supported CNPG shape uses a separate cluster image, preload libraries, and extension bootstrap: [FerretDB + CNPG guide](https://github.com/FerretDB/FerretDB/blob/v2.7.0/website/blog/2025-04-11-run-ferretdb-postgres-documentdb-extension-cnpg-kubernetes.md).
- There is no official FerretDB Kubernetes operator. The clean stack is the existing CloudNativePG operator for the backend plus an app-template Deployment for the stateless FerretDB proxy.

## Current migration risk

The live LibreChat database has zero users, conversations, messages, files, presets, agents, and sessions. Only bootstrap roles/grants/categories exist. This is the cheapest possible migration window; rebuilding bootstrap data is safer than carrying the bundled MongoDB forward.

## Proposed target

- A separate CNPG `Cluster` in `database` using the matching FerretDB PostgreSQL DocumentDB image.
- Start with three instances if this is intended to improve availability, not merely change database brands.
- Barman backups and monitoring through the existing CNPG stack.
- A two-replica stateless FerretDB app-template workload and ClusterIP service.
- LibreChat `mongodb.enabled: false` and `MONGO_URI` pointed at FerretDB.
- Disable FerretDB telemetry explicitly.

## Remaining check

The startup test did not exercise an authenticated login, conversation creation, message search, agent permissions, or restore. Before production, run one contained E2E flow against the candidate stack and verify a CNPG backup/restore.

## Verdict: PARTIAL

The replacement is technically viable and upstream-supported. Do it now, before LibreChat accumulates user data, but gate the cutover on one login/conversation/search E2E and a backup/restore check.
