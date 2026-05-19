import { useCurrentFrame, useVideoConfig, interpolate, spring } from 'remotion'
import { baseStyle, badge, BG_CARD, TEXT, TEXT_DIM, ACCENT, BORDER, GREEN, RED } from './theme'

interface Bidder {
  name: string
  time: string
  result: string
  price: string | null
  status: 'win' | 'error' | 'nobid'
}

const bidders: Bidder[] = [
  { name: 'appnexus', time: '27ms', result: 'no bid', price: null, status: 'nobid' },
  { name: 'pubmatic', time: '9ms', result: '$15.00', price: '$15.00', status: 'win' },
  { name: 'rubicon', time: '4ms', result: 'error', price: null, status: 'error' },
  { name: 'ix', time: '1ms', result: 'error', price: null, status: 'error' },
]

export const AuctionSlide = () => {
  const frame = useCurrentFrame()
  const { fps } = useVideoConfig()

  const badgeOpacity = interpolate(frame, [0, 15], [0, 1], { extrapolateRight: 'clamp' })

  const panelOpacity = interpolate(frame, [10, 25], [0, 1], { extrapolateRight: 'clamp' })
  const panelScale = interpolate(
    spring({ frame: Math.max(0, frame - 10), fps, config: { damping: 14 } }),
    [0, 1],
    [0.95, 1],
  )

  const winnerDelay = 140
  const winnerOpacity = interpolate(frame, [winnerDelay, winnerDelay + 20], [0, 1], {
    extrapolateRight: 'clamp',
  })
  const winnerY = interpolate(
    spring({ frame: Math.max(0, frame - winnerDelay), fps, config: { damping: 12 } }),
    [0, 1],
    [20, 0],
  )

  const statusColor = (status: string) => {
    if (status === 'win') return GREEN
    if (status === 'error') return RED
    return TEXT_DIM
  }

  return (
    <div style={baseStyle}>
      <div style={{ ...badge, opacity: badgeOpacity }}>LIVE AUCTION</div>

      <div
        style={{
          background: BG_CARD,
          border: `1px solid ${BORDER}`,
          borderRadius: 16,
          padding: '32px 48px',
          minWidth: 700,
          opacity: panelOpacity,
          transform: `scale(${panelScale})`,
        }}
      >
        {/* Header */}
        <div
          style={{
            display: 'flex',
            justifyContent: 'space-between',
            borderBottom: `1px solid ${BORDER}`,
            paddingBottom: 16,
            marginBottom: 16,
            fontSize: 14,
            fontWeight: 700,
            color: TEXT_DIM,
            letterSpacing: 1,
            textTransform: 'uppercase' as const,
          }}
        >
          <span style={{ flex: 2 }}>Bidder</span>
          <span style={{ flex: 1, textAlign: 'center' as const }}>Time</span>
          <span style={{ flex: 1, textAlign: 'right' as const }}>Result</span>
        </div>

        {/* Bidders */}
        {bidders.map((bidder, i) => {
          const delay = 35 + i * 25
          const rowOpacity = interpolate(frame, [delay, delay + 15], [0, 1], {
            extrapolateRight: 'clamp',
          })
          const rowX = interpolate(
            spring({
              frame: Math.max(0, frame - delay),
              fps,
              config: { damping: 14, stiffness: 100 },
            }),
            [0, 1],
            [-30, 0],
          )
          return (
            <div
              key={bidder.name}
              style={{
                display: 'flex',
                justifyContent: 'space-between',
                alignItems: 'center',
                padding: '12px 0',
                borderBottom: i < bidders.length - 1 ? `1px solid ${BORDER}` : 'none',
                opacity: rowOpacity,
                transform: `translateX(${rowX}px)`,
              }}
            >
              <span style={{ flex: 2, fontSize: 20, fontWeight: 600, color: TEXT }}>
                {bidder.name}
              </span>
              <span
                style={{ flex: 1, textAlign: 'center' as const, fontSize: 18, color: TEXT_DIM }}
              >
                {bidder.time}
              </span>
              <span
                style={{
                  flex: 1,
                  textAlign: 'right' as const,
                  fontSize: 20,
                  fontWeight: 700,
                  color: statusColor(bidder.status),
                }}
              >
                {bidder.result}
              </span>
            </div>
          )
        })}
      </div>

      {/* Winner banner */}
      <div
        style={{
          marginTop: 32,
          padding: '16px 40px',
          background: `${GREEN}15`,
          border: `2px solid ${GREEN}`,
          borderRadius: 12,
          fontSize: 24,
          fontWeight: 700,
          color: GREEN,
          opacity: winnerOpacity,
          transform: `translateY(${winnerY}px)`,
        }}
      >
        Winner: pubmatic — $15.00 CPM
      </div>
    </div>
  )
}
