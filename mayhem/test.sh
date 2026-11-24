#!/usr/bin/env bash
#
# mayhem/test.sh — run ANGLE's upstream unit tests plus known-answer translator cases.
#
# 1) out/mayhem/test/angle_unittests: upstream's angle_unittests compiler, preprocessor, src/common
#    and src/image_util suites (src/tests/angle_unittests.gni; build.sh lists every file it leaves
#    out and why), built by mayhem/build.sh with normal flags against googletest at the DEPS pin.
#    Its --gtest_output=json report is mapped to passed/failed/skipped.
# 2) upstream's samples/shader_translator CLI on each case in mayhem/tests/cases.txt, diffing its
#    full output (info log, translated ESSL/GLSL/HLSL source, SPIR-V disassembly, or reflected
#    variables) and exit code against the golden files in mayhem/tests/golden.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SRC:=/mayhem}"
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

T="$SRC/out/mayhem/test/shader_translator"
U="$SRC/out/mayhem/test/angle_unittests"
for b in "$T" "$U"; do
  if [ ! -x "$b" ]; then
    echo "test.sh: $b missing — run mayhem/build.sh first" >&2
    emit_ctrf angle-unittests+shader-translator-golden 0 1
    exit 1
  fi
done

passed=0 failed=0 skipped=0
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# ---- 1) upstream gtest suites
"$U" --gtest_brief=1 --gtest_output="json:$tmp/gtest.json" > "$tmp/gtest.log" 2>&1
urc=$?
grep -E '^\[  (FAILED|PASSED|SKIPPED) |^\[==========\]' "$tmp/gtest.log" | tail -40
if counts="$(python3 -I - "$tmp/gtest.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
p = f = s = 0
for suite in d["testsuites"]:
    for t in suite["testsuite"]:
        if t.get("failures"):
            f += 1
        elif t.get("status") == "NOTRUN" or t.get("result") in ("SKIPPED", "SUPPRESSED"):
            s += 1
        else:
            p += 1
print(p, f, s)
PY
)"; then
  read -r up uf us <<<"$counts"
else
  up=0 uf=1 us=0; echo "test.sh: angle_unittests wrote no usable JSON report (exit $urc)"
fi
# a crash or non-zero exit with no failed test recorded still counts as a failure
if [ "$urc" -ne 0 ] && [ "$uf" -eq 0 ]; then uf=1; echo "test.sh: angle_unittests exited $urc"; fi
echo "angle_unittests: passed=$up failed=$uf skipped=$us"
passed=$((passed + up)); failed=$((failed + uf)); skipped=$((skipped + us))

# ---- 2) shader_translator golden cases
while IFS='|' read -r name flags shader rc_want; do
  case "$name" in ''|\#*) continue ;; esac
  # shellcheck disable=SC2086
  "$T" $flags "mayhem/tests/shaders/$shader" > "$tmp/$name.out" 2>&1
  rc=$?
  if [ "$rc" = "$rc_want" ] && cmp -s "$tmp/$name.out" "mayhem/tests/golden/$name.out"; then
    passed=$((passed + 1)); echo "PASS $name"
  else
    failed=$((failed + 1)); echo "FAIL $name (exit $rc, want $rc_want)"
    diff -u "mayhem/tests/golden/$name.out" "$tmp/$name.out" | head -20
  fi
done < mayhem/tests/cases.txt

emit_ctrf angle-unittests+shader-translator-golden "$passed" "$failed" "$skipped"
