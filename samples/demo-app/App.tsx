import React, { useCallback, useEffect, useMemo, useState } from 'react'
import Clipboard from '@react-native-clipboard/clipboard'
import {
  Dimensions,
  FlatList,
  Image,
  Linking,
  SafeAreaView,
  ScrollView,
  StatusBar,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
  ActivityIndicator,
} from 'react-native'
import {
  SellwildWidget,
  useSellwildListings,
  buildConfig,
  configure,
  clearRemoteConfigCache,
} from '@sellwild/react-native-sdk'
import type { SellwildListing, SellwildConfig, PartialSellwildConfig } from '@sellwild/react-native-sdk'
import { currencyToSymbol } from '@sellwild/sdk-core'
import { WebView } from 'react-native-webview'

const { width: SCREEN_WIDTH } = Dimensions.get('window')
const CARD_GAP = 10
const CARD_WIDTH = (SCREEN_WIDTH - CARD_GAP * 3) / 2

const PBS_ENDPOINT = 'https://prebid.sellwild.com/openrtb2/auction'

// Static config — the minimum required fields. Everything else (bidders, refresh
// limits, geo-blocking, ad controls) comes from the remote app config on the CDN
// at https://widget.sellwild.com/app/weatherbug/weatherbug-weatherbug.json
// Managed via the CMS at sellwild-widget.netlify.app/admin-v2/app
const STATIC_CONFIG: PartialSellwildConfig = {
  partnerCode: 'weatherbug',
  listingsUrl: 'https://cache.sellwild.com/listings-img-data-sm-ferrarichat',
  appBundleId: 'com.aws.android',
  appStoreUrl: 'https://play.google.com/store/apps/details?id=com.aws.android',
  title: 'LOCAL DEALS NEAR YOU',
  titleSize: 20,
  linkText: 'VIEW ALL LISTINGS',
  linkSize: 16,
  linkColor: '#1a73e8',
  priceColor: '#1a73e8',
  colors: ['#1a73e8'],
  overlayTitle: true,
  cardWidth: '300px',
  bannerZid: '43',
  mobileZids: ['280'],
  widgetJsUrl: 'https://widget.sellwild.com/partner/index.js',
  debug: true,
} as PartialSellwildConfig

// Remote config slug — matches the CMS file app/weatherbug-weatherbug.md
const REMOTE_SLUG = 'weatherbug-weatherbug'

// ─── PBS Auction Types ───────────────────────────────────────────────────────

interface AuctionBid {
  price: number
  seat: string
  w: number
  h: number
  adm: string
  impid?: string // matches back to imp.id in the request
}

interface AuctionResult {
  loading: boolean
  responseTimes: Record<string, number>
  bids: AuctionBid[]
  errors: Record<string, string>
  totalTimeMs: number
}

// ─── Run PBS auctions per ad slot ────────────────────────────────────────────

interface SlotAuction extends AuctionResult {
  slotId: string
  size: string
}

const BIDDERS = {
  appnexus: { placement_id: 13144370 },
  pubmatic: { publisherId: '156209', adSlot: 'sellwild_300x250' },
  sharethrough: { pkey: 'abc123' },
  medianet: { cid: '8CU5JOKX4', crid: '451466393' },
}

const DEVICE = {
  ua: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0)',
  os: 'iOS', osv: '17.0', devicetype: 4,
  w: 390, h: 844,
}

const APP = {
  bundle: 'com.aws.android',
  name: 'WeatherBug',
  storeurl: 'https://play.google.com/store/apps/details?id=com.aws.android',
  publisher: { id: 'sellwild' },
}

interface MultiAuctionResult {
  loading: boolean
  auctionId: string
  slots: SlotAuction[]
  totalTimeMs: number
  responseTimes: Record<string, number>
}

