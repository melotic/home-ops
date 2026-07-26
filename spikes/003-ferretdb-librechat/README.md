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
- LibreChat merged [explicit FerretDB compatibility work](https://github.com/danny-avila/LibreChat/pull/11769), including multitenancy and deadlock-retry tests.
- FerretDB supports the normal CRUD, aggregation, and index commands LibreChat uses: [compatibility matrix](https://github.com/FerretDB/FerretDB/blob/v2.7.0/website/versioned_docs/version-v2.7/migration/compatibility.md).
- MongoDB transaction commit/abort commands remain unsupported. LibreChat probes transaction support and falls back when unavailable.
- Change streams remain unsupported, but LibreChat v0.8.7 does not use them in production paths.
- LibreChat's FerretDB suite covers 29 models and 98 custom indexes, but upstream excludes that suite from normal CI. Concurrent index creation has produced real deadlocks and relies on retry logic around [FerretDB issue #5167](https://github.com/FerretDB/FerretDB/issues/5167).
- FerretDB v2 requires PostgreSQL with the DocumentDB extension. It cannot simply use the existing minimal PostgreSQL image. The supported CNPG shape uses a separate cluster image, preload libraries, and extension bootstrap: [FerretDB + CNPG guide](https://github.com/FerretDB/FerretDB/blob/v2.7.0/website/blog/2025-04-11-run-ferretdb-postgres-documentdb-extension-cnpg-kubernetes.md).
- There is no official FerretDB Kubernetes operator. The clean stack is the existing CloudNativePG operator for the backend plus an app-template Deployment for the stateless FerretDB proxy.

## Rejected production shape

FerretDB would require a separate CNPG cluster using the matching PostgreSQL DocumentDB image, preload libraries, bootstrap SQL, storage, backups, and a stateless proxy. The existing general-purpose PostgreSQL cluster cannot safely host those extensions. Running that extra cluster costs more than retaining LibreChat's small bundled MongoDB instance, so no migration or further validation work is planned.

## Decision: REJECTED

Keep MongoDB. FerretDB compatibility is real, but v2 requires a separate PostgreSQL cluster with the DocumentDB extension. That adds a database cluster and proxy to remove one small MongoDB deployment, so it does not improve this homelab's operational shape.
