// Mock factories for every external payload React Native reads or sends: its
// own (the bridge message and the native config) plus core's, which React
// Native reads through core (core/test/factories, see base.ts there).

export * from '../../../core/test/factories'
export * from './bridgeMessage'
export * from './rnNativeConfig'