async function runMultiSlotAuction(): Promise<MultiAuctionResult> {
  const start = Date.now()
  try {
    // Single OpenRTB request with multiple imp objects — one per ad slot
    const imps = [
      {
        id: 'banner-top',
        banner: { format: [{ w: 320, h: 50 }] },
        bidfloor: 0.01,
        bidfloorcur: 'USD',
        ext: { prebid: { bidder: BIDDERS } },
      },
      {
        id: 'mrec-inline',
        banner: { format: [{ w: 300, h: 250 }] },
        video: {
          mimes: ['video/mp4'],
          protocols: [1, 2, 3, 4, 5, 6],
          w: 300, h: 250,
          linearity: 1,
          placement: 2,
        },
        bidfloor: 0.01,
        bidfloorcur: 'USD',
        ext: { prebid: { bidder: BIDDERS } },
      },
    ]

    // Retry up to 3 times for reliable fill
    for (let attempt = 0; attempt < 3; attempt++) {
      const res = await fetch(PBS_ENDPOINT, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          id: `auction-${Date.now()}`,
          test: 1,
          imp: imps,
          app: APP,
          device: DEVICE,
          tmax: 3000,
        }),
      })
      const d = await res.json()
      const auctionId = d?.id || `auction-${Date.now()}`
      const totalTimeMs = Date.now() - start
      const responseTimes = d?.ext?.responsetimemillis || {}

      // Collect all bids and match to imp by impid
      const allBids: AuctionBid[] = []
      for (const sb of d?.seatbid || []) {
        for (const b of sb?.bid || []) {
          allBids.push({ price: b.price, seat: sb.seat, w: b.w || 0, h: b.h || 0, adm: b.adm || '', impid: b.impid })
        }
      }

      const errors: Record<string, string> = {}
      for (const [k, v] of Object.entries(d?.ext?.errors || {})) {
        const arr = v as any[]
        if (arr?.[0]?.message) errors[k] = arr[0].message.slice(0, 60)
      }

      // Build per-slot results
      const slots: SlotAuction[] = imps.map(imp => {
        const slotBids = allBids.filter(b => (b as any).impid === imp.id)
        const w = imp.banner.format[0].w
        const h = imp.banner.format[0].h
        return {
          loading: false,
          slotId: imp.id,
          size: `${w}x${h}`,
          responseTimes,
          bids: slotBids,
          errors,
          totalTimeMs,
        }
      })

      if (allBids.length > 0 || attempt === 2) {
        return { loading: false, auctionId, slots, totalTimeMs, responseTimes }
      }
    }
  } catch (e: any) {
    return {
      loading: false,
      auctionId: '',
      totalTimeMs: Date.now() - start,
      responseTimes: {},
      slots: [
        { loading: false, slotId: 'banner-top', size: '320x50', responseTimes: {}, bids: [], errors: { fetch: e.message }, totalTimeMs: 0 },
        { loading: false, slotId: 'mrec-inline', size: '300x250', responseTimes: {}, bids: [], errors: { fetch: e.message }, totalTimeMs: 0 },
      ],
    }
  }
  return { loading: false, auctionId: '', slots: [], totalTimeMs: Date.now() - start, responseTimes: {} }
}

// ─── Ad Creative Renderer ────────────────────────────────────────────────────

function isRenderable(adm: string): boolean {
  if (!adm || adm.length < 20) return false
  // VAST video — we can render these now
  if (adm.includes('<VAST') || adm.includes('<?xml')) return true
  // HTML display
  return adm.includes('<img') || adm.includes('<div') || adm.includes('<a ') ||
         adm.includes('<script') || adm.includes('<iframe')
}

function buildCreativeHtml(adm: string, width: number, height: number): string {
  if (adm.includes('<VAST') || adm.includes('<?xml')) {
    // VAST video — parse out MediaFile and companion image
    const mp4Match = adm.match(/type='video\/mp4'[^>]*>\s*<!\[CDATA\[(.*?)\]\]>/s)
    const companionMatch = adm.match(/creativeType='image\/jpeg'[^>]*>\s*<!\[CDATA\[(.*?)\]\]>/s)
    const videoUrl = mp4Match?.[1]?.trim() || ''
    const companionUrl = companionMatch?.[1]?.trim() || ''

    // 300x250+: show video. 320x50: show companion image (video doesn't fit a banner)
    const useVideo = videoUrl && height >= 200
    const tag = useVideo
      ? `<video src="${videoUrl}" autoplay muted playsinline loop style="width:100%;height:100%;object-fit:contain"></video>`
      : companionUrl
        ? `<img src="${companionUrl}" style="width:100%;height:100%;object-fit:cover">`
        : `<div style="color:#fff;font-size:12px;text-align:center;padding-top:14px">Ad</div>`

    return `<!DOCTYPE html><html><head>
      <meta name="viewport" content="width=device-width,initial-scale=1">
      <style>*{margin:0;padding:0}html,body{width:${width}px;height:${height}px;overflow:hidden;background:#000;display:flex;align-items:center;justify-content:center}</style>
      </head><body>${tag}</body></html>`
  }
  // Regular HTML creative
  return `<!DOCTYPE html><html><head>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <style>*{margin:0;padding:0}html,body{width:${width}px;height:${height}px;overflow:hidden;background:transparent}</style>
    </head><body>${adm}</body></html>`
}

function AdCreative({ adm, width, height }: { adm: string; width: number; height: number }) {
  const html = buildCreativeHtml(adm, width, height)
  return (
    <View style={{ width, height, borderRadius: 10, overflow: 'hidden' }}>
      <WebView
        source={{ html, baseUrl: 'https://widget.sellwild.com/' }}
        style={{ width, height, backgroundColor: '#000' }}
        scrollEnabled={false}
        javaScriptEnabled
        allowsInlineMediaPlayback
        mediaPlaybackRequiresUserAction={false}
        originWhitelist={['*']}
      />
    </View>
  )
}

