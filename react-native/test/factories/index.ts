// Mock factories for every external payload React Native reads or sends: its
// own (the native config) plus core's, which React Native reads through core
// (core/test/factories, see base.ts there).

export * from '../../../core/test/factories'
// One invalid contract fixture as it arrives on the wire. Each one is checked
// to fail its schema for the declared reason (core's factory tests and
// expectInvalidCases here).
export { invalidPayload } from '../../../core/test/factories/base'
export * from './rnNativeConfig'
export * from './wrongTypedAppConfig'
