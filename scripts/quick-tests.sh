#!/bin/bash
# Quick self-test battery (~75 s): every short autotest scenario, run in
# parallel against the debug build. Self-tests ignore remote commands and
# stay out of Now Playing, so parallel runs don't interfere.
#
#   bash scripts/quick-tests.sh                 # after `swift build`
#   bash scripts/quick-tests.sh --autotest-volume 0   # extra flags for every run (silent)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/.build/debug/NeuraWave"
LOGDIR="$(mktemp -d)"
EXTRA=("$@")
# Now Playing coverage only on CI: locally it would take Control Center over
# from whatever you are listening to.
NOW_PLAYING=""
[ "${CI:-}" = "true" ] && NOW_PLAYING="--autotest-now-playing"
[ -x "$BIN" ] || { echo "build first: swift build"; exit 2; }

run() {
  local name="$1"; shift
  "$BIN" --autotest "$@" ${EXTRA[@]+"${EXTRA[@]}"} > "$LOGDIR/$name.log" 2>&1
}

# name | args | extra pattern the log must contain
SCENARIOS=(
  "smoke|--autotest-seconds 8 --autotest-cycle 2 $NOW_PLAYING|"
  "stop-restart|--autotest-seconds 16 --autotest-cycle 3 --autotest-stop-at 6|RESTART_AFTER_STOP"
  "switch-stress|--autotest-seconds 30 --autotest-cycle 2|"
  "pause-resume|--autotest-seconds 20 --autotest-cycle 50 --autotest-pause-at 5 --autotest-resume-at 12|AUTOTEST_RESUME"
  "quick-resume|--autotest-seconds 12 --autotest-cycle 50 --autotest-pause-at 5 --autotest-resume-at 6|AUTOTEST_RESUME"
  "device-change|--autotest-seconds 14 --autotest-cycle 50 --autotest-device-change-at 4|DEVICE_CHECK ok"
  "program|--autotest-seconds 45 --autotest-cycle 30 --autotest-program-seconds 45 --autotest-pause-at 10 --autotest-resume-at 15|PROGRAM_STEP 3/3"
  "timer-pause|--autotest-seconds 75 --autotest-cycle 100 --autotest-timer-minutes 1 --autotest-pause-at 10 --autotest-resume-at 15|TIMER_STOP_VERIFIED at 6[4-9]s"
)

# Self-tests must never change your saved settings. The debug binary keeps
# them in the "NeuraWave" defaults domain; snapshot it to compare after.
settings_before="$(defaults read NeuraWave 2>/dev/null | grep -vE 'NSWindow|NSStatusItem' || true)"

for scenario in "${SCENARIOS[@]}"; do
  IFS='|' read -r name args _ <<< "$scenario"
  # shellcheck disable=SC2086
  run "$name" $args &
done
wait

failed=0
for scenario in "${SCENARIOS[@]}"; do
  IFS='|' read -r name _ expect <<< "$scenario"
  log="$LOGDIR/$name.log"
  if grep -q AUTOTEST_COMPLETE "$log" && grep -q "SWITCH_CHECK ok" "$log" \
     && ! grep -qE "MISMATCH|_CHECK FAIL" "$log" \
     && { [ -z "$expect" ] || grep -qE "$expect" "$log"; }; then
    echo "PASS $name"
  else
    echo "FAIL $name"
    tail -5 "$log"
    failed=1
  fi
done
settings_after="$(defaults read NeuraWave 2>/dev/null | grep -vE 'NSWindow|NSStatusItem' || true)"
if [ "$settings_before" = "$settings_after" ]; then
  echo "PASS settings-untouched"
else
  echo "FAIL settings-untouched (a self-test changed saved settings)"
  diff <(echo "$settings_before") <(echo "$settings_after")
  failed=1
fi
echo "logs: $LOGDIR"
exit $failed
