import { useCurrentFrame, useVideoConfig, interpolate, spring } from 'remotion'
import { baseStyle, badge, BG_CARD, TEXT, TEXT_DIM, ACCENT, BORDER, GREEN, RED } from './theme'

const rows = [
  { label: 'Integration', left: '40 SDKs', right: '1 SDK' },
  { label: 'Latency', left: '2-5s', right: '<200ms' },
  { label: 'App Size', left: '+80MB', right: '+2MB' },
  { label: 'Updates', left: 'App Store', right: 'Server config' },
  { label: 'Reporting', left: 'Fragmented', right: 'Unified' },
]

export const ComparisonSlide = () => {
  const frame = useCurrentFrame()
  const { fps } = useVideoConfig()

  const badgeOpacity = interpolate(frame, [0, 15], [0, 1], { extrapolateRight: 'clamp' })

  const headerOpacity = interpolate(frame, [10, 25], [0, 1], { extrapolateRight: 'clamp' })

  const cellStyle: React.CSSProperties = {
    padding: '16px 24px',
    fontSize: 20,
    fontWeight: 600,
    textAlign: 'center' as const,
  }

  return (
    <div style={baseStyle}>
      <div style={{ ...badge, opacity: badgeOpacity }}>SIDE BY SIDE</div>

      <div
        style={{
          background: BG_CARD,
          border: `1px solid ${BORDER}`,
          borderRadius: 16,
          overflow: 'hidden',
          minWidth: 800,
          opacity: headerOpacity,
        }}
      >
        {/* Header */}
        <div style={{ display: 'flex' }}>
          <div
            style={{
              ...cellStyle,
              flex: 1,
              fontSize: 14,
              fontWeight: 700,
              color: TEXT_DIM,
              letterSpacing: 1,
              textTransform: 'uppercase' as const,
            }}
          />
          <div
            style={{
              ...cellStyle,
              flex: 1,
              fontSize: 16,
              fontWeight: 700,
              color: RED,
              letterSpacing: 1,
              background: `${RED}08`,
            }}
          >
            Client-Side
          </div>
          <div
            style={{
              ...cellStyle,
              flex: 1,
              fontSize: 16,
              fontWeight: 700,
              color: GREEN,
              letterSpacing: 1,
              background: `${GREEN}08`,
            }}
          >
            Sellwild
          </div>
        </div>

        {/* Rows */}
        {rows.map((row, i) => {
          const delay = 30 + i * 18
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
            [-20, 0],
          )
          return (
            <div
              key={row.label}
              style={{
                display: 'flex',
                borderTop: `1px solid ${BORDER}`,
                opacity: rowOpacity,
                transform: `translateX(${rowX}px)`,
              }}
            >
              <div
                style={{
                  ...cellStyle,
                  flex: 1,
                  color: TEXT_DIM,
                  fontWeight: 500,
                  textAlign: 'left' as const,
                }}
              >
                {row.label}
              </div>
              <div
                style={{
                  ...cellStyle,
                  flex: 1,
                  color: RED,
                  background: `${RED}08`,
                }}
              >
                {row.left}
              </div>
              <div
                style={{
                  ...cellStyle,
                  flex: 1,
                  color: GREEN,
                  background: `${GREEN}08`,
                }}
              >
                {row.right}
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}
