# contracts

Shared, language-neutral contracts for every Sellwild client: TS core, React Native, iOS, Android, Flutter and the web widget. Nothing here ships to partners.

```
npm install          # ajv 8 + ajv-formats, dev only
npm test             # node --test: vectors, validation, registry, key coverage, print gate, refresh guard
npm run validate     # node scripts/validate.mjs: table of every check, exit 1 on any failure
```

## What lives here

| path | contents |
|---|---|
| `FAILURES.md` | The clientFailure contract (logFailure on all six clients). Start here. |
| `failure-codes.json` | Canonical failure-code registry. `failure-codes.sources.json` traces each code to the phase-1 failure points. |
| `reference/log-failure.mjs` | JS reference of the logFailure pure core. `reference/vector-cases.mjs` holds the vector inputs. |
| `golden/` | Golden vectors generated from the reference (`npm run vectors`). Every platform's pure core must reproduce them. |
| `schemas/` | JSON Schema 2020-12 for every external shape: `app-config`, `listing`, `listings-response`, `localized-listings-config`, `localized-listings-response`, `events-batch`, `client-failure-event`, `bridge-message`, `rn-native-config`, `growthcode-sync-response`, `eid-blob`, plus `failure-codes`. |
| `samples/<schema>/` | Real payloads captured with read-only GETs on 2026-09-23. Base64 photos are cut to a 16-character stub; `samples/SOURCES.json` has the URL, the sha256 of the original bytes and a `truncated` flag. The `*.403.xml` files are what a missing config or state cache really returns. |
| `fixtures/<schema>/valid/`, `fixtures/<schema>/invalid/` | Hand-made variants (`"_synthetic": true`): minimal and edge cases. `invalid/_expected-errors.json` names the error each invalid fixture must produce. |
| `expectations/` | The typed result each platform must produce from each app-config and listings input, with today's per-platform `knownDrift`. |
| `print-gate.allowlist.json`, `scripts/print-gate.mjs` | Ratchet on print calls and empty catch blocks in SDK source. |
| `scripts/refresh-samples.mjs` | Re-captures the samples. GET only, allowlisted hosts only, needs `CONTRACTS_LIVE=1`. Never part of the test suite. |

## How each platform uses it

1. **Fixtures as factory bases.** Mock factories start from `fixtures/<schema>/valid/*.json` (or a sample) and apply overrides. Test code should not inline external payload literals.
2. **Emit and validate.** A factory test writes each variant it builds to `contracts/out/<platform>/<schema>.<variant>.json` (the root can be moved with `SELLWILD_CONTRACT_OUT`), then runs:

   ```
   node contracts/scripts/validate.mjs --out <platform>
   ```

   The schema is the file-name prefix before the first dot. The command fails when a file does not match, the schema name is unknown, or nothing was emitted. `contracts/out/` is git-ignored.

   | platform | fixtures path from its tests | emit dir |
   |---|---|---|
   | core, react-native (vitest) | `../contracts/fixtures/...` (or ajv in-process with `scripts/lib/schemas.mjs`) | `contracts/out/core/`, `contracts/out/react-native/` |
   | iOS (XCTest) | relative to `#filePath`, up to the repo root, then `contracts/` | `contracts/out/ios/` |
   | Android (JUnit) | `sourceSets["test"].resources.srcDir("../contracts")` | `contracts/out/android/` |
   | Flutter (flutter_test) | `File('../contracts/fixtures/...')` (cwd is the package root) | `contracts/out/flutter/` |
   | widget | vendored copies with a sha256 sync check | its own `contracts/out/widget/` |

3. **Conformance.** Each platform runs `fixtures/app-config/valid/*` and the app-config samples through its real parser and compares with `expectations/app-config.expected.json` (same for listings). A difference is allowed only in a field named in that platform's `knownDrift` entry. Remove the entry in the change that fixes the drift.
4. **Golden vectors.** Each pure core replays `golden/log-failure.vectors.json` (TS, Kotlin and Dart also the `utf16` file) and must match every vector exactly. See FAILURES.md section 12.
5. **Registry parity.** Each platform mirrors `failure-codes.json` as constants and tests that the mirror equals the codes whose `clients` include it.
6. **Key coverage.** `test/key-coverage.test.mjs` fails when SDK code reads a CONSTANT_CASE remote key that `schemas/app-config.schema.json` does not declare. Declare new keys there (with a description) in the same change.
7. **Print gate.** `test/print-gate.test.mjs` fails when a file gains a print call or an empty catch. After removing some, run `node scripts/print-gate.mjs --update` to lock the lower counts in.

## Changing things

1. Schema change: edit the schema, add or adjust fixtures (valid and invalid, with `_expected-errors.json`), run `npm test`. Every property needs a `description`.
2. Contract change: edit `FAILURES.md` and `reference/log-failure.mjs` together, run `npm run vectors`, commit the regenerated `golden/` files, and tell every platform lane.
3. New failure code: FAILURES.md section 4.4.
4. New real sample: add it to `SAMPLE_SPECS` in `scripts/lib/samples.mjs` and run `CONTRACTS_LIVE=1 node scripts/refresh-samples.mjs` by hand.
