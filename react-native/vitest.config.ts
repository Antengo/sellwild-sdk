import { coverageConfigDefaults, defineConfig } from 'vitest/config'

const here = (path: string) => decodeURIComponent(new URL(path, import.meta.url).pathname)

// Files the 95% gate measures. scripts/coverage/ts.mjs reads this and the
// exclusions below to write coverage-summary/react-native.json, so keep
// them here.
export const coverageInclude = ['src/**']

// Gate exclusions (contract A10). Each one needs a reason.
export const coverageExclusions: Array<{ path: string; reason: string }> = [
  {
    // buildBannerHtml and its helpers: no component, sample or doc in the
    // repo calls them (<SellwildBanner> is a native view since 1.3.0).
    // htmlBuilder.ts still re-exports buildBannerHtml.
    path: 'src/bannerHtml.ts',
    reason: 'dead: pending delete decision',
  },
  {
    // Not under src/**, so outside the gate anyway; listed so the summary
    // names them.
    path: 'ios/**',
    reason: 'RN native bridge glue: needs an RN host app build',
  },
  {
    path: 'android/**',
    reason: 'RN native bridge glue: needs an RN host app build',
  },
]

// `vitest run --coverage` is the gate: exclusions applied, 95% thresholds.
// `vitest run --coverage --mode whole` measures every source file with no
// thresholds, into coverage/whole, for the `whole` block of the summary.
export default defineConfig(({ mode }) => {
  const whole = mode === 'whole'
  return {
    // src uses the classic runtime (`import React from 'react'`).
    esbuild: { jsx: 'transform', jsxFactory: 'React.createElement', jsxFragment: 'React.Fragment' },
    resolve: {
      alias: [
        // No React Native runtime in tests: both packages are stubs.
        { find: /^react-native$/, replacement: here('./test/stubs/react-native.ts') },
        { find: /^react-native-webview$/, replacement: here('./test/stubs/react-native-webview.tsx') },
        // Test the core source in this repo, not the published build in
        // node_modules. Matches the paths entry in tsconfig.json.
        { find: /^@sellwild\/sdk-core$/, replacement: here('../core/src/index.ts') },
      ],
    },
    test: {
      environment: 'node',
      include: ['test/**/*.test.{ts,tsx}'],
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
