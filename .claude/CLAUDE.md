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
