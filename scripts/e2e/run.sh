#!/usr/bin/env bash
# e2e runner for the sample apps: build the app, boot the device, install,
# run the app's Maestro flows, collect the screenshots, shut the device down.
# e2e/README.md has the details.
#
#   bash scripts/e2e/run.sh <app>     one app (see --list)
#   bash scripts/e2e/run.sh --list    the apps
#
# Each app is a file scripts/e2e/apps/<app>.sh. To add one, copy apps/ios.sh
# and define the same six things (see "The app contract" below). Device
# helpers shared by several apps live in scripts/e2e/lib/.
#
# Env:
#   SELLWILD_NATIVE_LOCK=<script>  the lock that allows one native build or
#                                  booted device at a time on this machine.
#                                  The whole session (build to shutdown) runs
#                                  inside one call of it. Unset: the agents'
#                                  lock below, when it exists; else no lock.
#   SELLWILD_E2E_NO_BUILD=1        skip the build and use the last one
#   SELLWILD_E2E_CACHE=<dir>       build caches (default e2e/.cache, gitignored)
#   MAESTRO=<path>                 the Maestro CLI (default ~/.maestro/bin/maestro)
#   MAESTRO_DRIVER_STARTUP_TIMEOUT how long Maestro waits for its driver on the
#                                  device, in ms (default here 60000)
#   JAVA_HOME                      a JDK 17 (found when unset)
#
# Output: e2e/artifacts/<app>/ (gitignored): screenshots/<flow>-<name>.png,
# maestro.log, report-<flow>.xml (JUnit), build.log, device.log and
# maestro/<flow>/ (Maestro's own output: commands, logs, hierarchies).
#
# Exit status: 0 when every flow passed, 1 when a flow failed, 2 on a usage
# or setup error (unknown app, no Maestro, failed build, device or install).

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
E2E_DIR="$ROOT/scripts/e2e"
DEFAULT_LOCK=/private/tmp/claude-501/-Users-lawrence-Programming-Web-Antengo/7809ef48-b1e2-4faf-84db-3b9af9c5c86e/scratchpad/native-lock.sh

