# Android emulator helpers for scripts/e2e/apps/*.sh (android, rn-android).
# Sourced by scripts/e2e/run.sh; defines functions only.
#
# Env:
#   ANDROID_HOME / ANDROID_SDK_ROOT  the Android SDK (default ~/Library/Android/sdk)
#   SELLWILD_ANDROID_AVD             the AVD to boot (default Pixel_5_API_36, see
#                                    android_avd_pick)
#   SELLWILD_ANDROID_MEMORY          the emulator's RAM in MB for this boot only
#                                    (default 2560, the emulator's floor for API 36;
#                                    the AVD's config is not changed)

ANDROID_SDK_DIR="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
ADB="$ANDROID_SDK_DIR/platform-tools/adb"
ANDROID_EMULATOR="$ANDROID_SDK_DIR/emulator/emulator"
# One emulator at a time on a fixed port, so its serial is known before it boots.
ANDROID_EMU_PORT=5554
ANDROID_SERIAL_E2E="emulator-$ANDROID_EMU_PORT"

# Sets ANDROID_AVD: SELLWILD_ANDROID_AVD, else Pixel_5_API_36. Fails when it is not
# an AVD on this machine. Not Pixel_5_API_32: its 800 MB data partition is full
# (11 MB free after pm trim-caches), and the 15 MB sample APK does not install
# ("Requested internal only, but not enough space"). Pixel_5_API_36 has 6 GB; it
# boots with SELLWILD_ANDROID_MEMORY RAM (2.5 GB), not its configured 4 GB.
android_avd_pick() {
  ANDROID_AVD="${SELLWILD_ANDROID_AVD:-Pixel_5_API_36}"
  if ! "$ANDROID_EMULATOR" -list-avds | grep -qx "$ANDROID_AVD"; then
    echo "android-emu: no AVD \"$ANDROID_AVD\" (emulator -list-avds)" >&2
    return 1
  fi
}

# Runs adb against the e2e emulator.
android_adb() {
  "$ADB" -s "$ANDROID_SERIAL_E2E" "$@"
}

# Boots AVD $1 and waits until Android is up (7 minutes at most). Its console
# output goes to $2. It saves no snapshot on exit, so every run starts alike.
# Sets E2E_EMU_PID. An emulator already on the port is reused.
android_emu_boot() {
  "$ADB" start-server
  if android_adb get-state 2>/dev/null | grep -q device; then
    echo "android-emu: $ANDROID_SERIAL_E2E is already up; using it"
  else
    "$ANDROID_EMULATOR" -avd "$1" -port "$ANDROID_EMU_PORT" -memory "${SELLWILD_ANDROID_MEMORY:-2560}" \
      -no-snapshot-save -no-audio -no-boot-anim >"$2" 2>&1 &
    E2E_EMU_PID=$!
  fi
  local waited=0
  until [ "$(android_adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
    if [ -n "${E2E_EMU_PID:-}" ] && ! kill -0 "$E2E_EMU_PID" 2>/dev/null; then
      echo "android-emu: the emulator exited while booting (log: $2)" >&2
      return 1
    fi
    if [ "$waited" -ge 420 ]; then
      echo "android-emu: $ANDROID_SERIAL_E2E did not boot in 420s" >&2
      return 1
    fi
    sleep 3
    waited=$((waited + 3))
  done
  echo "android-emu: $ANDROID_SERIAL_E2E booted in ${waited}s"
  # Awake and unlocked, with animations off (faster and steadier UI tests).
  android_adb shell input keyevent KEYCODE_WAKEUP
  android_adb shell wm dismiss-keyguard
  local scale
  for scale in window_animation_scale transition_animation_scale animator_duration_scale; do
    android_adb shell settings put global "$scale" 0
  done
  # Room to install: drop the apps' caches (nothing else) and show what is free.
  android_adb shell pm trim-caches 4G
  android_adb shell df -h /data
}

# Installs APK $3 as package $2 on device $1, removing the package first.
android_install() {
  "$ADB" -s "$1" uninstall "$2" >/dev/null 2>&1 || true
  "$ADB" -s "$1" install -r -t "$3"
}

# The e2e emulator down, as the machine rules ask: adb emu kill, then the
# process itself if it is still there after 30s.
android_emu_shutdown() {
  android_adb emu kill 2>/dev/null || true
  local waited=0
  if [ -n "${E2E_EMU_PID:-}" ]; then
    while kill -0 "$E2E_EMU_PID" 2>/dev/null && [ "$waited" -lt 30 ]; do
      sleep 1
      waited=$((waited + 1))
    done
    if kill -0 "$E2E_EMU_PID" 2>/dev/null; then
      echo "android-emu: the emulator did not exit; killing pid $E2E_EMU_PID"
      kill -9 "$E2E_EMU_PID" 2>/dev/null || true
    fi
  fi
  # adb lists a killed emulator for a few seconds more.
  waited=0
  while "$ADB" devices | grep -q "^$ANDROID_SERIAL_E2E" && [ "$waited" -lt 15 ]; do
    sleep 1
    waited=$((waited + 1))
  done
  echo "android-emu: emulators left: $("$ADB" devices | grep -c '^emulator-')"
}
