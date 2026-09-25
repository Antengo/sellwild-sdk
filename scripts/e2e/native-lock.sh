#!/bin/bash
# One native build or booted device at a time on this machine.
#
#   scripts/e2e/native-lock.sh <label> -- <command...>
#
# Waits until no other holder runs, then runs <command> holding the lock and
# frees it on exit. mkdir is atomic, so two callers never both win. A lock
# whose owner pid is gone is stale and is taken over. The lock lives outside
# the repo (/tmp/sellwild-native-<uid>.lock, or $SELLWILD_NATIVE_LOCK_DIR) so
# every checkout and worktree on the machine shares it.

LOCK="${SELLWILD_NATIVE_LOCK_DIR:-/tmp/sellwild-native-$(id -u).lock}"
label="${1:?usage: native-lock.sh <label> -- <command...>}"; shift
[ "${1:-}" = "--" ] && shift
[ $# -gt 0 ] || { echo "usage: native-lock.sh <label> -- <command...>" >&2; exit 2; }

waited=0
while ! mkdir "$LOCK" 2>/dev/null; do
  owner="$(cat "$LOCK/pid" 2>/dev/null)"
  if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then
    echo "native-lock: stale lock from pid $owner ($(cat "$LOCK/label" 2>/dev/null)), taking it" >&2
    rm -rf "$LOCK"
    continue
  fi
  if [ $((waited % 60)) -eq 0 ]; then
    echo "native-lock: waiting for $(cat "$LOCK/label" 2>/dev/null) (pid $owner), ${waited}s" >&2
  fi
  sleep 5
  waited=$((waited + 5))
done
echo $$ > "$LOCK/pid"
echo "$label" > "$LOCK/label"
trap 'rm -rf "$LOCK"' EXIT INT TERM
"$@"
