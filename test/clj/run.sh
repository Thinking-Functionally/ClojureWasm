#!/usr/bin/env bash
# test/clj/run.sh — run the test/clj suites and require the backends to agree.
#
#   bash test/clj/run.sh                       # all suites, on the binary's default backend
#   bash test/clj/run.sh --all-backends        # tree_walk, vm and wasmgc; they must agree
#   bash test/clj/run.sh --backend wasmgc      # one backend
#   bash test/clj/run.sh --suite tier_a        # one suite (names: test/clj/support/suites.txt)
#   bash test/clj/run.sh --include-slow        # also the suites marked slow
#   bash test/clj/run.sh --jvm                 # also run each suite on JVM Clojure (`clj`) as the oracle
#   CLJW_BIN=/path/to/cljw  CLJ_TEST_CAPS="threads fs"  bash test/clj/run.sh
#
# Each suite is run as ONE cljw process per backend whose only form calls
# cljtest.runner (test/clj/support). A suite passes when, on every backend:
#   * the process exits 0 and prints a CLJTEST-SUMMARY line with no failures,
#   * pass+fail+error >= the manifest's min_assertions (no silent shrinking; a
#     suite that runs zero tests fails),
# and across backends the exit code, stdout and stderr are byte-identical.
# A suite whose `requires` capability is not in $CLJ_TEST_CAPS is reported as
# SKIP with the reason (e.g. `eval` is unavailable in a standalone AOT build).
#
# Exit 0 = every selected suite passed; 1 = a failure or divergence; 2 = usage.

set -uo pipefail
cd "$(dirname "$0")/../.."

BIN="${CLJW_BIN:-zig-out/bin/cljw}"
MANIFEST="${CLJ_TEST_MANIFEST:-test/clj/support/suites.txt}"
CAPS=" ${CLJ_TEST_CAPS:-eval threads fs net java} "
SUITE="all"
BACKENDS="default"
SLOW=0
JVM=0

while [ $# -gt 0 ]; do
    case "$1" in
        --suite) SUITE="${2:?--suite needs a name}"; shift 2 ;;
        --backend) BACKENDS="${2:?--backend needs a name}"; shift 2 ;;
        --all-backends) BACKENDS="tree_walk vm wasmgc"; shift ;;
        --include-slow) SLOW=1; shift ;;
        --jvm) JVM=1; shift ;;
        --bin) BIN="${2:?--bin needs a path}"; shift 2 ;;
        -h | --help) sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1 (see --help)" >&2; exit 2 ;;
    esac
done

