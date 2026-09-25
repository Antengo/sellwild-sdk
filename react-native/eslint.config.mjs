// ESLint for @sellwild/react-native-sdk: src, test and the vitest config.
// The native code (ios/, android/, native-checks/) has its own linters.
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
// House failure rules (contracts/FAILURES.md 1, 2, 9):
//   no-console                      src: React Native JS has no A2 module of its own (it uses core's)
//   sellwild/no-global-console      src: console through globalThis, window, self or global
//   sellwild/no-silent-catch        everywhere: empty catches (comments do not count) and swallowing .catch handlers
//   sellwild/catch-reports-failure  src: every catch calls logFailure, rethrows or hands on a registry code.
//                                   useSellwildListings' .catch (log once, FAILURES.md 9.2) carries its
//                                   own eslint-disable-next-line.
//   sellwild/disable-reason         everywhere: turning off a sellwild/* rule needs "-- FAILURES.md <section>: <why>"
// The rules live in contracts/lint/eslint-plugin-sellwild.mjs, shared with
// core and (vendored) the widget.

import fs from 'node:fs'
import js from '@eslint/js'
import { defineConfig } from 'eslint/config'
import globals from 'globals'
import tseslint from 'typescript-eslint'
import sellwild from '../contracts/lint/eslint-plugin-sellwild.mjs'
import { PRINT_EXEMPT } from '../contracts/scripts/print-gate.mjs'

const PACKAGE = 'react-native/'

/** Registry codes: a string handed on from a catch must be one of these. */
const codes = JSON.parse(fs.readFileSync(new URL('../contracts/failure-codes.json', import.meta.url), 'utf8')).map((entry) => entry.code)

/** The A2 modules of this package, relative to it (none today). */
const printExempt = PRINT_EXEMPT.filter((file) => file.startsWith(PACKAGE)).map((file) => file.slice(PACKAGE.length))

export default defineConfig(
  { ignores: ['coverage/', 'ios/', 'android/', 'native-checks/'] },
  { linterOptions: { reportUnusedDisableDirectives: 'error' } },
  js.configs.recommended,
  tseslint.configs.recommendedTypeChecked,
  {
    languageOptions: {
      parserOptions: {
        // tsconfig.test.json covers src, test and vitest.config.ts;
        // tsconfig.json holds test/stubs/rn-globals.d.ts, which the test one leaves out.
        project: ['./tsconfig.test.json', './tsconfig.json'],
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
    files: ['src/**/*.{ts,tsx}'],
    rules: {
      'no-console': 'error',
      'sellwild/no-global-console': 'error',
      'sellwild/catch-reports-failure': ['error', { reporters: ['logFailure'], codes }],
    },
  },
  ...(printExempt.length ? [{ files: printExempt, rules: { 'no-console': 'off', 'sellwild/no-global-console': 'off' } }] : []),
)
