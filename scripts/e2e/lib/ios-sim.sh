# iOS Simulator helpers for scripts/e2e/apps/*.sh (ios, rn-ios).
# Sourced by scripts/e2e/run.sh; defines functions only.

# Sets IOS_SIM_ID: SELLWILD_IOS_SIM_ID, else the pick scripts/coverage/ios.sh
# makes (a booted iPhone, else the first iPhone by name on the newest iOS).
ios_sim_pick() {
  if [ -n "${SELLWILD_IOS_SIM_ID:-}" ]; then
    IOS_SIM_ID="$SELLWILD_IOS_SIM_ID"
    return 0
  fi
  IOS_SIM_ID="$(xcrun simctl list devices available -j | node -e '
    let raw = "";
    process.stdin.on("data", (chunk) => (raw += chunk)).on("end", () => {
      const version = (runtime) => {
        const m = /\.iOS-(\d+)-(\d+)(?:-(\d+))?$/.exec(runtime);
        return m ? [Number(m[1]), Number(m[2]), Number(m[3] ?? 0)] : null;
      };
      const phones = Object.entries(JSON.parse(raw).devices).flatMap(([runtime, list]) => {
        const v = version(runtime);
        if (!v) return [];
        return list.filter((d) => d.isAvailable !== false && d.name.startsWith("iPhone")).map((d) => ({ ...d, v }));
      });
      const order = (a, b) => b.v[0] - a.v[0] || b.v[1] - a.v[1] || b.v[2] - a.v[2] || a.name.localeCompare(b.name);
      const pick = phones.filter((d) => d.state === "Booted").sort(order)[0] ?? phones.sort(order)[0];
      if (!pick) process.exit(1);
      process.stdout.write(pick.udid);
    });')" || { echo "ios-sim: no available iPhone simulator" >&2; return 1; }
}

# Boots $1 (already booted is fine) and waits until it is ready.
ios_sim_boot() {
  xcrun simctl boot "$1" 2>/dev/null || true
  xcrun simctl bootstatus "$1" -b
}

# Installs app $3 on simulator $1, removing bundle $2 first.
ios_sim_install() {
  xcrun simctl uninstall "$1" "$2" 2>/dev/null || true
  xcrun simctl install "$1" "$3"
}

# Every simulator down, as the machine rules ask.
ios_sim_shutdown() {
  xcrun simctl shutdown all
}
