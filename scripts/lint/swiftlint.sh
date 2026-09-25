#!/usr/bin/env bash
# SwiftLint gate: installs the pinned SwiftLint if needed, then lints with
# .swiftlint.yml and checks the findings against
# scripts/lint/swiftlint.baseline.json (scripts/lint/swiftlint-baseline.mjs
# has the matching rules). Every finding counts, warnings too. Exits 1 on a
# finding the baseline does not cover.
#
#   bash scripts/lint/swiftlint.sh             the gate
#   bash scripts/lint/swiftlint.sh --update    rewrite the baseline after fixing findings
#                                              (refuses any increase unless --allow-increase)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
bash "$ROOT/scripts/lint/install-swiftlint.sh"
cd "$ROOT"

if [ "${1:-}" = "--update" ]; then
  shift
  exec node scripts/lint/swiftlint-baseline.mjs --update "$@"
fi
exec node scripts/lint/swiftlint-baseline.mjs "$@"
