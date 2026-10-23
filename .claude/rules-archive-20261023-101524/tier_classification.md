---
paths:
  - src/lang/**
  - src/runtime/host/**
  - data/compat_tiers.yaml
---

# Tier classification discipline

## Rule

Every public function and type carries a tier classification A / B / C / D
(per `data/compat_tiers.yaml` and ADR-0013).

Tier D forms raise a per-form catalog Code (`tier_d_gen_class` /
`tier_d_gen_interface` / `tier_d_compile` / `tier_d_proxy_deep` /
`tier_d_bean_deep`); each Code carries a hand-written multi-sentence
template. The canonical naming + template-content spec lives in
**ADR-0018 amendment 2** (= the catalog SSOT); the Tier label (D)
and rationale ADR (ADR-0013) live in `data/compat_tiers.yaml`; neither
the label nor the ADR identifier appears in user-facing text.

## Why

- Tier classification is the cw v1 contract with users.
- Users see a structured signal for each unsupported feature.
- Tier promotion (e.g., D -> C) requires explicit ADR amendment.

## How to apply

- New function: add entry to `data/compat_tiers.yaml`, include tier in
  docstring.
- Tier D function: error message format per the rule.
- Tier promotion: amend `data/compat_tiers.yaml` + ADR.

## Tier promotion / demotion

- D -> any: MAJOR release required (per ROADMAP §1.4 SemVer rule).
- A -> A (no change), A -> B: MAJOR.
- B -> A: MINOR.
- C -> A or C -> B: MINOR.
- A or B -> D: forbidden (would break Clojure source compatibility).