function WinnerAd({ bid, size }: { bid: AuctionBid; size: '300x250' | '320x50' }) {
  const is300 = size === '300x250'
  return (
    <View style={[a.winnerAd, is300 ? a.winnerAd300 : a.winnerAd320]}>
      <View style={a.winnerAdInner}>
        <View style={a.winnerAdBidInfo}>
          <Text style={a.winnerAdSeat}>{bid.seat}</Text>
          <Text style={a.winnerAdCpm}>${bid.price.toFixed(2)}</Text>
        </View>
        {is300 ? (
          <>
            <Text style={a.winnerAdHeadline}>Programmatic Ad</Text>
            <Text style={a.winnerAdBody}>
              This ad was won by {bid.seat} at ${bid.price.toFixed(2)} CPM{'\n'}
              via prebid.sellwild.com in a server-side auction.
            </Text>
            <View style={a.winnerAdBadge}>
              <Text style={a.winnerAdBadgeText}>PREBID S2S</Text>
            </View>
          </>
        ) : (
          <Text style={a.winnerAdBodySmall}>
            Won by {bid.seat} · ${bid.price.toFixed(2)} CPM · Prebid S2S
          </Text>
        )}
      </View>
    </View>
  )
}

// ─── House Ad Component ──────────────────────────────────────────────────────

function HouseAd({ size }: { size: '300x250' | '320x50' }) {
  const is300 = size === '300x250'
  // WeatherBug brand: green bug #6AB344, blue text #4A90C4, header teal #4A6F8A
  return (
    <View style={[a.houseAd, is300 ? a.houseAd300 : a.houseAd320]}>
      <View style={a.houseAdInner}>
        {is300 ? (
          <>
            <View style={a.houseLogoRow}>
              <Text style={a.houseBugIcon}>{'🐛'}</Text>
              <Text style={a.houseLogoText}>WeatherBug</Text>
              <Text style={a.houseLogoReg}>{'®'}</Text>
            </View>
            <Text style={a.houseAdHeadline}>Know Before.{'\n'}Go Prepared.</Text>
            <Text style={a.houseAdBody}>Real-time forecasts, lightning alerts,{'\n'}pollen counts & live radar maps.</Text>
            <View style={a.houseAdCta}>
              <Text style={a.houseAdCtaText}>Download Free</Text>
            </View>
            <Text style={a.houseAdPowered}>Powered by GroundTruth</Text>
          </>
        ) : (
          <View style={a.houseBannerRow}>
            <Text style={a.houseBugSmall}>{'🐛'}</Text>
            <Text style={a.houseBannerLogo}>WeatherBug</Text>
            <Text style={a.houseBannerDivider}>|</Text>
            <Text style={a.houseBannerSub}>Live forecasts & alerts</Text>
            <View style={a.houseAdCtaSmall}>
              <Text style={a.houseAdCtaSmallText}>Get App</Text>
            </View>
          </View>
        )}
      </View>
      <View style={a.houseAdLabel}>
        <Text style={a.houseAdLabelText}>AD</Text>
      </View>
    </View>
  )
}

// ─── Auction Debug Panel ─────────────────────────────────────────────────────

function SlotAuctionPanel({ auction }: { auction: SlotAuction }) {
  const bidders = Object.keys(auction.responseTimes)
  const hasBids = auction.bids.length > 0

  return (
    <View style={a.slotPanel}>
      <View style={a.slotPanelHeader}>
        <Text style={a.slotPanelSize}>{auction.size}</Text>
        <Text style={a.slotPanelTime}>{auction.totalTimeMs}ms</Text>
      </View>
      {bidders.map(bidder => {
        const ms = auction.responseTimes[bidder]
        const bid = auction.bids.find(b => b.seat === bidder)
        const err = auction.errors[bidder]
        return (
          <View key={bidder} style={a.bidderRow}>
            <View style={[a.statusDot, bid ? a.dotGreen : err ? a.dotRed : a.dotGrey]} />
            <Text style={a.bidderName}>{bidder}</Text>
            <Text style={a.bidderMs}>{ms}ms</Text>
            {bid ? (
              <Text style={a.bidPrice}>${bid.price.toFixed(2)}</Text>
            ) : err ? (
              <Text style={a.bidNone}>error</Text>
            ) : (
              <Text style={a.bidNone}>no bid</Text>
            )}
          </View>
        )
      })}
      {hasBids && (
        <View style={a.winBox}>
          <Text style={a.winTitle}>Winner: {auction.bids[0].seat}</Text>
          <Text style={a.winDetail}>
            ${auction.bids[0].price.toFixed(2)} CPM — {auction.size} {
              auction.bids[0].adm.includes('<VAST')
                ? (parseInt(auction.size) <= 50 ? 'display (companion)' : 'video')
                : 'display'
            }
          </Text>
        </View>
      )}
    </View>
  )
}

const DASHBOARD_URL = 'http://localhost:3100'

