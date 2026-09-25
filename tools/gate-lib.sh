# The step runner behind scripts/gate.sh. The same file is in sellwild-sdk
# and sellwild-widget; each repo's scripts/gate.sh sources it, declares its
# steps with `step` and calls `gate_main "$@"`. Bash 3.2 (macOS /bin/bash).
#
#   step <id> <mode> <kind> <native> <needs> <command>
#     mode    fast (runs in --fast and --full) or full (--full only)
#     kind    typecheck, lint, check, coverage or warnings. After a failed
#             typecheck step, the coverage steps are skipped.
#     native  gradle, ios, xcode or -. A native step waits while
#             another xcodebuild or Gradle build runs on the machine (up to
#             GATE_NATIVE_WAIT seconds, default 600). After the last gradle
#             step in a row, GATE_GRADLE_STOP runs; after an ios step (one
#             that boots a simulator), GATE_IOS_STOP runs. An xcode step only
#             builds, so nothing is shut down after it.
#     needs   a step id or -. When that step is skipped, this one is too.
#     command run with bash -c from the repo root.
#
# Each step runs through tools/timed.mjs as suite gate:<id>
# (.timings/suites.jsonl). The run goes on after a failure, so one run shows
# every failure; the table at the end has every result, and the exit status
# is 1 when any step failed.

S_ID=(); S_MODE=(); S_KIND=(); S_NATIVE=(); S_NEEDS=(); S_CMD=()

step() {
  S_ID+=("$1"); S_MODE+=("$2"); S_KIND+=("$3"); S_NATIVE+=("$4"); S_NEEDS+=("$5"); S_CMD+=("$6")
}

_gate_now() { perl -MTime::HiRes=time -e 'printf "%.2f", time'; }

