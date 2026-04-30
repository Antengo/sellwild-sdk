import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import {
  View,
  StyleSheet,
  ActivityIndicator,
  ViewStyle,
} from 'react-native'
import { WebView } from 'react-native-webview'
import type { WebViewMessageEvent } from 'react-native-webview'
import type { SellwildConfig, SellwildListing } from '@sellwild/sdk-core'
import { buildConfig, WIDGET_BASE_URL } from '@sellwild/sdk-core'
import type { PartialSellwildConfig } from '@sellwild/sdk-core'
import { buildWidgetHtml } from './htmlBuilder'

export interface SellwildWidgetProps {
  config: PartialSellwildConfig
  style?: ViewStyle
  onListingPress?: (listing: SellwildListing) => void
  onAdImpression?: (zoneId: string | number) => void
  onError?: (error: Error) => void
  onLoad?: () => void
}

// The web widget intercepts window.open() and sends the listing URL.
// A full SellwildListing object is not available from the WebView boundary —
// the listing field will be absent; url contains the Sellwild product page URL.
type WebViewMessage =
  | { type: 'LISTING_CLICK'; listing?: SellwildListing; url?: string }
  | { type: 'AD_IMPRESSION'; zoneId: string | number }
  | { type: 'WIDGET_LOADED' }
  | { type: 'ERROR'; message: string }

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

  const handleMessage = useCallback(
    (event: WebViewMessageEvent) => {
      try {
        const msg: WebViewMessage = JSON.parse(event.nativeEvent.data)
        switch (msg.type) {
          case 'LISTING_CLICK':
            // The web widget sends a URL via window.open() interception.
            // A full listing object is not available at the WebView boundary.
            // Pass the listing if somehow present (future compatibility),
            // otherwise construct a minimal stub so callers can navigate.
            if (msg.listing) {
              onListingPress?.(msg.listing)
            } else if (msg.url && onListingPress) {
              const stub: SellwildListing = {
                id: '', status: 'active', title: '',
                text: '', url: msg.url, categoryId: '', categoryGroupId: '',
                currency: 'USD', price: '', strikePrice: '',
                has_photo: false, photo_count: 0, photos: [],
                createdDate: '', videoUrl: '', shippable: '',
                listingType: '', dataSourceId: '',
                user: { id: '', firstName: '', lastName: '', username: '',
                        membershipType: '', trustLevel: '', has_photo: '',
                        photos: [], isPhoneVerified: false },
              }
              onListingPress(stub)
            }
            break
          case 'AD_IMPRESSION':
            onAdImpression?.(msg.zoneId)
            break
          case 'WIDGET_LOADED':
            setLoading(false)
            onLoad?.()
            break
          case 'ERROR':
            onError?.(new Error(msg.message))
            break
        }
      } catch {
        // Non-SDK message, ignore
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
          onError?.(new Error(nativeEvent.description))
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
