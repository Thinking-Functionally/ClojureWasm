# Project Rules (merged)

## bootstrap_essence
---
paths:
  - "src/**/*.zig"
  - "src/**/*.clj"
  - "src/lang/bootstrap.zig"
  - "src/eval/analyzer/**/*.zig"
  - "src/eval/backend/**/*.zig"
---
> Folded into [`provisional_marker.md`](provisional_marker.md) §
> "Why this rule exists" at Wave 16 W16-6 (2026-05-26). This file

## clojure_spec_citation
---
paths:
  - src/eval/**
  - src/lang/**
  - src/runtime/**
  - src/runtime/host/**
---
Each primitive function and special-form implementation carries a
docstring that cites canonical Clojure semantics.
Format:

## debt_dedup
---
paths:
  - .dev/debt.yaml
---
> `.dev/debt.yaml` is a structured YAML SSOT (ADR-0072 migration; 3 sections
> since the 2026-06-15 ledger audit): `active:` (actionable, drained
> easiest-first), `standing:` (epics/campaigns/capstones + the indefinitely-
> deferred future bucket — the loop does NOT auto-drain these), and
> `discharged:` (resolved/history). Each entry a mapping
> (`id` / `status` / `category` / `barrier` / optional `quality_floor` /

## exploration_vs_done
---
paths:
  - "**"
---
cw v1 has two modes of work:
- **Exploration**: free-form. Tracked files are not yet touched.
  Scratch lives in `private/notes/`, REPL sessions, throwaway
  `.clj` files. The only rule is "don't break the working tree".
- **Done**: tracked. A change lands in `src/` / `.dev/` /
  `.claude/` / `scripts/` / `test/` / `bench/` / `docs/ja/` /

## extended_challenge
---
paths:
  - "**"
---
The loop never stops on its own (CLAUDE.md § The only stop). The
only moment this rule fires is when the **user has just asked the
loop to stop** and the per-task note is being written to close
the session.
In that note, record 3 short items so the next session resumes
without spinning up cost:

## markdown_format
---
paths:
  - "**/*.md"
---
Auto-loaded when editing any `.md` file. Two concerns: pipe-table
alignment, and a small set of conventions for Markdown bodies.
Manual width calculation is the wrong tool. We have a CLI that mirrors
Emacs `markdown-mode`'s `markdown-table-align` exactly. After you finish
editing any pipe table, run:
```sh

## module_docstring
---
paths:
  - src/**/*.zig
---
Every new `.zig` source file under `src/` opens with two-line
boilerplate:
```zig
// SPDX-License-Identifier: EPL-2.0
//! One-line summary of what this module is for.
//! ...optional further `//!` lines describing the public contract.

## no_copy_from_v1
---
paths:
  - src/**/*.zig
  - bench/fixtures/**
  - test/**
---
Do not copy cw v0 (git tag `v0.5.0`) code verbatim.
Read v0 as a read-only reference and re-derive semantics in Zig 0.16
idiom.
- cw v0 carries 89K LOC of accumulated technical debt

## no_jvm_specific_assumption
---
paths:
  - src/**/*.zig
  - .dev/**/*.md
---
cw v1 is not a JVM reimplementation. Comments and docs do not assume:
- Class hierarchy (cw has TypeDescriptor, not Class).
- Object header layout matching JVM (cw has its own packed header per
  ADR-0009).
- Bytecode generation (cw has Opcode enum, not JVM .class files).

## no_op_stub_forbidden
---
paths:
  - src/**/*.zig
  - src/lang/clj/**
  - src/runtime/host/**
---
> Folded into [`provisional_marker.md`](provisional_marker.md) §
> "Skeleton vs transient stub vs PROVISIONAL vs permanent no-op"
> at Wave 16 W16-6 (2026-05-26). This file remains as a path-
> frontmatter pointer so editors of `src/**/*.zig` /

## perf_marker
---
paths:
  - "src/**/*.zig"
  - "src/**/*.clj"
---
Auto-loaded when editing source. Codifies the **discoverability** layer
for performance optimizations — code shaped for speed rather than for
the simplest correct form. Sibling to
[`provisional_marker.md`](provisional_marker.md); the SSOT is
[`.dev/optimizations.md`](../../.dev/optimizations.md).

## plan_revision_thinking
---
paths:
  - "**"
---
> SSOT: `.dev/principle.md`. This file is the trigger only.
If "wait, this feels off" / "this seems different from what we
planned" / "I'll fix it later" / "this looks like a hassle, let me
take a side route" comes to mind while editing, interrupt the
current edit, re-read `.dev/principle.md`, and take the surgery
at the right depth before continuing. The interrupt is not a

## tier_classification
---
paths:
  - src/lang/**
  - src/runtime/host/**
  - data/compat_tiers.yaml
---
Every public function and type carries a tier classification A / B / C / D
(per `data/compat_tiers.yaml` and ADR-0013).
Tier D forms raise a per-form catalog Code (`tier_d_gen_class` /
`tier_d_gen_interface` / `tier_d_compile` / `tier_d_proxy_deep` /

## zone_deps
---
paths:
  - "src/**/*.zig"
  - "build.zig"
---
Auto-loaded when editing Zig source. Authoritative version of the layering
contract in ROADMAP §4.1 / §A1.
```
Layer 3: src/app/, src/main.zig    -- CLI / REPL / nREPL / builder / pod
                                       imports anything below