[ -x "$BIN" ] || {
    echo "building cljw…" >&2
    zig build -Dwasm -Doptimize="${CLJW_OPT:-ReleaseSafe}" >/dev/null
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Bounded run (macOS has no `timeout`): kill the process group after 10 minutes.
run_bounded() {
    perl -e '$p=fork; if(!$p){setpgrp(0,0); exec @ARGV or die} $SIG{ALRM}=sub{kill "KILL",-$p; waitpid($p,0); exit 124}; alarm 600; waitpid($p,0); exit($?>>8)' "$@"
}

field() { echo "$1" | sed -E "s/.*:$2 ([0-9]+).*/\\1/"; }

selected=0 passed=0 failed=0 skipped=0

while IFS='|' read -r name kind cp spec min req slow; do
    case "$name" in '' | '#'*) continue ;; esac
    [ "$SUITE" = all ] || [ "$SUITE" = "$name" ] || continue
    selected=$((selected + 1))

    if [ "$slow" = yes ] && [ "$SLOW" -eq 0 ]; then
        echo "SKIP  $name (slow; pass --include-slow)"; skipped=$((skipped + 1)); continue
    fi
    missing=""
    if [ "$req" != "-" ]; then
        for r in $(echo "$req" | tr ',' ' '); do
            case "$CAPS" in *" $r "*) ;; *) missing="$r" ;; esac
        done
    fi
    if [ -n "$missing" ]; then
        echo "SKIP  $name (requires '$missing', not in CLJ_TEST_CAPS)"; skipped=$((skipped + 1)); continue
    fi

    CP="test/clj/support"
    if [ "$cp" != "-" ]; then
        for d in $(echo "$cp" | tr ',' ' '); do CP="$CP:test/clj/$d"; done
    fi
    items=""
    if [ "$kind" = files ]; then
        for f in $(echo "$spec" | tr ',' ' '); do items="$items \"test/clj/$f\""; done
        FORM="(cljtest.runner/run-files \"$name\" [$items])"
    else
        for n in $(echo "$spec" | tr ',' ' '); do items="$items $n"; done
        FORM="(cljtest.runner/run-namespaces \"$name\" '[$items])"
    fi

    problems=""
    first=""
    firstsum=""
    for b in $BACKENDS; do
        flag=""
        [ "$b" = default ] || flag="--backend=$b"
        base="$TMP/$name.$b"
        # shellcheck disable=SC2086
        run_bounded "$BIN" $flag -cp "$CP" -e "(do (require 'cljtest.runner) $FORM)" \
            >"$base.out" 2>"$base.err" </dev/null
        echo $? >"$base.rc"
        rc="$(cat "$base.rc")"
        sum="$(grep '^CLJTEST-SUMMARY' "$base.out" | tail -1)"
        if [ -z "$sum" ]; then
            problems="$problems [$b: no CLJTEST-SUMMARY, exit $rc]"
            continue
        fi
        p="$(field "$sum" pass)"; f="$(field "$sum" fail)"; e="$(field "$sum" error)"
        [ "$rc" -eq 0 ] || problems="$problems [$b: exit $rc, fail=$f error=$e]"
        [ $((p + f + e)) -ge "$min" ] || problems="$problems [$b: only $((p + f + e)) assertions, manifest requires >= $min]"
        if [ -z "$first" ]; then
            first="$b"; firstsum="$sum"
        else
            for k in rc out err; do
                cmp -s "$TMP/$name.$first.$k" "$base.$k" || problems="$problems [$first vs $b: $k differs]"
            done
        fi
    done

    if [ "$JVM" -eq 1 ]; then
        # Oracle: the SAME suite on JVM Clojure (`clj`). Only the assertion counts
        # are compared (clojure.test's text differs slightly between hosts).
        if command -v clj >/dev/null 2>&1 && [ -n "$firstsum" ]; then
            jcp="$CP"
            run_bounded clj -Sdeps "{:paths [\"$(echo "$jcp" | sed 's/:/" "/g')\"]}" -M \
                -e "(do (require 'cljtest.runner) $FORM)" \
                >"$TMP/$name.jvm.out" 2>"$TMP/$name.jvm.err" </dev/null
            jrc=$?
            jsum="$(grep '^CLJTEST-SUMMARY' "$TMP/$name.jvm.out" | tail -1)"
            if [ -z "$jsum" ]; then
                problems="$problems [jvm: no CLJTEST-SUMMARY, exit $jrc]"
            else
                for k in test pass fail error; do
                    [ "$(field "$jsum" $k)" = "$(field "$firstsum" $k)" ] || problems="$problems [jvm vs $first: $k $(field "$jsum" $k) != $(field "$firstsum" $k)]"
                done
            fi
        else
            problems="$problems [--jvm requested but \`clj\` not found]"
        fi
    fi

    if [ -z "$problems" ]; then
        echo "OK    $name: $(field "$firstsum" pass) assertions pass  [backends: ${BACKENDS}$([ "$JVM" -eq 1 ] && echo ' + jvm')]"
        passed=$((passed + 1))
    else
        echo "FAIL  $name:$problems"
        for b in $BACKENDS jvm; do
            [ -f "$TMP/$name.$b.out" ] || continue
            echo "  --- $b (last 12 lines of stdout) ---"
            tail -12 "$TMP/$name.$b.out" | sed 's/^/  /'
            [ -s "$TMP/$name.$b.err" ] && { echo "  --- $b stderr ---"; head -8 "$TMP/$name.$b.err" | sed 's/^/  /'; }
        done
        failed=$((failed + 1))
    fi
done <"$MANIFEST"

if [ "$selected" -eq 0 ]; then
    echo "no suite named '$SUITE' in $MANIFEST" >&2
    exit 2
fi
echo "test/clj: $passed passed, $failed failed, $skipped skipped (of $selected suites; backends: $BACKENDS)"
[ "$failed" -eq 0 ]
