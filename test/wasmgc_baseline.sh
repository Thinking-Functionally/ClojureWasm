#!/usr/bin/env bash
# test/wasmgc_baseline.sh — run every test/e2e/*.sh against the WasmGC backend
# and print a per-script pass/fail table + assertion (PASS line) totals.
#
#   bash test/wasmgc_baseline.sh [path-substring]   # e.g. phase14_atom
#
# Isolation: the wasmgc binary is built into a private prefix and scripts run
# from a sandbox root whose zig-out/bin/cljw is that binary. Scripts that
# rebuild zig-out/bin/cljw themselves therefore cannot swap in the VM binary
# (which would silently make later scripts pass on the wrong backend), and the
# repo's own zig-out is never touched. A sanity check asserts the binary under
# test really is the wasmgc one.
# Results: /tmp/wasmgc_baseline/{summary.tsv,<script>.log}
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
FILTER="${1:-}"
OUT=/tmp/wasmgc_baseline
SANDBOX="$OUT/root"
TMO="${WASMGC_TEST_TIMEOUT:-30}"
rm -rf "$OUT"; mkdir -p "$OUT" "$SANDBOX/zig-out/bin"
cd "$REPO"

zig build -Dbackend=wasmgc -Dwasm -Doptimize="${CLJW_OPT:-ReleaseSafe}" \
  --prefix "$OUT/prefix" >"$OUT/build.log" 2>&1 \
  || { echo "wasmgc build failed, see $OUT/build.log" >&2; exit 2; }

for e in "$REPO"/* "$REPO"/.[!.]*; do
  case "$(basename "$e")" in zig-out|.zig-cache|.git) continue;; esac
  ln -s "$e" "$SANDBOX/$(basename "$e")"
done
cp "$OUT/prefix/bin/cljw" "$SANDBOX/zig-out/bin/cljw"
SENTINEL=$(shasum "$SANDBOX/zig-out/bin/cljw" | cut -d' ' -f1)

run_one() {
  local s="$1" n; n="$(basename "$s" .sh)"
  (cd "$SANDBOX" && CLJW_SKIP_BUILD=1 perl -e '$t=shift; $p=fork; if(!$p){setpgrp(0,0); exec @ARGV or die} $SIG{ALRM}=sub{kill "KILL",-$p; waitpid($p,0); exit 124}; alarm $t; waitpid($p,0); exit($?>>8)' "$TMO" bash "$SANDBOX/test/e2e/$n.sh") >"$OUT/$n.log" 2>&1
  local rc=$? p; p=$(grep -c '^PASS' "$OUT/$n.log" || true)
  # A script that replaced the binary under test is invalid, not a pass.
  [ "$(shasum "$SANDBOX/zig-out/bin/cljw" | cut -d' ' -f1)" = "$SENTINEL" ] || {
    rc=99; cp "$OUT/prefix/bin/cljw" "$SANDBOX/zig-out/bin/cljw"; }
  printf '%s\t%s\t%s\n' "$n" "$([ $rc -eq 0 ] && echo pass || echo fail)" "$p" >"$OUT/$n.res"
}

for s in test/e2e/*.sh; do
  [[ -z "$FILTER" || "$s" == *"$FILTER"* ]] && run_one "$s"
done

cat "$OUT"/*.res | sort >"$OUT/summary.tsv"
total=$(wc -l <"$OUT/summary.tsv" | tr -d ' '); ok=$(grep -c $'\tpass\t' "$OUT/summary.tsv" || true)
asserts=$(awk -F'\t' '{s+=$3} END{print s+0}' "$OUT/summary.tsv")
echo "scripts passing: $ok/$total   PASS assertions seen: $asserts"
echo "table: $OUT/summary.tsv"
[ "$ok" -eq "$total" ]
