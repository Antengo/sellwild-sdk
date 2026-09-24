import { coverageConfigDefaults, defineConfig } from 'vitest/config'

// Files the 95% gate measures. scripts/coverage/ts.mjs reads this and the
// exclusions below to write coverage-summary/core.json, so keep them here.
export const coverageInclude = ['src/**']

// Gate exclusions (contract A10). Each one needs a reason.
export const coverageExclusions: Array<{ path: string; reason: string }> = [
  { path: 'src/types.ts', reason: 'type-only: interfaces and type aliases, compiles to an empty module' },
]

// `vitest run --coverage` is the gate: exclusions applied, 95% thresholds.
// `vitest run --coverage --mode whole` measures every source file with no
// thresholds, into coverage/whole, for the `whole` block of the summary.
export default defineConfig(({ mode }) => {
  const whole = mode === 'whole'
  return {
    test: {
      environment: 'node',
      include: ['test/**/*.test.ts'],
      setupFiles: ['test/setup.ts'],
      coverage: {
        provider: 'v8',
        // Count lines and branches from the source AST, as istanbul does.
        // The default v8 remap skips branches in functions that never ran
        // and counts comment and type-only lines, which overstates coverage.
        experimentalAstAwareRemapping: true,
        all: true,
        include: coverageInclude,
        exclude: [
          ...coverageConfigDefaults.exclude,
          ...(whole ? [] : coverageExclusions.map((e) => e.path)),
        ],
        reporter: whole
          ? ['json-summary', 'json']
          : ['text-summary', 'json-summary', 'json', 'lcov', 'html'],
        reportsDirectory: whole ? 'coverage/whole' : 'coverage',
        reportOnFailure: true,
        thresholds: whole
          ? undefined
          : { lines: 95, branches: 95, functions: 95, statements: 95 },
      },
    },
  }
})
