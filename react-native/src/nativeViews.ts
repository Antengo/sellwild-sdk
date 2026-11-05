import React from 'react'
import { requireNativeComponent, UIManager } from 'react-native'
import type { HostComponent } from 'react-native'
import { logFailure } from './failures'

// The native view managers <SellwildBanner> and <SellwildFeed> render.

/**
 * The native view manager `name` as a component, or null when this build does
 * not register it. requireNativeComponent crashes loudly for a name that is
 * not registered, so probe first. Call it once per name, at module load, as
 * before: React Native refuses a second registration of the same name.
 */
export function nativeViewOrNull<P extends object>(name: string): HostComponent<P> | null {
  const config = UIManager.getViewManagerConfig?.(name)
  if (!config) return null
  return requireNativeComponent<P>(name)
}

// Names already reported: the missing view manager is reported once per
// process, the first time a component that needs it renders.
const reportedMissing = new Set<string>()

/**
 * Reports bridge.native_view.missing once, after the first render of a
 * component whose native view manager `name` is not registered. Not at module
 * load: an app that imports the package but never renders the view has
 * nothing to report. Only React Native JS sees this failure.
 */
export function useMissingNativeViewReport(name: string, component: 'banner' | 'feed', missing: boolean): void {
  React.useEffect(() => {
    if (!missing || reportedMissing.has(name)) return
    reportedMissing.add(name)
    logFailure({
      code: 'bridge.native_view.missing',
      component,
      message: `${name} is not registered in this build`,
    })
  }, [name, component, missing])
}
