#!/usr/bin/env bash
# scripts/check_backend_diff.sh — three-way differential check (tree_walk / vm / wasmgc).
#
# Every case in test/diff/backends/*.txt (cases separated by a `;;---` line) is
# run as `(do <case>)` in a SEPARATE cljw process per backend, selected with
# `--backend=`. The three runs must agree on: stdout, exit code, and the first
# two lines of stderr (error kind + message; stack traces legitimately differ
# per backend). Separate processes avoid the in-process `--compare` limits
# (shared Env, heap values compared by address).
#
# Usage: bash scripts/check_backend_diff.sh            # all case files
#        bash scripts/check_backend_diff.sh closures   # one stem
#        CLJW_BIN=/path/to/cljw bash scripts/check_backend_diff.sh
# Exit 0 = all agree; 1 = at least one divergence (details printed).
#
# Known, accepted divergences are listed in test/diff/backends/known_divergences.txt
# (one `file:case-number` per line, `#` comments) and reported but not failing.

set -uo pipefail
cd "$(dirname "$0")/.."

BIN="${CLJW_BIN:-zig-out/bin/cljw}"
[ -x "$BIN" ] || { echo "building cljw…" >&2; zig build -Dwasm -Doptimize="${CLJW_OPT:-ReleaseSafe}" >/dev/null; }

DIR="test/diff/backends"
KNOWN="$DIR/known_divergences.txt"
BACKENDS=(tree_walk vm wasmgc)
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Bounded run (macOS has no `timeout`): kill the process group after 60s.
run_one() {
    perl -e '$p=fork; if(!$p){setpgrp(0,0); exec @ARGV or die} $SIG{ALRM}=sub{kill "KILL",-$p; waitpid($p,0); exit 124}; alarm 60; waitpid($p,0); exit($?>>8)' "$@"
}

files=()
if [ $# -gt 0 ]; then files+=("$DIR/$1.txt"); else files=("$DIR"/*.txt); fi

total=0; fails=0; known=0
for f in "${files[@]}"; do
    [ -f "$f" ] || continue
    [ "$(basename "$f")" = "known_divergences.txt" ] && continue
    rm -f "$TMP"/case.*
    awk -v d="$TMP" 'BEGIN{n=1; out=sprintf("%s/case.%03d",d,n)}
        /^;;---$/ {n++; out=sprintf("%s/case.%03d",d,n); next}
        {print > out}' "$f"
    for c in "$TMP"/case.*; do
        [ -s "$c" ] || continue
        # Skip comment-only / blank blocks.
        grep -qv '^[[:space:]]*\(;.*\)\?$' "$c" || continue
        total=$((total + 1))
        num="${c##*.}"
        src="(do $(cat "$c")
)"
        for b in "${BACKENDS[@]}"; do
            run_one "$BIN" --backend="$b" -e "$src" >"$TMP/out.$b" 2>"$TMP/err.$b"
            echo $? >"$TMP/rc.$b"
            head -2 "$TMP/err.$b" >"$TMP/errh.$b"
        done
        diverged=0
        for b in vm wasmgc; do
            for k in out rc errh; do
                cmp -s "$TMP/$k.tree_walk" "$TMP/$k.$b" || diverged=1
            done
        done
        if [ "$diverged" -eq 1 ]; then
            key="$(basename "$f"):$((10#$num))"
            if [ -f "$KNOWN" ] && grep -qx "$key" "$KNOWN"; then
                known=$((known + 1)); echo "KNOWN  $key"; continue
            fi
            fails=$((fails + 1))
            echo "DIVERGE $key"
            echo "  case: $(head -c 300 "$c" | tr '\n' ' ')"
            for b in "${BACKENDS[@]}"; do
                echo "  [$b] rc=$(cat "$TMP/rc.$b") out=$(head -c 200 "$TMP/out.$b" | tr '\n' '|') err=$(tr '\n' '|' <"$TMP/errh.$b" | head -c 200)"
            done
        fi
    done
done

echo "backend diff: $total cases, $fails diverging, $known known"
[ "$fails" -eq 0 ]
