// ESLint for @sellwild/sdk-core: src, test, scripts and the vitest config.
//
//   npm run lint                     fails on any finding eslint-suppressions.json does not hold
//   npm run lint -- --prune-suppressions
//                                    after fixing baselined findings: lower the counts
//
// Existing findings are baselined in eslint-suppressions.json (ESLint bulk
// suppressions, one count per file and rule). A count may only go down: a new
// finding fails, and so does a baselined one that is gone until it is pruned.
// Never run --suppress-all again to get green; fix the finding or disable it
// on its line with a reason.
//
// House failure rules (contracts/FAILURES.md 1, 2, 8.4):
//   no-console                      src, except the A2 modules (contracts/scripts/print-gate.mjs PRINT_EXEMPT)
//   sellwild/no-global-console      the same files: console through globalThis, window, self or global
//   sellwild/no-silent-catch        everywhere: empty catches (comments do not count) and swallowing .catch handlers
//   sellwild/catch-reports-failure  src: every catch calls logFailure, rethrows or hands on a registry code.
//                                   The transport catches FAILURES.md 8.4 exempts (EventQueue.flush,
//                                   resolveUid) each carry their own eslint-disable-next-line.
//   sellwild/disable-reason         everywhere: turning off a sellwild/* rule needs "-- FAILURES.md <section>: <why>"
// The rules live in contracts/lint/eslint-plugin-sellwild.mjs, shared with
// react-native and (vendored) the widget.

import fs from 'node:fs'
import js from '@eslint/js'
import { defineConfig } from 'eslint/config'
import globals from 'globals'
import tseslint from 'typescript-eslint'
import sellwild from '../contracts/lint/eslint-plugin-sellwild.mjs'
import { PRINT_EXEMPT } from '../contracts/scripts/print-gate.mjs'

const PACKAGE = 'core/'

/** Registry codes: a string handed on from a catch must be one of these. */
const codes = JSON.parse(fs.readFileSync(new URL('../contracts/failure-codes.json', import.meta.url), 'utf8')).map((entry) => entry.code)

/** The A2 modules of this package, relative to it. */
const printExempt = PRINT_EXEMPT.filter((file) => file.startsWith(PACKAGE)).map((file) => file.slice(PACKAGE.length))

export default defineConfig(
  { ignores: ['dist/', 'coverage/'] },
  { linterOptions: { reportUnusedDisableDirectives: 'error' } },
  js.configs.recommended,
  tseslint.configs.recommendedTypeChecked,
  {
    languageOptions: {
      parserOptions: {
        // tsconfig.test.json covers src, test and vitest.config.ts.
        project: './tsconfig.test.json',
        tsconfigRootDir: import.meta.dirname,
      },
    },
  },
  {
    files: ['**/*.{js,mjs,cjs}'],
    extends: [tseslint.configs.disableTypeChecked],
    languageOptions: { globals: globals.node },
  },
  {
    plugins: { sellwild },
    rules: {
      // Empty catches are sellwild/no-silent-catch's, which also counts a
      // comment-only body as empty (FAILURES.md 1.3).
      'no-empty': ['error', { allowEmptyCatch: true }],
      'sellwild/no-silent-catch': 'error',
      'sellwild/disable-reason': 'error',
      // A leading underscore marks a binding that is unused on purpose.
      '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_', varsIgnorePattern: '^_', caughtErrorsIgnorePattern: '^_', destructuredArrayIgnorePattern: '^_' }],
    },
  },
  {
    files: ['src/**/*.ts'],
    rules: {
      'no-console': 'error',
      'sellwild/no-global-console': 'error',
      'sellwild/catch-reports-failure': ['error', { reporters: ['logFailure'], codes }],
    },
  },
  {
    // A2: the debug echo and the debug logger may print (FAILURES.md 2).
    files: printExempt,
    rules: { 'no-console': 'off', 'sellwild/no-global-console': 'off' },
  },
  {
    // The logFailure shell: its own catch cannot report, it would recurse
    // (FAILURES.md 3.4 item 4). It counts internalErrors instead.
    files: ['src/failures/index.ts'],
    rules: { 'sellwild/catch-reports-failure': 'off' },
  },
)