function AuctionPanel({ slots, auctionId, onRefresh }: { slots: SlotAuction[]; auctionId: string; onRefresh: () => void }) {
  const totalImpressions = slots.filter(s => s.bids.length > 0).length
  const totalRevenue = slots.reduce((sum, s) => sum + (s.bids[0]?.price || 0), 0)
  const dashboardLink = auctionId ? `${DASHBOARD_URL}/auctions/${encodeURIComponent(auctionId)}` : ''

  return (
    <View style={a.panel}>
      <View style={a.panelHeader}>
        <Text style={a.panelTitle}>Prebid Server Auction</Text>
        <TouchableOpacity onPress={onRefresh} style={a.refreshBtn}>
          <Text style={a.refreshText}>Run Again</Text>
        </TouchableOpacity>
      </View>
      <Text style={a.panelEndpoint}>{PBS_ENDPOINT}</Text>
      <Text style={a.panelNote}>Single request, {slots.length} impressions</Text>

      {/* Summary stats */}
      <View style={a.statsRow}>
        <View style={a.statBox}>
          <Text style={a.statValue}>{slots.length}</Text>
          <Text style={a.statLabel}>Ad Slots</Text>
        </View>
        <View style={a.statBox}>
          <Text style={a.statValue}>{totalImpressions}</Text>
          <Text style={a.statLabel}>Filled</Text>
        </View>
        <View style={a.statBox}>
          <Text style={[a.statValue, { color: '#16A34A' }]}>${totalRevenue.toFixed(2)}</Text>
          <Text style={a.statLabel}>Total CPM</Text>
        </View>
        <View style={a.statBox}>
          <Text style={a.statValue}>{totalImpressions > 0 ? Math.round((totalImpressions / slots.length) * 100) : 0}%</Text>
          <Text style={a.statLabel}>Fill Rate</Text>
        </View>
      </View>

      {/* Dashboard deep-link */}
      {dashboardLink ? (
        <View style={a.dashboardLinkRow}>
          <Text style={a.dashboardLinkUrl} numberOfLines={1}>{dashboardLink}</Text>
          <TouchableOpacity
            style={a.copyBtn}
            onPress={() => Clipboard.setString(dashboardLink)}
          >
            <Text style={a.copyBtnText}>Copy</Text>
          </TouchableOpacity>
        </View>
      ) : null}

      {/* Per-slot breakdown */}
      {slots.map((slot, i) => (
        <SlotAuctionPanel key={slot.slotId} auction={slot} />
      ))}

      <View style={a.nofillBox}>
        <Text style={a.nofillTitle}>Using test placement IDs</Text>
        <Text style={a.nofillBody}>
          Plug in Weatherbug's real SSP seat IDs to see all bidders compete with real demand.
        </Text>
      </View>
    </View>
  )
}

// ─── Listing Card ────────────────────────────────────────────────────────────

function ListingCard({ listing, onPress }: { listing: SellwildListing; onPress: (l: SellwildListing) => void }) {
  const photo = listing.photos?.[0]
  const price = listing.price && !isNaN(Number(listing.price)) && Number(listing.price) > 0
    ? Number(listing.price).toLocaleString(undefined, { maximumFractionDigits: 0 })
    : null
  const symbol = currencyToSymbol(listing.currency)

  return (
    <TouchableOpacity style={s.card} onPress={() => onPress(listing)} activeOpacity={0.92}>
      <View style={s.imageWrap}>
        {photo?.url ? (
          <Image source={{ uri: photo.url }} style={s.image} resizeMode="cover" />
        ) : (
          <View style={[s.image, s.imagePlaceholder]}>
            <Text style={s.placeholderText}>No Image</Text>
          </View>
        )}
        {price && (
          <View style={s.priceBadge}>
            <Text style={s.priceText}>{symbol}{price}</Text>
          </View>
        )}
      </View>
      <View style={s.cardBody}>
        <Text style={s.cardTitle} numberOfLines={2}>{listing.title}</Text>
      </View>
    </TouchableOpacity>
  )
}

// ─── Native Screen ───────────────────────────────────────────────────────────

