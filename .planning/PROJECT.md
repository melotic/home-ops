# home-ops

## What This Is

`home-ops` is the GitOps source of truth for the Zion Talos/Kubernetes home cluster that runs self-hosted media, automation, networking, storage, and observability services. This brownfield initiative focuses on evolving that existing platform into a leaner, more reliable, and more predictable system to operate, with better CI/CD, clearer signals when changes are safe to merge, and stronger network isolation for sensitive workloads.

## Core Value

The cluster must stay efficient, observable, and safe to change, even when hardware fails or workloads move.

## Requirements

### Validated

- ✓ Talos machine configuration and Kubernetes bootstrap are managed declaratively from this repository — existing
- ✓ FluxCD reconciles cluster and application state from Git across multiple namespaces and shared components — existing
- ✓ Self-hosted services already run on the cluster for media, automation, monitoring, networking, and supporting platform needs — existing
- ✓ Secrets are handled through SOPS/age and External Secrets rather than storing plaintext credentials in Git — existing
- ✓ Shared storage, databases, ingress/gateway, and observability foundations are already part of the platform baseline — existing
- ✓ Pull requests already run rendered-manifest validation, giving the project a starting point for stronger deployability checks — existing

### Active

- [ ] Replace Forgejo with a slimmer self-hosted GitLab deployment and migrate existing repositories without exposing sensitive code to GitHub
- [ ] Right-size resource requests, limits, and placement so the cluster schedules workloads reliably and uses hardware capacity more efficiently
- [ ] Improve alerting, dashboards, and metrics/log visibility so failures are obvious and actionable instead of guesswork
- [ ] Introduce Multus-backed VLAN segmentation so selected workloads can attach to dedicated networks such as IoT and VPN-oriented paths
- [ ] Reduce media-service fragility caused by Plex depending on the Intel node and improve resilience when that node is unavailable
- [ ] Reduce duplication and improve drift/prune behavior so GitOps changes are easier to reason about and safer to reconcile

### Out of Scope

- None yet — keep the initial roadmap open until the phase breakdown reveals clear deferrals

## Context

The repository already manages a heterogeneous three-node Talos control plane, with one Intel node (`k8s-trinity`) and two AMD nodes (`k8s-niobe`, `k8s-ghost`). Existing pain points are operational rather than foundational: resource requests and limits appear too high, scheduling is fragile, observability and alerting are weak, VictoriaLogs does not have a clear role, and GitOps drift/prune behavior plus duplicated configuration make changes harder to trust.

The project is also motivated by workflow and privacy constraints. Sensitive code should remain self-hosted, so the repository migration target needs to stay local rather than relying on GitHub as the system of record. The existing Forgejo setup is not delivering the CI/CD confidence needed, and one of the desired outcomes is knowing from a pull request whether a change will actually deploy cleanly.

`onedr0p/home-ops` is a reference point for proven patterns, but this project should adapt ideas selectively to fit the current cluster, hardware, and workload mix rather than copying them blindly.

## Constraints

- **Platform**: Must build on the existing Talos + FluxCD GitOps foundation — the goal is to improve a working brownfield platform, not replace it wholesale
- **Privacy**: Sensitive repositories must remain self-hosted/local — migration choices cannot depend on even private GitHub hosting
- **Hardware**: The cluster is heterogeneous, with Plex currently tied to Intel GPU capability on `k8s-trinity` — scheduling and resilience work must respect node-specific capabilities
- **Operational safety**: Pull requests and reconciliation flows need to provide trustworthy deployability signals before merge — cleanup around drift, prune, and duplication should improve confidence, not just aesthetics

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Replace Forgejo with a slimmer GitLab deployment | The current self-hosted CI/CD experience is insufficient, but sensitive code still needs to remain local | — Pending |
| Prioritize resource right-sizing and scheduling reliability first | Cluster efficiency and scheduling pain are the main drivers and affect every other improvement track | — Pending |
| Keep observability, network segmentation, media resilience, and GitOps hygiene in the same active initiative | These issues compound operational fragility and should be planned together even if delivered in separate phases | — Pending |
| Use `onedr0p/home-ops` as inspiration when it offers proven patterns | External inspiration is useful, but the current repo and hardware constraints still determine the final design | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-04-24 after initialization*
