#!/usr/bin/env bash
# test/clj/run_tier_a.sh — compatibility entry point for the Tier A gate (§9.13
# row 11.4). The suites now live behind test/clj/run.sh; this runs the `tier_a`
# suite on the binary's default backend (CLJW_BACKEND / --backend still apply
# through the environment). Tier A skip taxonomy (ADR-0046):
# test/clj/skip_taxonomy.yaml.
set -euo pipefail
cd "$(dirname "$0")/../.."

# Honor the gate's shared-binary contract: skip the build when run_all.sh already
# built the optimised cljw (CLJW_SKIP_BUILD), else build ReleaseSafe (NOT a bare
# `zig build` = Debug, which would clobber the shared binary to Debug right before
# the parallel e2e pool — the ~100x silent perf cliff; D-385).
[ -n "${CLJW_SKIP_BUILD:-}" ] || zig build -Dwasm -Doptimize="${CLJW_OPT:-ReleaseSafe}" >/dev/null

exec bash test/clj/run.sh --suite tier_a