function NativeScreen() {
  const [config, setConfig] = useState<SellwildConfig | null>(null)

  // Fetch remote config from CDN on mount — merges CMS overrides over static defaults.
  // If the fetch fails (offline, timeout), falls back silently to static config.
  useEffect(() => {
    configure(STATIC_CONFIG.partnerCode!, REMOTE_SLUG, { timeout: 5000, overrides: STATIC_CONFIG })
      .then((cfg) => {
        // Passthrough verification: log every key that flows from CDN → widget.
        // Confirms unmapped bidders (MEDIANET, AMX, SOVRN, etc.) survive.
        const remoteKeys = cfg.remote ? Object.keys(cfg.remote).sort() : []
        console.log('[Sellwild] configure() resolved. remote passthrough keys:', remoteKeys)
        setConfig(cfg)
      })
  }, [])

  // On app foreground, clear cache so next init picks up CMS changes
  useEffect(() => {
    return () => { clearRemoteConfigCache() }
  }, [])

  const resolvedConfig = config ?? buildConfig(STATIC_CONFIG)
  const { listings, loading, error, refresh } = useSellwildListings(resolvedConfig)
  const [auctionResult, setAuctionResult] = useState<MultiAuctionResult>({ loading: true, auctionId: '', slots: [], totalTimeMs: 0, responseTimes: {} })

  const bannerAuction = auctionResult.slots.find(s => s.slotId === 'banner-top') || null
  const mrecAuction = auctionResult.slots.find(s => s.slotId === 'mrec-inline') || null
  const auctionsLoading = auctionResult.loading

  const runAuctions = useCallback(async () => {
    setAuctionResult(prev => ({ ...prev, loading: true }))
    const result = await runMultiSlotAuction()
    setAuctionResult(result)
  }, [])

  useEffect(() => { runAuctions() }, [])

  const handlePress = useCallback((listing: SellwildListing) => {
    if (listing.url) Linking.openURL(listing.url)
  }, [])

  if (error) {
    return (
      <View style={s.center}>
        <Text style={s.errorTitle}>Failed to load</Text>
        <TouchableOpacity style={s.retryBtn} onPress={refresh}>
          <Text style={s.retryText}>Try Again</Text>
        </TouchableOpacity>
      </View>
    )
  }

  return (
    <ScrollView style={s.flex} contentContainerStyle={s.scrollContent} showsVerticalScrollIndicator={false}>
      {/* Section: Marketplace */}
      <View style={s.sectionHeader}>
        <Text style={s.sectionTitle}>Marketplace</Text>
        <Text style={s.sectionSub}>{listings.length} listings near you</Text>
      </View>

      {/* Row 1 */}
      {listings.length >= 2 && (
        <View style={s.row}>
          <ListingCard listing={listings[0]} onPress={handlePress} />
          <ListingCard listing={listings[1]} onPress={handlePress} />
        </View>
      )}

      {/* Ad Slot 1: 320x50 banner */}
      <View style={a.adSlot}>
        <Text style={a.adSlotLabel}>SPONSORED</Text>
        {auctionsLoading ? (
          <View style={[a.filledAd, { backgroundColor: '#F1F5F9' }]}>
            <ActivityIndicator size="small" color="#94A3B8" />
          </View>
        ) : bannerAuction && bannerAuction.bids.length > 0 && isRenderable(bannerAuction.bids[0].adm) ? (
          <AdCreative adm={bannerAuction.bids[0].adm} width={320} height={50} />
        ) : bannerAuction && bannerAuction.bids.length > 0 ? (
          <WinnerAd bid={bannerAuction.bids[0]} size="320x50" />
        ) : (
          <HouseAd size="320x50" />
        )}
      </View>

      {/* Row 2 */}
      {listings.length >= 4 && (
        <View style={s.row}>
          <ListingCard listing={listings[2]} onPress={handlePress} />
          <ListingCard listing={listings[3]} onPress={handlePress} />
        </View>
      )}

      {/* Row 3 */}
      {listings.length >= 6 && (
        <View style={s.row}>
          <ListingCard listing={listings[4]} onPress={handlePress} />
          <ListingCard listing={listings[5]} onPress={handlePress} />
        </View>
      )}

      {/* Ad Slot 2: 300x250 MREC */}
      <View style={a.adSlot}>
        <Text style={a.adSlotLabel}>SPONSORED</Text>
        {auctionsLoading ? (
          <View style={[a.filledAd, { height: 250, width: 300, backgroundColor: '#F1F5F9' }]}>
            <ActivityIndicator size="small" color="#94A3B8" />
          </View>
        ) : mrecAuction && mrecAuction.bids.length > 0 && isRenderable(mrecAuction.bids[0].adm) ? (
          <AdCreative adm={mrecAuction.bids[0].adm} width={300} height={250} />
        ) : mrecAuction && mrecAuction.bids.length > 0 ? (
          <WinnerAd bid={mrecAuction.bids[0]} size="300x250" />
        ) : (
          <HouseAd size="300x250" />
        )}
      </View>

      {/* Row 4 */}
      {listings.length >= 8 && (
        <View style={s.row}>
          <ListingCard listing={listings[6]} onPress={handlePress} />
          <ListingCard listing={listings[7]} onPress={handlePress} />
        </View>
      )}

      {/* Auction Debug Panel */}
      {!auctionsLoading && bannerAuction && mrecAuction && (
        <AuctionPanel slots={[bannerAuction, mrecAuction]} auctionId={auctionResult.auctionId} onRefresh={runAuctions} />
      )}
      {auctionsLoading && (
        <View style={a.loadingPanel}>
          <ActivityIndicator color={ACCENT} />
          <Text style={a.loadingText}>Running Prebid auctions...</Text>
        </View>
      )}

      <View style={{ height: 40 }} />
    </ScrollView>
  )
}

