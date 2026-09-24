# ADR 0008: OpenObserve for Log Aggregation

## Status

Accepted

## Context

[ADR 0007](0007-observability-stack.md) chose Loki for log aggregation.
Loki works, but its only interface is Grafana's Explore view (LogQL) --
there is no dedicated log-search UI with a field-facet sidebar, histogram,
and one-click filters (the "Discover tab" experience familiar from
OpenSearch Dashboards/Kibana). OpenObserve provides exactly that in its own
built-in UI, as a single self-contained binary -- no second cluster of
components to run alongside Loki, since it replaces it rather than
supplementing it.

OpenObserve's **official Helm chart** (`openobserve/openobserve`, checked at
every published version from 0.80.x through the current 1.0.2) turned out to
be unusable for this cluster: it is HA/microservices-only (separate
ingester/querier/compactor/router/scheduler components), requires a
CloudNativePG-managed Postgres cluster as its metadata store, and mandates
an external S3-compatible object store -- there is no chart-exposed path to
the single-binary local-disk mode the product also supports. Adding a
Postgres operator and an object store just to run a log viewer would be the
same class of overkill this project already avoided elsewhere (Zabbix was
dropped from `TODO.md` for the same reason: enterprise-scale tooling on a
single-node homelab).

## Decision

Replace Loki with a **hand-written standalone OpenObserve Deployment**
(`apps/core/openobserve/`, no Helm chart), running OpenObserve's
single-binary local-disk mode (`ZO_LOCAL_MODE=true`, the product's own
default), matching Loki's prior SingleBinary-mode simplicity: one
container, `emptyDir` storage, no external dependencies.

This is the same "hand-written manifests, no `helmCharts` block" pattern
already used in this repo for `apps/core/gateway`, `apps/core/coredns-custom`,
and `apps/core/argocd` -- not a new pattern.

Alloy's `loki.write` component (`apps/core/alloy/values.yaml`) is repointed
at OpenObserve's Loki-push-API-compatible ingestion endpoint
(`POST /api/{organization}/loki/api/v1/push`, HTTP Basic Auth) instead of
Loki's own push endpoint -- no change to Alloy's log-collection pipeline
itself, only the destination URL and added credentials.

## Consequences

### Positive

- Dedicated log-search UI (field facets, histogram, saved searches) without
  adopting a heavier stack.
- No new dependency surface: still a single container, still ephemeral
  `emptyDir` storage (same tradeoff already accepted for Loki and
  VictoriaMetrics on this cluster's lack of a dynamic StorageClass).
- Alloy's collection pipeline is untouched; only the write destination
  changes.

### Negative

- Hand-written manifests instead of a maintained chart -- no upstream
  Kustomize/Helm upgrade path; version bumps mean re-checking the
  Deployment manually against release notes.
- Diverges from the official Helm chart's (much heavier) supported
  topology -- if this cluster ever needs OpenObserve's HA mode (multi-node,
  durable long-term retention), that's effectively a from-scratch
  migration, not an upgrade.
- Grafana's OpenObserve datasource plugin is not confirmed to be published
  on grafana.com's plugin catalog; if it can only be installed as an
  unsigned plugin, Grafana keeps VictoriaMetrics for metrics/alerts while
  log search happens in OpenObserve's own UI directly -- acceptable, but
  means log data isn't necessarily correlated inside Grafana panels.

## Review Criteria

Revisit if:

- OpenObserve ships a lighter/local-disk-mode Helm chart upstream.
- Log volume or retention needs outgrow a single ephemeral-storage
  container (would need the HA chart's Postgres + object-store topology
  after all).
- A dynamic StorageClass is added to this cluster, changing the
  ephemeral-storage tradeoff calculus for every component that currently
  accepts it.