# Index of a step id, or nothing.
_gate_index() {
  local i
  for ((i = 0; i < ${#S_ID[@]}; i++)); do
    if [ "${S_ID[$i]}" = "$1" ]; then echo "$i"; return 0; fi
  done
  return 1
}

_gate_usage() {
  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$GATE_SCRIPT"
}

_gate_list() {
  local i
  printf '%-22s %-5s %-10s %s\n' STEP MODE KIND COMMAND
  for ((i = 0; i < ${#S_ID[@]}; i++)); do
    printf '%-22s %-5s %-10s %s\n' "${S_ID[$i]}" "${S_MODE[$i]}" "${S_KIND[$i]}" "${S_CMD[$i]}"
  done
}

# Prints what native build is running on this machine, if any.
_gate_native_busy() {
  if pgrep -x xcodebuild >/dev/null 2>&1; then echo "an xcodebuild"; return 0; fi
  if pgrep -f 'org.gradle.wrapper.GradleWrapperMain' >/dev/null 2>&1; then echo "a Gradle build"; return 0; fi
  return 1
}

_gate_wait_native() {
  local waited=0 limit="${GATE_NATIVE_WAIT:-600}" what
  while what="$(_gate_native_busy)"; do
    if [ "$waited" -ge "$limit" ]; then
      echo "gate: $what is still running after ${limit}s; not starting $1 (one native build at a time)." >&2
      return 1
    fi
    if [ "$waited" -eq 0 ]; then echo "gate: waiting for $what to finish before $1 (one native build at a time)"; fi
    sleep 5
    waited=$((waited + 5))
  done
}

_GATE_GRADLE_UP=0
_GATE_SIM_UP=0

_gate_gradle_stop() {
  if [ "$_GATE_GRADLE_UP" = 1 ] && [ -n "${GATE_GRADLE_STOP:-}" ]; then
    echo "==> $GATE_GRADLE_STOP"
    bash -c "$GATE_GRADLE_STOP" || echo "gate: '$GATE_GRADLE_STOP' failed" >&2
  fi
  _GATE_GRADLE_UP=0
}

_gate_sims_stop() {
  if [ "$_GATE_SIM_UP" = 1 ] && [ -n "${GATE_IOS_STOP:-}" ]; then
    echo "==> $GATE_IOS_STOP"
    bash -c "$GATE_IOS_STOP" || echo "gate: '$GATE_IOS_STOP' failed" >&2
  fi
  _GATE_SIM_UP=0
}

_gate_cleanup() { _gate_gradle_stop; _gate_sims_stop; }

gate_main() {
  local mode=fast only="" i j id
  while [ $# -gt 0 ]; do
    case "$1" in
      --fast) mode=fast ;;
      --full) mode=full ;;
      --only)
        if [ $# -lt 2 ]; then echo "gate: --only needs step ids (see --list)" >&2; return 2; fi
        mode=only; only="$2"; shift ;;
      --only=*) mode=only; only="${1#--only=}" ;;
      --list) _gate_list; return 0 ;;
      -h|--help) _gate_usage; return 0 ;;
      *) echo "gate: unknown argument '$1' (see --help)" >&2; return 2 ;;
    esac
    shift
  done

  # The selected step indexes, in gate order.
  local wanted=() sel=()
  if [ "$mode" = only ]; then
    IFS=',' read -r -a wanted <<<"$only"
    if [ ${#wanted[@]} -eq 0 ]; then echo "gate: --only needs step ids (see --list)" >&2; return 2; fi
    for id in "${wanted[@]}"; do
      if ! _gate_index "$id" >/dev/null; then
        echo "gate: unknown step '$id'. Steps: ${S_ID[*]}" >&2
        return 2
      fi
    done
  fi
  for ((i = 0; i < ${#S_ID[@]}; i++)); do
    case "$mode" in
      fast) if [ "${S_MODE[$i]}" = fast ]; then sel+=("$i"); fi ;;
      full) sel+=("$i") ;;
      only) for id in "${wanted[@]}"; do if [ "$id" = "${S_ID[$i]}" ]; then sel+=("$i"); fi; done ;;
    esac
  done

  trap _gate_cleanup EXIT
  trap 'exit 130' INT TERM

  local res=() secs=() notes=() typecheck_failed=0 failed=0 skipped=0 n=${#sel[@]}
  local t_all t0 t1 status note k cmd native next_native
  t_all="$(_gate_now)"
  echo "gate --$mode: ${n} steps in $(basename "$GATE_ROOT")"
  for ((j = 0; j < n; j++)); do
    i="${sel[$j]}"
    id="${S_ID[$i]}"; cmd="${S_CMD[$i]}"; native="${S_NATIVE[$i]}"
    note=""
    if [ "$typecheck_failed" = 1 ] && [ "${S_KIND[$i]}" = coverage ]; then
      note="a type check failed"
    elif [ "${S_NEEDS[$i]}" != - ]; then
      for ((k = 0; k < j; k++)); do
        if [ "${S_ID[${sel[$k]}]}" = "${S_NEEDS[$i]}" ] && [ "${res[$k]}" = skip ]; then note="${S_NEEDS[$i]} was skipped"; fi
      done
    fi
    if [ -n "$note" ]; then
      echo
      echo "==> [$((j + 1))/$n] $id: skipped ($note)"
      res+=(skip); secs+=(0); notes+=("$note"); skipped=$((skipped + 1))
      continue
    fi

    echo
    echo "==> [$((j + 1))/$n] $id: $cmd"
    t0="$(_gate_now)"
    status=0
    if [ "$native" != - ] && ! _gate_wait_native "$id"; then
      status=1
      note="another native build is running"
    else
      if [ "$native" = gradle ]; then _GATE_GRADLE_UP=1; fi
      if [ "$native" = ios ]; then _GATE_SIM_UP=1; fi
      (cd "$GATE_ROOT" && node tools/timed.mjs "gate:$id" -- bash -c "$cmd") || status=$?
    fi
    t1="$(_gate_now)"
    secs+=("$(perl -e "printf '%.1f', $t1 - $t0")")
    if [ "$status" -eq 0 ]; then
      res+=(pass); notes+=("$note")
    else
      res+=(FAIL); notes+=("${note:-exit $status}"); failed=$((failed + 1))
      if [ "${S_KIND[$i]}" = typecheck ]; then typecheck_failed=1; fi
    fi

    next_native=-
    if [ $((j + 1)) -lt "$n" ]; then next_native="${S_NATIVE[${sel[$((j + 1))]}]}"; fi
    if [ "$native" = gradle ] && [ "$next_native" != gradle ]; then _gate_gradle_stop; fi
    if [ "$native" = ios ]; then _gate_sims_stop; fi
  done

  local total
  total="$(perl -e "printf '%.1f', $(_gate_now) - $t_all")"
  echo
  echo "gate --$mode results ($(basename "$GATE_ROOT"))"
  printf '%-22s %-6s %8s  %s\n' STEP RESULT SECONDS NOTE
  for ((j = 0; j < n; j++)); do
    printf '%-22s %-6s %8s  %s\n' "${S_ID[${sel[$j]}]}" "${res[$j]}" "${secs[$j]}" "${notes[$j]}"
  done
  echo "$((n - failed - skipped)) passed, $failed failed, $skipped skipped, ${total}s"
  [ "$failed" -eq 0 ]
}
