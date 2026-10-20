# Project rules (merged)

## no-op stubs forbidden
Every function body must do real work or be a documented skeleton with a TODO(phase) tag.

## no copy from v1
Never copy v1 code. v2 is a ground-up redesign; v1 patterns do not apply.

## no JVM-specific assumptions
Wasm-targeted code must not assume JVM semantics (classloading, reflection, etc.).

## extended challenge
When stuck, enumerate at least 3 alternatives before picking. No first idea wins.

## plan revision thinking
Before revising a plan, state what changed and why the old plan no longer fits.

## tier classification
Classify work as tier-1 (critical path), tier-2 (supporting), tier-3 (nice-to-have).

## markdown format
Keep markdown docs at most 100 lines. Use headers, not walls of text.
