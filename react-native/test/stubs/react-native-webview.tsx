// Test double for 'react-native-webview'. vitest.config.ts aliases the
// package to this file. WebView renders a host 'WebView' element, so
// react-test-renderer records its props (source, onMessage, onError, ...).
// A test drives it by calling those props, for example
// tree.root.findByType('WebView').props.onMessage({ nativeEvent: { data } }).
import React from 'react'
import { vi, type Mock } from 'vitest'

export interface WebViewMessageEvent {
  nativeEvent: { data: string; url?: string }
}

/** The imperative methods a WebView ref exposes, as mocks. */
export interface WebViewHandle {
  injectJavaScript: Mock<(script: string) => void>
  postMessage: Mock<(message: string) => void>
  reload: Mock<() => void>
  stopLoading: Mock<() => void>
  goBack: Mock<() => void>
  goForward: Mock<() => void>
}

export type WebView = WebViewHandle

export const WebView = React.forwardRef<WebViewHandle, Record<string, unknown>>(
  function WebView(props, ref) {
    const handle = React.useMemo<WebViewHandle>(
      () => ({
        injectJavaScript: vi.fn(),
        postMessage: vi.fn(),
        reload: vi.fn(),
        stopLoading: vi.fn(),
        goBack: vi.fn(),
        goForward: vi.fn(),
      }),
      [],
    )
    React.useImperativeHandle(ref, () => handle, [handle])
    // A string type makes a host element. JSX <WebView> would mean this
    // component again.
    return React.createElement('WebView', props)
  },
)