// ─── Widget Screen ───────────────────────────────────────────────────────────

function WidgetScreen() {
  const [config, setConfig] = useState<PartialSellwildConfig>(STATIC_CONFIG)

  useEffect(() => {
    configure(STATIC_CONFIG.partnerCode!, REMOTE_SLUG, { timeout: 5000, overrides: STATIC_CONFIG })
      .then((cfg) => {
        const remoteKeys = cfg.remote ? Object.keys(cfg.remote).sort() : []
        console.log('[Sellwild] WidgetScreen configure() resolved. remote passthrough keys:', remoteKeys)
        setConfig(cfg)
      })
  }, [])

  return (
    <SellwildWidget
      config={config}
      style={s.flex}
      onListingPress={(listing: SellwildListing) => {
        if (listing.url) Linking.openURL(listing.url)
      }}
      onLoad={() => console.log('[Sellwild] Widget loaded')}
      onError={(err: Error) => console.error('[Sellwild] Error:', err.message)}
    />
  )
}

// ─── App ─────────────────────────────────────────────────────────────────────

type Tab = 'native' | 'widget'

export default function App() {
  const [tab, setTab] = useState<Tab>('native')
  return (
    <View style={s.root}>
      <StatusBar barStyle="light-content" />
      <SafeAreaView style={s.safeTop}>
        <View style={s.header}>
          <View>
            <Text style={s.headerTitle}>Sellwild</Text>
            <Text style={s.headerSub}>Powered by Prebid Server</Text>
          </View>
          <View style={s.headerBadge}><Text style={s.headerBadgeText}>S2S</Text></View>
        </View>
      </SafeAreaView>
      <View style={s.tabBar}>
        {(['native', 'widget'] as Tab[]).map(t => (
          <TouchableOpacity key={t} style={[s.tab, tab === t && s.tabActive]} onPress={() => setTab(t)}>
            <Text style={[s.tabLabel, tab === t && s.tabLabelActive]}>
              {t === 'native' ? 'Native + Auction' : 'Widget'}
            </Text>
          </TouchableOpacity>
        ))}
      </View>
      <View style={s.flex}>
        {tab === 'native' ? <NativeScreen /> : <WidgetScreen />}
      </View>
    </View>
  )
}

// ─── Styles ──────────────────────────────────────────────────────────────────

const ACCENT = '#2563EB'
const BG = '#F8FAFC'

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: BG },
  flex: { flex: 1 },
  safeTop: { backgroundColor: ACCENT },
  scrollContent: { paddingHorizontal: CARD_GAP },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingHorizontal: 20, paddingVertical: 14, backgroundColor: ACCENT },
  headerTitle: { color: '#fff', fontSize: 24, fontWeight: '800', letterSpacing: -0.5 },
  headerSub: { color: 'rgba(255,255,255,0.7)', fontSize: 12, marginTop: 2 },
  headerBadge: { backgroundColor: 'rgba(255,255,255,0.2)', paddingHorizontal: 10, paddingVertical: 4, borderRadius: 12 },
  headerBadgeText: { color: '#fff', fontSize: 11, fontWeight: '700', letterSpacing: 1 },
  tabBar: { flexDirection: 'row', backgroundColor: '#fff', borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: '#E2E8F0' },
  tab: { flex: 1, paddingVertical: 14, alignItems: 'center' as const },
  tabActive: { borderBottomWidth: 2.5, borderBottomColor: ACCENT },
  tabLabel: { fontSize: 15, color: '#94A3B8', fontWeight: '600' as const },
  tabLabelActive: { color: ACCENT },
  sectionHeader: { paddingTop: 16, paddingBottom: 12 },
  sectionTitle: { fontSize: 22, fontWeight: '700' as const, color: '#0F172A' },
  sectionSub: { fontSize: 13, color: '#94A3B8', marginTop: 2 },
  row: { flexDirection: 'row', justifyContent: 'space-between', marginBottom: CARD_GAP },
  card: { width: CARD_WIDTH, borderRadius: 14, backgroundColor: '#fff', shadowColor: '#000', shadowOffset: { width: 0, height: 4 }, shadowOpacity: 0.08, shadowRadius: 12, elevation: 4, overflow: 'hidden' },
  imageWrap: { width: '100%', aspectRatio: 4 / 3, backgroundColor: '#F1F5F9' },
  image: { width: '100%', height: '100%' },
  imagePlaceholder: { alignItems: 'center' as const, justifyContent: 'center' as const, backgroundColor: '#E2E8F0' },
  placeholderText: { color: '#94A3B8', fontSize: 12 },
  priceBadge: { position: 'absolute', bottom: 8, left: 8, backgroundColor: ACCENT, paddingHorizontal: 10, paddingVertical: 5, borderRadius: 8 },
  priceText: { color: '#fff', fontSize: 15, fontWeight: '700' as const },
  cardBody: { padding: 10 },
  cardTitle: { fontSize: 13, fontWeight: '600' as const, color: '#1E293B', lineHeight: 17 },
  center: { flex: 1, alignItems: 'center' as const, justifyContent: 'center' as const, padding: 32 },
  errorTitle: { fontSize: 17, fontWeight: '700' as const, color: '#0F172A' },
  retryBtn: { backgroundColor: ACCENT, paddingHorizontal: 28, paddingVertical: 12, borderRadius: 10, marginTop: 12 },
  retryText: { color: '#fff', fontWeight: '700' as const },
})

