#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

bash scripts/package-app.sh release

BIN="$ROOT/build/NeuraWave.app/Contents/MacOS/NeuraWave"
LOGDIR="$ROOT/test-results"
# Extra flags for every run, e.g. AUTOTEST_EXTRA_ARGS="--autotest-volume 0"
# for a silent battery.
read -r -a EXTRA <<< "${AUTOTEST_EXTRA_ARGS:-}"
mkdir -p "$LOGDIR"

# Pass = run completed, every requested switch reached the audio, and no
# in-run check (DEVICE_CHECK, WINDOW_CHECK, …) reported a failure.
scenario_passed() {
  local log="$1"
  grep -q "AUTOTEST_COMPLETE" "$log" 2>/dev/null \
    && grep -q "SWITCH_CHECK ok" "$log" 2>/dev/null \
    && ! grep -qE "MISMATCH|_CHECK FAIL" "$log" 2>/dev/null
}

run_scenario() {
  local name="$1"
  local timeout="$2"
  shift 2
  local log="$LOGDIR/$name.log"
  : > "$log"

  "$BIN" "$@" ${EXTRA[@]+"${EXTRA[@]}"} >> "$log" 2>&1 &
  local pid=$!
  local deadline=$((SECONDS + timeout))

  while (( SECONDS < deadline )); do
    if grep -q "SWITCH_CHECK" "$log" 2>/dev/null; then break; fi
    if ! kill -0 "$pid" 2>/dev/null; then break; fi
    sleep 1
  done

  if scenario_passed "$log"; then
    echo "PASS $name"
  else
    echo "FAIL $name"
    tail -5 "$log"
  fi

  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
}

wait_for_complete() {
  local log="$1"
  local pid="$2"
  local timeout="$3"
  local deadline=$((SECONDS + timeout))
  while (( SECONDS < deadline )); do
    if grep -q "SWITCH_CHECK" "$log" 2>/dev/null; then break; fi
    if ! kill -0 "$pid" 2>/dev/null; then break; fi
    sleep 1
  done
}

echo "=== quick scenarios ==="

# Scenario 1 with a mid-run screenshot for visual verification
LOG01="$LOGDIR/01-basic.log"
: > "$LOG01"
"$BIN" --autotest --autotest-seconds 10 --autotest-cycle 3 --autotest-show-window ${EXTRA[@]+"${EXTRA[@]}"} >> "$LOG01" 2>&1 &
PID01=$!
sleep 5
WID="$(swift scripts/window-id-by-pid.swift "$PID01" 2>/dev/null | head -1)"
if [ -n "$WID" ]; then
  screencapture -x -l "$WID" "$LOGDIR/visual-playing.png" 2>/dev/null || true
fi
wait_for_complete "$LOG01" "$PID01" 20
if scenario_passed "$LOG01"; then
  echo "PASS 01-basic"
else
  echo "FAIL 01-basic"
  tail -5 "$LOG01"
fi
kill "$PID01" 2>/dev/null || true
wait "$PID01" 2>/dev/null || true

run_scenario "02-stop-restart" 30 --autotest --autotest-seconds 16 --autotest-cycle 3 --autotest-stop-at 6
run_scenario "03-timer-autostop" 90 --autotest --autotest-seconds 70 --autotest-cycle 5 --autotest-timer-minutes 1
run_scenario "05-program-advance" 90 --autotest --autotest-seconds 45 --autotest-cycle 30 --autotest-program-seconds 45
run_scenario "06-switch-stress" 60 --autotest --autotest-seconds 40 --autotest-cycle 2
run_scenario "07-pause-resume" 40 --autotest --autotest-seconds 20 --autotest-cycle 50 --autotest-pause-at 5 --autotest-resume-at 12
run_scenario "08-quick-resume" 30 --autotest --autotest-seconds 12 --autotest-cycle 50 --autotest-pause-at 5 --autotest-resume-at 6
run_scenario "09-timer-pause" 100 --autotest --autotest-seconds 75 --autotest-cycle 100 --autotest-timer-minutes 1 --autotest-pause-at 10 --autotest-resume-at 15
run_scenario "10-program-pause" 90 --autotest --autotest-seconds 45 --autotest-cycle 30 --autotest-program-seconds 45 --autotest-pause-at 10 --autotest-resume-at 15
run_scenario "11-device-change" 30 --autotest --autotest-seconds 14 --autotest-cycle 50 --autotest-device-change-at 4
run_scenario "12-window-reopen" 30 --autotest --autotest-seconds 8 --autotest-cycle 50 --autotest-window-check

echo "=== endurance (30 min) ==="
# Truncate first: appending to a stale log could let an old
# AUTOTEST_COMPLETE line from a previous run fake a PASS.
: > "$LOGDIR/04-endurance.log"
nohup "$BIN" --autotest --autotest-seconds 1800 --autotest-cycle 30 --autotest-volume 0.06 ${EXTRA[@]+"${EXTRA[@]}"} \
  >> "$LOGDIR/04-endurance.log" 2>&1 &
ENDURANCE_PID=$!
echo "$ENDURANCE_PID" > "$LOGDIR/endurance.pid"

nohup bash -c '
  pid="$1"
  perf_log="$2"
  while kill -0 "$pid" 2>/dev/null; do
    ps -o pid=,rss=,%cpu=,etime= -p "$pid" >> "$perf_log"
    sleep 60
  done
' _ "$ENDURANCE_PID" "$LOGDIR/endurance-perf.log" >> "$LOGDIR/perf.log" 2>&1 &
PERF_PID=$!
echo "$PERF_PID" > "$LOGDIR/perf.pid"

echo "endurance started pid=$ENDURANCE_PID perf=$PERF_PID"

echo "waiting for endurance to finish (up to 35 min)..."
END_DEADLINE=$((SECONDS + 35 * 60))
while (( SECONDS < END_DEADLINE )); do
  if grep -q "SWITCH_CHECK" "$LOGDIR/04-endurance.log" 2>/dev/null; then break; fi
  if ! kill -0 "$ENDURANCE_PID" 2>/dev/null; then break; fi
  sleep 5
done
if scenario_passed "$LOGDIR/04-endurance.log"; then
  echo "PASS 04-endurance"
else
  echo "FAIL 04-endurance"
  tail -5 "$LOGDIR/04-endurance.log"
fi
kill "$ENDURANCE_PID" 2>/dev/null || true
kill "$PERF_PID" 2>/dev/null || true
wait "$ENDURANCE_PID" 2>/dev/null || true
wait "$PERF_PID" 2>/dev/null || true
