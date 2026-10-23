# ClojureWasm

A Clojure runtime written in Zig 0.16.0.

> Project memory loaded by Claude Code on every session. Keep it short.
> Detailed plans live in `.dev/ROADMAP.md`. Skills hold runnable procedures.

## Project spirit (top priority, governs everything below)

**The finished form's cleanliness wins.** Shipping fast and avoiding
rework are second-tier. Pre-built roadmaps and ADRs exist precisely
to minimise rework, but when they collide with "what the final shape
should look like", the final shape wins and the plan is amended in
place (ROADMAP §17). This applies to:

- **Big surgery is welcome** when design tighting-up exposes something
  the original plan missed. The autonomous loop must not hesitate at
  depth-3 / depth-4 revisions (`.dev/principle.md`).
- **Skeleton-then-rewrite is endorsed** (per `permanent_noop_forbidden`)
  but **excessive skeletons are a smell** (per the Smallest-diff bias

# Full version archived in claude_rules.db

## Context Management — MANDATORY
- NEVER read files >200 lines without offset+limit. Max 150 lines per read.
- For runtime.zig (460 lines): read in 3 chunks (0-149, 150-299, 300-460). NEVER read it fully.
- NEVER run test commands without `2>&1 | head -50`
- When Edit fails, do NOT re-read the whole file. Use `sed -i` commands instead.
- Prefer `grep -n "pattern" file` to find line numbers, then read only ±20 lines around the target.
- Workflow for large file edits:
  1. `grep -n "target_pattern" file` → get line number
  2. Read offset=LINE-20, limit=40
  3. Apply edit or generate sed command
  4. Do NOT re-read to verify. Use `sed -n 'LINEp' file` to check.

## Context Management — MANDATORY
- NEVER read files >200 lines without offset+limit. Max 150 lines per read.
- For runtime.zig (460 lines): read in 3 chunks (0-149, 150-299, 300-460). NEVER read it fully.
- NEVER run test commands without `2>&1 | head -50`
- When Edit fails, do NOT re-read the whole file. Use `sed -i` commands instead.
- Prefer `grep -n "pattern" file` to find line numbers, then read only ±20 lines around the target.
- Workflow for large file edits:
  1. `grep -n "target_pattern" file` → get line number
  2. Read offset=LINE-20, limit=40
  3. Apply edit or generate sed command
  4. Do NOT re-read to verify. Use `sed -n 'LINEp' file` to check.
