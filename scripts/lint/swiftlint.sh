#!/usr/bin/env bash
# SwiftLint gate: installs the pinned SwiftLint if needed, then lints with
# .swiftlint.yml. Exits non-zero on any finding not in .swiftlint.baseline.json
# (--strict: warnings count too).
#
#   bash scripts/lint/swiftlint.sh             the gate
#   bash scripts/lint/swiftlint.sh --update    rewrite the baseline after fixing findings
#                                              (refuses new findings; see swiftlint-baseline.mjs)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
bash "$ROOT/scripts/lint/install-swiftlint.sh"
cd "$ROOT"

if [ "${1:-}" = "--update" ]; then
  shift
  exec node scripts/lint/swiftlint-baseline.mjs "$@"
fi
exec tools/bin/swiftlint lint --strict --quiet --baseline .swiftlint.baseline.json
