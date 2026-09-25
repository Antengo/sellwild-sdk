#!/usr/bin/env bash
# Installs the pinned SwiftLint into tools/bin/ (gitignored) from the official
# GitHub release, checks its sha256, and does nothing when that version is
# already there.
#
# Usage: bash scripts/lint/install-swiftlint.sh
#
# Not brew (unpinned) and not a Package.swift plugin: this repo is a library,
# and a plugin dependency there would be resolved by every consumer.
#
# To bump: change VERSION and SHA256 together. SHA256 is the sha256 of
# portable_swiftlint.zip on the release page (GitHub shows it as the asset
# digest).

set -euo pipefail

VERSION="0.65.1"
SHA256="c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0"
URL="https://github.com/realm/SwiftLint/releases/download/${VERSION}/portable_swiftlint.zip"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN_DIR="$ROOT/tools/bin"
BIN="$BIN_DIR/swiftlint"

if [ -x "$BIN" ] && [ "$("$BIN" version 2>/dev/null)" = "$VERSION" ]; then
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "install-swiftlint: downloading SwiftLint $VERSION"
curl -fsSL --retry 3 -o "$TMP/portable_swiftlint.zip" "$URL"

actual="$(shasum -a 256 "$TMP/portable_swiftlint.zip" | cut -d' ' -f1)"
if [ "$actual" != "$SHA256" ]; then
  echo "install-swiftlint: sha256 mismatch for $URL" >&2
  echo "  expected $SHA256" >&2
  echo "  got      $actual" >&2
  exit 1
fi

unzip -q -o "$TMP/portable_swiftlint.zip" swiftlint -d "$TMP/out"
mkdir -p "$BIN_DIR"
install -m 0755 "$TMP/out/swiftlint" "$BIN"

installed="$("$BIN" version)"
if [ "$installed" != "$VERSION" ]; then
  echo "install-swiftlint: installed binary reports $installed, expected $VERSION" >&2
  exit 1
fi
echo "install-swiftlint: installed SwiftLint $VERSION at tools/bin/swiftlint"
