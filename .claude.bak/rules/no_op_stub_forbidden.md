---
paths:
  - src/**/*.zig
  - src/lang/clj/**
  - src/runtime/host/**
---

# Permanent no-op forbidden — transient stubs OK

> Folded into [`provisional_marker.md`](provisional_marker.md) §
> "Skeleton vs transient stub vs PROVISIONAL vs permanent no-op"
> at Wave 16 W16-6 (2026-05-26). This file remains as a path-
> frontmatter pointer so editors of `src/**/*.zig` /
> `src/lang/clj/**` keep auto-loading the time-axis distinction
> ("final shape" vs "development trajectory") that the original
> 2026-05-23 rename surfaced.

## Canonical rule (one sentence)

> **No Tier A / B / C feature may ship in a form where the user
> sees success while the runtime silently drops the intended
> semantics.**

The 4-row boundary table (Skeleton OK / Transient stub OK /
PROVISIONAL-with-triad OK / Permanent no-op NG) lives in
[`provisional_marker.md`](provisional_marker.md) § "Skeleton vs
transient stub vs PROVISIONAL vs permanent no-op". See also:

- `scripts/check_no_op_stub.sh` — heuristic scan (informational
  per W16-2 cleanup).
- ADR-0004 / ADR-0012 / ADR-0023 — skeleton-then-rewrite
  endorsement.
- ADR-0018 amendment 2 — Tier D / sub-feature staged `feature_not_supported`
  template contract.

## Revision history

- **2026-05-26 (Wave 16 W16-6)**: body folded into
  `provisional_marker.md`; this file becomes a 30-line pointer.
- 2026-05-23: original rename "No-op stub forbidden" → "Permanent
  no-op forbidden — transient stubs OK" (made the time-axis
  explicit).