list_apps() {
  for f in "$E2E_DIR"/apps/*.sh; do basename "$f" .sh; done
}

usage() {
  echo "usage: bash scripts/e2e/run.sh <app>   apps: $(list_apps | tr '\n' ' ')" >&2
  exit 2
}

APP="${1:-}"
case "$APP" in
  --list) list_apps; exit 0 ;;
  ""|-h|--help) usage ;;
esac
APP_FILE="$E2E_DIR/apps/$APP.sh"
if [ ! -f "$APP_FILE" ]; then
  echo "run.sh: no app \"$APP\" (no $APP_FILE)." >&2
  usage
fi

# Run the whole session inside one lock call.
if [ -z "${SELLWILD_E2E_LOCKED:-}" ]; then
  export SELLWILD_E2E_LOCKED=1
  LOCK="${SELLWILD_NATIVE_LOCK:-$DEFAULT_LOCK}"
  if [ -x "$LOCK" ]; then
    exec "$LOCK" "e2e-$APP" -- bash "$E2E_DIR/run.sh" "$@"
  fi
  echo "run.sh: no native lock at $LOCK; running without one." >&2
fi

# Maestro needs a JDK 17 (the same search as scripts/gate.sh).
is_jdk17() { [ -x "$1/bin/java" ] && "$1/bin/java" -version 2>&1 | grep -q 'version "17'; }
if ! is_jdk17 "${JAVA_HOME:-}"; then
  for candidate in "$(/usr/libexec/java_home -v 17 2>/dev/null || true)" /Library/Java/JavaVirtualMachines/jdk-17.0.1.jdk/Contents/Home; do
    if [ -n "$candidate" ] && is_jdk17 "$candidate"; then export JAVA_HOME="$candidate"; break; fi
  done
fi
MAESTRO="${MAESTRO:-$HOME/.maestro/bin/maestro}"
if [ ! -x "$MAESTRO" ]; then
  echo "run.sh: Maestro not found at $MAESTRO. Install it (e2e/README.md, \"Setup\")." >&2
  exit 2
fi
export MAESTRO_CLI_NO_ANALYTICS=1 MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED=true
# How long Maestro waits for its driver on the device. Its own default was too
# short once on this busy machine (rn-android: "Maestro Android driver did not
# start up in time"), so give it a minute.
export MAESTRO_DRIVER_STARTUP_TIMEOUT="${MAESTRO_DRIVER_STARTUP_TIMEOUT:-60000}"

E2E_CACHE="${SELLWILD_E2E_CACHE:-$ROOT/e2e/.cache}"
ART="$ROOT/e2e/artifacts/$APP"
rm -rf "$ART"
mkdir -p "$ART/screenshots" "$E2E_CACHE"

# The app contract. apps/<app>.sh sets:
#   E2E_APP_ID    bundle id / application id the flows launch
#   E2E_FLOWS     the folder of the app's flows (e2e/maestro/<dir>)
#   e2e_build     builds the app (reusing caches) and sets E2E_APP_PATH;
#                 with SELLWILD_E2E_NO_BUILD=1 it only sets E2E_APP_PATH
#   e2e_boot      boots the device and sets E2E_DEVICE (Maestro's --device)
#   e2e_install   installs E2E_APP_PATH on E2E_DEVICE
#   e2e_shutdown  shuts every device of its kind down (runs on any exit)
for lib in "$E2E_DIR"/lib/*.sh; do
  # shellcheck source=/dev/null
  source "$lib"
done
# shellcheck source=/dev/null
source "$APP_FILE"

step() { echo "run.sh [$APP]: $*"; }
fail_setup() { echo "run.sh [$APP]: FAILED: $*" >&2; exit 2; }

step "building (log: e2e/artifacts/$APP/build.log)"
e2e_build >"$ART/build.log" 2>&1 || { tail -30 "$ART/build.log" >&2; fail_setup "build"; }
[ -e "${E2E_APP_PATH:-}" ] || fail_setup "no app at ${E2E_APP_PATH:-<unset>}"

trap 'step "shutting the device down"; e2e_shutdown >>"$ART/device.log" 2>&1' EXIT
step "booting the device"
e2e_boot >>"$ART/device.log" 2>&1 || { tail -20 "$ART/device.log" >&2; fail_setup "boot"; }
step "installing $E2E_APP_PATH on $E2E_DEVICE"
e2e_install >>"$ART/device.log" 2>&1 || { tail -20 "$ART/device.log" >&2; fail_setup "install"; }

step "running the flows in ${E2E_FLOWS#"$ROOT"/}"
# One Maestro call per flow file, each with its own JUnit report and output
# folder. Relative takeScreenshot paths land in $ART.
cd "$ART" || exit 2
status=0
for flow in "$E2E_FLOWS"/*.yaml; do
  name="$(basename "$flow" .yaml)"
  "$MAESTRO" --device "$E2E_DEVICE" test "$flow" \
    --format junit --output "$ART/report-$name.xml" \
    --test-output-dir "$ART/maestro/$name" 2>&1 | tee -a "$ART/maestro.log"
  flow_status=${PIPESTATUS[0]}
  [ "$flow_status" -eq 0 ] || status=1
  # With a report format Maestro prints only a summary: add every step.
  node "$E2E_DIR/lib/maestro-steps.mjs" "$ART/maestro/$name" | tee -a "$ART/maestro.log"
  # Its takeScreenshot files and failure screenshots, as <flow>-<name>.png.
  while IFS= read -r png; do
    cp "$png" "$ART/screenshots/$name-$(basename "$png")"
  done < <(find "$ART/maestro/$name" -name '*.png')
done

step "screenshots: $(find "$ART/screenshots" -name '*.png' | wc -l | tr -d ' ') in e2e/artifacts/$APP/screenshots"
if [ "$status" -ne 0 ]; then
  step "FAILED: a flow failed (see e2e/artifacts/$APP/maestro.log)"
  exit 1
fi
step "passed"
