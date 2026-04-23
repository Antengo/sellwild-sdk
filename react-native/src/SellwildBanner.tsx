import React, { useCallback, useState } from 'react'
import { View, StyleSheet, ViewStyle } from 'react-native'
import { WebView } from 'react-native-webview'
import type { WebViewMessageEvent } from 'react-native-webview'
import type { SellwildConfig, AdSize } from '@sellwild/sdk-core'
import { WIDGET_BASE_URL } from '@sellwild/sdk-core'
import { buildBannerHtml } from './htmlBuilder'

// Standard IAB mobile ad sizes
const AD_DIMENSIONS: Record<AdSize, { width: number; height: number }> = {
  '300x250': { width: 300, height: 250 },
  '320x50': { width: 320, height: 50 },
  '728x90': { width: 728, height: 90 },
  '160x600': { width: 160, height: 600 },
  '300x600': { width: 300, height: 600 },
  '1x1': { width: 1, height: 1 },
}

export interface SellwildBannerProps {
  config: SellwildConfig
  size: AdSize
  zoneId: number | string
  style?: ViewStyle
  onImpression?: () => void
  onClick?: () => void
  onError?: (error: Error) => void
}

export function SellwildBanner({
  config,
  size,
  zoneId,
  style,
  onImpression,
  onClick,
  onError,
}: SellwildBannerProps) {
  const dimensions = AD_DIMENSIONS[size]
  const html = buildBannerHtml(config, zoneId, size)

  const handleMessage = useCallback(
    (event: WebViewMessageEvent) => {
      try {
        const msg = JSON.parse(event.nativeEvent.data)
        if (msg.type === 'AD_IMPRESSION') onImpression?.()
        if (msg.type === 'AD_CLICK') onClick?.()
      } catch {
        // ignore
      }
    },
    [onImpression, onClick]
  )

  return (
    <View style={[{ width: dimensions.width, height: dimensions.height }, style]}>
      <WebView
        source={{ html, baseUrl: WIDGET_BASE_URL }}
        style={StyleSheet.absoluteFill}
        onMessage={handleMessage}
        javaScriptEnabled
        domStorageEnabled
        thirdPartyCookiesEnabled
        scrollEnabled={false}
        showsVerticalScrollIndicator={false}
        showsHorizontalScrollIndicator={false}
        mixedContentMode="compatibility"
        originWhitelist={['*']}
        onError={syntheticEvent => {
          onError?.(new Error(syntheticEvent.nativeEvent.description))
        }}
      />
    </View>
  )
}
