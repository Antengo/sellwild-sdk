import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import {
  View,
  StyleSheet,
  ActivityIndicator,
  ViewStyle,
} from 'react-native'
import { WebView } from 'react-native-webview'
import type { WebViewMessageEvent } from 'react-native-webview'
import type { SellwildListing } from '@sellwild/sdk-core'
import { buildConfig } from '@sellwild/sdk-core'
import type { PartialSellwildConfig } from '@sellwild/sdk-core'
import { logFailure } from './failures'
import { buildWidgetHtml, unwritableRemoteKeys } from './htmlBuilder'
import {
  bridgeFailureReport,
  decodeWidgetMessage,
  httpErrorReport,
  listingStub,
  loadErrorReport,
} from './widgetBridge'

export interface SellwildWidgetProps {
  config: PartialSellwildConfig
  style?: ViewStyle
  onListingPress?: (listing: SellwildListing) => void
  onAdImpression?: (zoneId: string | number) => void
  onError?: (error: Error) => void
  onLoad?: () => void
}

// Calls the host callback `name`. One that throws is reported
// (widget.host_callback.exception) and not rethrown: it runs inside the
// WebView's onMessage, where the old catch-all swallowed it silently.
function callHost(name: string, call: () => void): void {
  try {
    call()
  } catch (error) {
    logFailure({
      code: 'widget.host_callback.exception',
      component: 'webview',
      severity: 'warn',
      error,
      message: `${name} threw`,
    })
  }
}

export function SellwildWidget({
  config: configProp,
  style,
  onListingPress,
  onAdImpression,
  onError,
  onLoad,
}: SellwildWidgetProps) {
  // Memoize so that parent re-renders don't change `source.html`, which
  // would force react-native-webview to reload and lose ad session state.
  const config = useMemo(() => buildConfig(configProp), [
    configProp.partnerCode,
    configProp.listingsUrl,
    configProp.gamTag,
    configProp.gptProxyUrl,
    configProp.bannerZid,
    configProp.debug,
  ])
  const [loading, setLoading] = useState(true)
  const webViewRef = useRef<WebView>(null)

  const html = useMemo(() => buildWidgetHtml(config), [config])

  // The page leaves out a remote key that cannot be an attribute name, since
  // it would break the widget tag. Reported once per config, with the count
  // only: the keys are CMS data.
  useEffect(() => {
    const left = unwritableRemoteKeys(config).length
    if (left) {
      logFailure({
        code: 'config.field.invalid',
        component: 'webview',
        severity: 'warn',
        message: `remote keys that cannot be widget attribute names were left out: ${left}`,
      })
    }
  }, [config])

  const handleMessage = useCallback(
    (event: WebViewMessageEvent) => {
      // A message the page should not have sent is reported once
      // (bridge.message.*). One with a wrong-typed field is still routed as
      // before.
      const { action, failure } = decodeWidgetMessage(event.nativeEvent.data)
      if (failure) logFailure(bridgeFailureReport(failure))
      if (!action) return
      switch (action.kind) {
        case 'listing':
          callHost('onListingPress', () => onListingPress?.(action.listing))
          break
        case 'listingUrl':
          // A full listing object is not available at the WebView boundary:
          // a minimal stub carries the URL so callers can navigate.
          if (onListingPress) callHost('onListingPress', () => onListingPress(listingStub(action.url)))
          break
        case 'impression':
          callHost('onAdImpression', () => onAdImpression?.(action.zoneId))
          break
        case 'loaded':
          setLoading(false)
          callHost('onLoad', () => onLoad?.())
          break
        case 'scriptError':
          // A script error inside the widget page. The page cannot report
          // it itself, so it is reported here, before the host hears of it
          // (once: an ERROR message with a wrong-typed message was reported
          // above instead).
          if (!failure) logFailure({ code: 'bridge.script.exception', component: 'webview', message: action.message })
          callHost('onError', () => onError?.(new Error(action.message)))
          break
      }
    },
    [onListingPress, onAdImpression, onError, onLoad]
  )

  return (
    <View style={[styles.container, style]}>
      {loading && (
        <View style={styles.loader}>
          <ActivityIndicator size="large" />
        </View>
      )}
      <WebView
        ref={webViewRef}
        source={{ html, baseUrl: 'https://widget.sellwild.com/' }}
        style={styles.webView}
        onMessage={handleMessage}
        javaScriptEnabled
        domStorageEnabled
        thirdPartyCookiesEnabled
        allowsInlineMediaPlayback
        mediaPlaybackRequiresUserAction={false}
        mixedContentMode="compatibility"
        originWhitelist={['*']}
        onError={syntheticEvent => {
          const { nativeEvent } = syntheticEvent
          // The WebView failed to load its page. Reported before the host
          // hears of it; a host onError that throws still throws, as before.
          logFailure(loadErrorReport(nativeEvent))
          onError?.(new Error(nativeEvent.description))
        }}
        onHttpError={syntheticEvent => {
          // An HTTP error status for the page. Reported only: onError never
          // heard of these, and does not start to.
          logFailure(httpErrorReport(syntheticEvent.nativeEvent))
        }}
      />
    </View>
  )
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    minHeight: 300,
  },
  webView: {
    flex: 1,
    backgroundColor: 'transparent',
  },
  loader: {
    ...StyleSheet.absoluteFillObject,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: '#f5f5f5',
    zIndex: 1,
  },
})
