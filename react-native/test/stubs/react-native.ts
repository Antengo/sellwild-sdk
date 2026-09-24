// Test double for the 'react-native' package. vitest.config.ts aliases
// 'react-native' to this file, so src runs without the React Native runtime.
// It models what react-native/src uses, plus Dimensions and Linking.
//
// Components render a host element of the same name, so react-test-renderer
// records their props: tree.root.findByType('View').props.
//
// The stub is built once per test file and kept on globalThis. A copy of this
// module made after vi.resetModules() exports the same objects, so a change
// made through any copy is seen by all of them, and test/setup.ts's
// resetReactNativeStub() after every test undoes it everywhere.
//
// SellwildBanner and SellwildFeed probe UIManager when their module loads, so
// a test that changes the registered view managers does that first, then
// vi.resetModules() and imports the component again.
import React from 'react'
import { vi, type Mock } from 'vitest'

type HostProps = { children?: React.ReactNode; [prop: string]: unknown }

function hostComponent(name: string) {
  const component = React.forwardRef<unknown, HostProps>((props, ref) =>
    React.createElement(name, { ...props, ref }),
  )
  component.displayName = name
  return component
}

// Type-only names src imports from 'react-native'. esbuild drops them, so
// these exist for the stub's own type-check.
export type ViewStyle = Record<string, unknown>
export type StyleProp<T> = T | ReadonlyArray<StyleProp<T>> | null | undefined | false
export type NativeSyntheticEvent<T> = { nativeEvent: T }

type OS = 'ios' | 'android'

export interface SellwildRNModuleStub {
  setGeo: Mock<(geo: Record<string, unknown>) => void>
  setExternalUserIds: Mock<(eids: unknown[]) => void>
  prewarm: Mock<(config: Record<string, unknown>) => void>
  // Not in the native modules yet. contracts/FAILURES.md section 3.1 item 5
  // adds it for the failure `wrapper` attribute.
  setWrapper: Mock<(wrapper: string) => void>
}

// The native view managers the SDK registers on iOS and Android.
const DEFAULT_VIEW_MANAGERS = ['SellwildBannerView', 'SellwildFeedView']

function flatten(style: unknown): Record<string, unknown> {
  if (Array.isArray(style)) {
    return style.reduce<Record<string, unknown>>((out, s) => ({ ...out, ...flatten(s) }), {})
  }
  return style && typeof style === 'object' ? { ...(style as Record<string, unknown>) } : {}
}

function makeStub() {
  const viewManagers = new Set(DEFAULT_VIEW_MANAGERS)

  const absoluteFillObject = { position: 'absolute', left: 0, right: 0, top: 0, bottom: 0 } as const
  const StyleSheet = {
    create: <T extends Record<string, object>>(styles: T): T => styles,
    flatten,
    absoluteFillObject,
    absoluteFill: absoluteFillObject,
    hairlineWidth: 1,
  }

  const Platform = {
    OS: 'ios' as OS,
    select<T>(spec: { ios?: T; android?: T; native?: T; default?: T }): T | undefined {
      return spec[Platform.OS] ?? spec.native ?? spec.default
    },
  }

  // One module object: commands.ts keeps the reference it read at load, so
  // the reset repairs this object instead of replacing it.
  const moduleMethods: SellwildRNModuleStub = {
    setGeo: vi.fn(),
    setExternalUserIds: vi.fn(),
    prewarm: vi.fn(),
    setWrapper: vi.fn(),
  }
  const sellwildRNModule: SellwildRNModuleStub = { ...moduleMethods }
  const NativeModules: { SellwildRNModule?: SellwildRNModuleStub } = {
    SellwildRNModule: sellwildRNModule,
  }

  const UIManager = {
    getViewManagerConfig: vi.fn((name: string) => (viewManagers.has(name) ? { Commands: {} } : null)),
    hasViewManagerConfig: vi.fn((name: string) => viewManagers.has(name)),
  }

  // A test that needs another size uses Dimensions.get.mockReturnValue(...).
  const Dimensions = {
    get: vi.fn((_dim: 'window' | 'screen') => ({ width: 390, height: 844, scale: 3, fontScale: 1 })),
    addEventListener: vi.fn(() => ({ remove: vi.fn() })),
  }

  const Linking = {
    openURL: vi.fn(async (_url: string): Promise<void> => undefined),
    canOpenURL: vi.fn(async (_url: string): Promise<boolean> => true),
  }

  // Each object's own properties as built. The reset puts them back and
  // drops any a test added.
  const originals = new Map<object, Record<string, unknown>>([
    [StyleSheet, { ...StyleSheet }],
    [Platform, { ...Platform }],
    [sellwildRNModule, { ...moduleMethods }],
    [NativeModules, { SellwildRNModule: sellwildRNModule }],
    [UIManager, { ...UIManager }],
    [Dimensions, { ...Dimensions }],
    [Linking, { ...Linking }],
  ])

  return {
    View: hostComponent('View'),
    Text: hostComponent('Text'),
    Image: hostComponent('Image'),
    TouchableOpacity: hostComponent('TouchableOpacity'),
    ActivityIndicator: hostComponent('ActivityIndicator'),
    StyleSheet,
    Platform,
    NativeModules,
    UIManager,
    // Like React Native, returns the view manager name, which React renders
    // as a host element that records its props.
    requireNativeComponent: vi.fn((name: string) => name),
    Dimensions,
    Linking,
    viewManagers,
    originals,
  }
}

type Stub = ReturnType<typeof makeStub>

const STUB = Symbol.for('sellwild.test.reactNativeStub')
const stub: Stub = ((globalThis as { [STUB]?: Stub })[STUB] ??= makeStub())

export const {
  View,
  Text,
  Image,
  TouchableOpacity,
  ActivityIndicator,
  StyleSheet,
  Platform,
  NativeModules,
  UIManager,
  requireNativeComponent,
  Dimensions,
  Linking,
} = stub

// ─── Test controls ───────────────────────────────────────────────────────────

/** Sets which native view managers UIManager reports as registered. */
export function setRegisteredViewManagers(names: string[]): void {
  stub.viewManagers.clear()
  for (const name of names) stub.viewManagers.add(name)
}

/**
 * Back to defaults: iOS, both view managers registered, native module linked
 * with all its methods, no property a test replaced or added. Mock call
 * history is cleared by setup's vi.resetAllMocks().
 */
export function resetReactNativeStub(): void {
  for (const [target, original] of stub.originals) {
    const props = target as Record<string, unknown>
    for (const key of Object.keys(props)) {
      if (!(key in original)) delete props[key]
    }
    Object.assign(props, original)
  }
  setRegisteredViewManagers(DEFAULT_VIEW_MANAGERS)
}
