# ClojureWasm

A Clojure runtime targeting WebAssembly, written in Zig 0.16.0.
Embeds zwasm v2 (pinned v2.5.0, Apache-2.0, github.com/zwasm/zwasm).

> Keep this file <= 3 KB. Details live in `.dev/` -- read on demand.

## Build and test

    zig build                    # compile
    zig build test               # unit tests
    zig build test-all           # all test layers
    zig build run -- <args>      # run

## Key constraints

- Zig 0.16.0 only. No other Zig version.
- zwasm v2.5.0 is final pin (F-001). `.dev/zwasm_capabilities.md` is frozen reference.
- Finished form wins (F-002): big surgery OK when design demands it.
- No JVM-specific assumptions in Wasm-targeted code.
- No permanent no-op stubs -- skeleton-then-rewrite only.

## Priority chain (top to bottom)

1. `.dev/project_facts.md` -- user-declared invariants (F-001 to F-009), never self-amend
2. `.dev/principle.md` -- bad-smell catalogue, four revision depths
3. `.dev/ROADMAP.md` -- single source of truth for plans
4. `.dev/decisions/` -- ADRs, newest wins on conflict
5. `.dev/handover.md` -- current state (max 100 lines)

## On-demand references (do NOT paste into context unprompted)

- `.dev/ROADMAP.md` -- mission, phases, principles
- `.dev/principle.md` -- smell sensor, revision depths
- `.dev/project_facts.md` -- F-NNN invariants
- `.dev/gc_roots_map.md` -- GC root tracking
- `.dev/skills/` -- runnable procedures (audit, code-learning, continue)

## Code layout

- `src/` -- Zig sources (parse/ validate/ ir/ runtime/ engine/ wasi/ api/ cli/)
- `include/` -- public C headers
- `test/` -- per-layer suites
- `docs/` -- tutorial, API ref, benchmarks
- `.dev/` -- roadmap, ADRs, handover, principles
