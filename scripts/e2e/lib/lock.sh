# The native lock (scripts/e2e/native-lock.sh: one native build or booted
# device at a time on this machine) for the scripts that build or boot:
# scripts/e2e/run.sh and scripts/rn/compile-bridge-*.sh. Sourced; defines
# functions only.

# Prints the pid of the ancestor process that runs the lock script $1, if
# any. The lock script runs its command only once it holds the lock, so such
# an ancestor means this process is inside the lock already (for example
# `native-lock.sh ... -- bash scripts/gate.sh --e2e`). The lock is not
# re-entrant: taking it again there would wait forever.
lock_holder() {
  local want="${1##*/}" pid="$PPID" w1 w2 rest
  while [ -n "$pid" ] && [ "$pid" -gt 1 ]; do
    # The command's first two words: the script itself, or its shell then it.
    read -r w1 w2 rest <<<"$(ps -o command= -p "$pid" 2>/dev/null)"
    if [ "${w1##*/}" = "$want" ] || [ "${w2##*/}" = "$want" ]; then
      echo "$pid"
      return 0
    fi
    pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
  done
  return 1
}

# Runs the calling script again inside the native lock, unless it is inside
# it already: SELLWILD_E2E_LOCKED is set (an outer run.sh or bridge script
# holds it), or an ancestor runs the lock script (the gate run under it).
#
#   native_lock_reexec <label> <script> [args...]
#
# The lock script is SELLWILD_NATIVE_LOCK, or scripts/e2e/native-lock.sh.
# When it is missing, this says so and the caller goes on without a lock.
# Returns 0 when the caller should go on; otherwise it execs the lock script
# with `bash <script> [args...]` and does not return.
native_lock_reexec() {
  local label="$1" lock holder
  shift
  [ -n "${SELLWILD_E2E_LOCKED:-}" ] && return 0
  export SELLWILD_E2E_LOCKED=1
  lock="${SELLWILD_NATIVE_LOCK:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/native-lock.sh}"
  if [ ! -x "$lock" ]; then
    echo "$label: no native lock at $lock; running without one." >&2
    return 0
  fi
  if holder="$(lock_holder "$lock")"; then
    echo "$label: already inside the native lock (pid $holder); not taking it again."
    return 0
  fi
  exec "$lock" "$label" -- bash "$@"
}
