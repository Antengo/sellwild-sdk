# Flutter helpers for scripts/e2e/apps/flutter-*.sh (flutter-ios,
# flutter-android). Sourced by scripts/e2e/run.sh; defines functions only.
#
# Env:
#   FLUTTER  the flutter CLI (default: flutter on PATH)

FLUTTER_SAMPLE="$ROOT/samples/flutter-demo"

# Runs the flutter CLI inside the sample, with no analytics.
flutter_sample() {
  local bin="${FLUTTER:-$(command -v flutter)}"
  if [ -z "$bin" ]; then
    echo "flutter: no flutter CLI (add it to PATH or set FLUTTER)" >&2
    return 1
  fi
  (cd "$FLUTTER_SAMPLE" && "$bin" --suppress-analytics "$@")
}

# Stops the sample's Gradle daemons (the machine rules). Its wrapper exists
# once flutter has built the app for Android.
flutter_gradle_stop() {
  local gradlew="$FLUTTER_SAMPLE/android/gradlew"
  [ -x "$gradlew" ] || return 0
  "$gradlew" -p "$FLUTTER_SAMPLE/android" --stop
}
