// Runs the scripts the SDK injects into its WebView pages (src/htmlBuilder.ts)
// against a fake window and document, and records what they post through
// window.ReactNativeWebView.postMessage. Those strings are the real bridge
// messages the SDK produces, captured without a WebView, so tests can check
// them against the contract and feed them to SellwildWidget's onMessage.

/** The inline <script> blocks of a page that post through ReactNativeWebView. */
export function bridgeScripts(html: string): string[] {
  const scripts: string[] = []
  const inline = /<script>([\s\S]*?)<\/script>/g
  for (let m = inline.exec(html); m; m = inline.exec(html)) {
    if (m[1].includes('ReactNativeWebView')) scripts.push(m[1])
  }
  return scripts
}

type Listener = (event: { message?: string }) => void

// A window and document with only what the injected scripts touch. Without
// `bridge`, window.ReactNativeWebView is missing, as in a page that is not
// inside a React Native WebView.
function fakePage(bridge: boolean) {
  const posted: string[] = []
  const windowListeners: Record<string, Listener> = {}
  const documentListeners: Record<string, Listener> = {}
  const timers: Array<() => void> = []
  const appended: Array<{ onload?: () => void }> = []
  const window: Record<string, unknown> = {
    ReactNativeWebView: bridge
      ? {
          postMessage(data: string) {
            posted.push(data)
          },
        }
      : undefined,
    // What the widget script's window.open override falls back to.
    open: (): null => null,
    addEventListener(type: string, listener: Listener) {
      windowListeners[type] = listener
    },
  }
  const document = {
    addEventListener(type: string, listener: Listener) {
      documentListeners[type] = listener
    },
    createElement: (): { onload?: () => void } => ({}),
    getElementById: () => ({
      appendChild(el: { onload?: () => void }) {
        appended.push(el)
      },
    }),
  }
  const setTimeout = (fn: () => void): number => timers.push(fn)
  return { posted, windowListeners, documentListeners, timers, appended, window, document, setTimeout }
}

function run(html: string, bridge = true) {
  const page = fakePage(bridge)
  const scripts = bridgeScripts(html)
  if (scripts.length === 0) throw new Error('no ReactNativeWebView script in the page')
  for (const script of scripts) {
    new Function('window', 'document', 'setTimeout', script)(page.window, page.document, page.setTimeout)
  }
  return page
}

export interface WidgetPage {
  /** The strings posted so far, as onMessage receives them in nativeEvent.data. */
  posted: string[]
  /** The page's window (to read what the script left on it). */
  window: Record<string, unknown>
  /** The widget opens a listing: it calls window.open(url). */
  openListing(url: string): void
  /** DOMContentLoaded, then the timer that sends WIDGET_LOADED. */
  loadDom(): void
  /** A window 'error' event, with `message` or without one. */
  scriptError(message?: string): void
}

/** Load the script of buildWidgetHtml's page. `bridge: false` leaves out window.ReactNativeWebView. */
export function runWidgetPage(html: string, { bridge = true }: { bridge?: boolean } = {}): WidgetPage {
  const page = run(html, bridge)
  return {
    posted: page.posted,
    window: page.window,
    openListing: (url) => {
      (page.window.open as (url: string) => unknown)(url)
    },
    loadDom: () => {
      page.documentListeners.DOMContentLoaded?.({})
      for (const fn of page.timers.splice(0)) fn()
    },
    scriptError: (message) => page.windowListeners.error?.(message === undefined ? {} : { message }),
  }
}

export interface BannerPage {
  posted: string[]
  /** The zone ad script finished loading. */
  adLoaded(): void
}

/** Load the script of buildBannerHtml's page (the zone-script path: no GAM tag). */
export function runBannerPage(html: string): BannerPage {
  const page = run(html)
  return {
    posted: page.posted,
    adLoaded: () => {
      for (const el of page.appended) el.onload?.()
    },
  }
}
