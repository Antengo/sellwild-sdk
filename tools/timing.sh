# Suite timing for the coverage shell scripts. Source it, then:
#   timing_begin <suite>      start the clock and record on exit
#   timing_phase <name>       close the phase that ran since the last mark
# On exit the run is appended to .timings/suites.jsonl by tools/timed.mjs,
# with the script's exit status. A timing failure never fails the suite.

_timing_now() { perl -MTime::HiRes=time -e 'printf "%.2f", time'; }

timing_begin() {
  TIMING_SUITE="$1"
  TIMING_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  TIMING_START="$(_timing_now)"
  TIMING_LAST="$TIMING_START"
  TIMING_PHASES=()
  trap '_timing_end $?' EXIT
}

timing_phase() {
  local now secs
  now="$(_timing_now)"
  secs="$(perl -e "printf '%.2f', $now - $TIMING_LAST")"
  TIMING_PHASES+=(--phase "$1=$secs")
  TIMING_LAST="$now"
  echo "::timing $1 $secs"
}

_timing_end() {
  local status="$1" secs
  secs="$(perl -e "printf '%.2f', $(_timing_now) - $TIMING_START")"
  node "$TIMING_ROOT/tools/timed.mjs" --record "$TIMING_SUITE" --seconds "$secs" --exit "$status" \
    ${TIMING_PHASES[@]+"${TIMING_PHASES[@]}"} >/dev/null 2>&1 || true
  echo "::timing total $secs"
}