// ─── Auction + Ad Styles ─────────────────────────────────────────────────────

const a = StyleSheet.create({
  // Ad slots
  adSlot: { alignItems: 'center' as const, marginVertical: 12 },
  adSlotLabel: { fontSize: 10, fontWeight: '600' as const, color: '#CBD5E1', letterSpacing: 1, marginBottom: 6 },
  filledAd: { width: 320, height: 50, backgroundColor: '#DBEAFE', borderRadius: 10, alignItems: 'center' as const, justifyContent: 'center' as const, borderWidth: 1, borderColor: '#93C5FD' },
  filledAdText: { fontSize: 12, color: ACCENT, fontWeight: '600' as const },
  filledAdCpm: { fontSize: 18, color: ACCENT, fontWeight: '800' as const, marginTop: 4 },

  // House ads
  // House ads — WeatherBug branded (#6AB344 green, #4A90C4 blue, #3D5A73 dark teal)
  houseAd: { borderRadius: 12, overflow: 'hidden', backgroundColor: '#3D5A73' },
  houseAd300: { width: 300, height: 250 },
  houseAd320: { width: 320, height: 50 },
  houseAdInner: { flex: 1, padding: 16, justifyContent: 'center' as const },
  // 300x250 logo row
  houseLogoRow: { flexDirection: 'row', alignItems: 'center' as const, marginBottom: 10 },
  houseBugIcon: { fontSize: 22, marginRight: 6 },
  houseLogoText: { fontSize: 22, fontWeight: '700' as const, color: '#4A90C4' },
  houseLogoReg: { fontSize: 10, color: '#4A90C4', marginTop: -8 },
  houseAdHeadline: { color: '#fff', fontSize: 24, fontWeight: '800' as const, marginBottom: 6, lineHeight: 30 },
  houseAdBody: { color: 'rgba(255,255,255,0.65)', fontSize: 13, lineHeight: 19, marginBottom: 14 },
  houseAdCta: { backgroundColor: '#6AB344', paddingHorizontal: 22, paddingVertical: 10, borderRadius: 8, alignSelf: 'flex-start' as const },
  houseAdCtaText: { color: '#fff', fontSize: 14, fontWeight: '800' as const },
  houseAdPowered: { color: 'rgba(255,255,255,0.3)', fontSize: 9, marginTop: 10 },
  // 320x50 banner row
  houseBannerRow: { flexDirection: 'row', alignItems: 'center' as const, flex: 1 },
  houseBugSmall: { fontSize: 18, marginRight: 5 },
  houseBannerLogo: { fontSize: 15, fontWeight: '700' as const, color: '#4A90C4' },
  houseBannerDivider: { color: 'rgba(255,255,255,0.25)', marginHorizontal: 8, fontSize: 14 },
  houseBannerSub: { flex: 1, color: 'rgba(255,255,255,0.6)', fontSize: 11 },
  houseAdCtaSmall: { backgroundColor: '#6AB344', paddingHorizontal: 12, paddingVertical: 6, borderRadius: 6 },
  houseAdCtaSmallText: { color: '#fff', fontSize: 11, fontWeight: '800' as const },
  houseAdLabel: { position: 'absolute', top: 6, right: 6, backgroundColor: 'rgba(255,255,255,0.12)', paddingHorizontal: 5, paddingVertical: 1.5, borderRadius: 3 },
  houseAdLabelText: { color: 'rgba(255,255,255,0.4)', fontSize: 8, fontWeight: '700' as const, letterSpacing: 0.5 },

  // Winner ad (when creative isn't renderable HTML)
  winnerAd: { borderRadius: 12, overflow: 'hidden', backgroundColor: '#EFF6FF', borderWidth: 1, borderColor: '#BFDBFE' },
  winnerAd300: { width: 300, height: 250 },
  winnerAd320: { width: 320, height: 50 },
  winnerAdInner: { flex: 1, padding: 16, justifyContent: 'center' as const },
  winnerAdBidInfo: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' as const, marginBottom: 8 },
  winnerAdSeat: { fontSize: 12, fontWeight: '700' as const, color: ACCENT, textTransform: 'uppercase' as const, letterSpacing: 0.5 },
  winnerAdCpm: { fontSize: 20, fontWeight: '800' as const, color: '#16A34A' },
  winnerAdHeadline: { fontSize: 18, fontWeight: '700' as const, color: '#1E293B', marginBottom: 4 },
  winnerAdBody: { fontSize: 13, color: '#64748B', lineHeight: 18, marginBottom: 12 },
  winnerAdBodySmall: { fontSize: 11, color: '#64748B' },
  winnerAdBadge: { backgroundColor: ACCENT, paddingHorizontal: 10, paddingVertical: 6, borderRadius: 6, alignSelf: 'flex-start' as const },
  winnerAdBadgeText: { color: '#fff', fontSize: 11, fontWeight: '700' as const, letterSpacing: 0.5 },

  // Stats
  statsRow: { flexDirection: 'row', marginBottom: 16, gap: 8 },
  statBox: { flex: 1, backgroundColor: '#F8FAFC', borderRadius: 10, padding: 10, alignItems: 'center' as const },
  statValue: { fontSize: 18, fontWeight: '800' as const, color: '#0F172A' },
  statLabel: { fontSize: 10, fontWeight: '600' as const, color: '#94A3B8', marginTop: 2 },

  // Per-slot panel
  slotPanel: { backgroundColor: '#F8FAFC', borderRadius: 12, padding: 12, marginBottom: 10 },
  slotPanelHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' as const, marginBottom: 8 },
  slotPanelSize: { fontSize: 14, fontWeight: '700' as const, color: '#0F172A' },
  slotPanelTime: { fontSize: 12, color: '#94A3B8' },

  // Auction panel
  panel: { backgroundColor: '#fff', borderRadius: 16, padding: 16, marginTop: 16, shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, shadowOpacity: 0.06, shadowRadius: 8 },
  panelHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' as const, marginBottom: 4 },
  panelTitle: { fontSize: 16, fontWeight: '700' as const, color: '#0F172A' },
  refreshBtn: { backgroundColor: '#F1F5F9', paddingHorizontal: 12, paddingVertical: 6, borderRadius: 8 },
  refreshText: { fontSize: 12, fontWeight: '600' as const, color: ACCENT },
  panelEndpoint: { fontSize: 11, color: '#94A3B8', fontFamily: 'Courier', marginBottom: 1 },
  panelNote: { fontSize: 11, color: '#94A3B8', marginBottom: 12 },
  panelTime: { fontSize: 12, color: '#64748B', marginBottom: 12 },
  bidderList: { marginBottom: 12 },
  bidderRow: { flexDirection: 'row', alignItems: 'center' as const, paddingVertical: 6, borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: '#F1F5F9' },
  statusDot: { width: 8, height: 8, borderRadius: 4, marginRight: 8 },
  dotGreen: { backgroundColor: '#22C55E' },
  dotRed: { backgroundColor: '#EF4444' },
  dotGrey: { backgroundColor: '#CBD5E1' },
  bidderName: { flex: 1, fontSize: 13, fontWeight: '600' as const, color: '#334155' },
  bidderMs: { fontSize: 12, color: '#94A3B8', marginRight: 8, width: 50, textAlign: 'right' as const },
  bidPrice: { fontSize: 13, fontWeight: '700' as const, color: '#22C55E', width: 60, textAlign: 'right' as const },
  bidNone: { fontSize: 12, color: '#CBD5E1', width: 60, textAlign: 'right' as const },
  dashboardLinkRow: { flexDirection: 'row' as const, alignItems: 'center' as const, backgroundColor: '#F1F5F9', borderRadius: 8, padding: 8, marginBottom: 12, gap: 8 },
  dashboardLinkUrl: { flex: 1, fontSize: 11, color: '#475569', fontFamily: 'Courier' },
  copyBtn: { backgroundColor: '#3B82F6', borderRadius: 6, paddingHorizontal: 12, paddingVertical: 6 },
  copyBtnText: { fontSize: 12, fontWeight: '600' as const, color: '#fff' },
  nofillBox: { backgroundColor: '#FEF3C7', borderRadius: 10, padding: 12, marginBottom: 8 },
  nofillTitle: { fontSize: 13, fontWeight: '700' as const, color: '#92400E', marginBottom: 2 },
  nofillBody: { fontSize: 12, color: '#A16207', lineHeight: 17 },
  winBox: { backgroundColor: '#DCFCE7', borderRadius: 10, padding: 12 },
  winTitle: { fontSize: 13, fontWeight: '700' as const, color: '#166534', marginBottom: 2 },
  winDetail: { fontSize: 12, color: '#15803D' },
  loadingPanel: { flexDirection: 'row', alignItems: 'center' as const, justifyContent: 'center' as const, padding: 20 },
  loadingText: { marginLeft: 8, fontSize: 13, color: '#94A3B8' },
})
