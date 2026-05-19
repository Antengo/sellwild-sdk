import { useCurrentFrame, useVideoConfig, interpolate, spring } from 'remotion'
import { baseStyle, badge, heading, subheading, BG_CARD, TEXT, TEXT_DIM, RED, BORDER, ACCENT } from './theme'

const sdks = [
  'AppNexus', 'PubMatic', 'Index Exchange', 'Rubicon', 'OpenX',
  'TripleLift', 'Sharethrough', 'InMobi', 'Smaato', 'Yieldmo',
  'Taboola', 'Media.net', 'Sovrn', 'Unruly', 'LoopMe', 'Nativo',
]

export const ProblemSlide = () => {
  const frame = useCurrentFrame()
  const { fps } = useVideoConfig()

  const badgeOpacity = interpolate(frame, [0, 15], [0, 1], { extrapolateRight: 'clamp' })

  const headingOpacity = interpolate(frame, [10, 25], [0, 1], { extrapolateRight: 'clamp' })
  const headingY = interpolate(
    spring({ frame: Math.max(0, frame - 10), fps, config: { damping: 14 } }),
    [0, 1],
    [30, 0],
  )

  const redXOpacity = interpolate(frame, [140, 160], [0, 1], { extrapolateRight: 'clamp' })
  const redXScale = interpolate(
    spring({ frame: Math.max(0, frame - 140), fps, config: { damping: 10, stiffness: 120 } }),
    [0, 1],
    [2, 1],
  )

  const subOpacity = interpolate(frame, [170, 190], [0, 1], { extrapolateRight: 'clamp' })

  return (
    <div style={baseStyle}>
      <div style={{ ...badge, opacity: badgeOpacity }}>THE PROBLEM</div>

      <div
        style={{
          ...heading,
          fontSize: 56,
          opacity: headingOpacity,
          transform: `translateY(${headingY}px)`,
          marginBottom: 40,
        }}
      >
        You're managing 40+ SDK integrations.
      </div>

      <div
        style={{
          display: 'flex',
          flexWrap: 'wrap',
          gap: 10,
          justifyContent: 'center',
          maxWidth: 900,
          position: 'relative',
        }}
      >
        {sdks.map((name, i) => {
          const delay = 30 + i * 6
          const chipOpacity = interpolate(frame, [delay, delay + 10], [0, 1], {
            extrapolateRight: 'clamp',
          })
          const chipScale = interpolate(
            spring({
              frame: Math.max(0, frame - delay),
              fps,
              config: { damping: 12, stiffness: 100 },
            }),
            [0, 1],
            [0.7, 1],
          )
          return (
            <div
              key={name}
              style={{
                padding: '8px 18px',
                background: BG_CARD,
                border: `1px solid ${BORDER}`,
                borderRadius: 8,
                fontSize: 16,
                fontWeight: 600,
                color: TEXT_DIM,
                opacity: chipOpacity,
                transform: `scale(${chipScale})`,
              }}
            >
              {name}
            </div>
          )
        })}

        {/* Red X overlay */}
        <div
          style={{
            position: 'absolute',
            top: '50%',
            left: '50%',
            transform: `translate(-50%, -50%) scale(${redXScale})`,
            opacity: redXOpacity,
            fontSize: 120,
            fontWeight: 900,
            color: RED,
            lineHeight: 1,
            textShadow: `0 0 40px ${RED}`,
          }}
        >
          ✕
        </div>
      </div>

      <div style={{ ...subheading, fontSize: 28, opacity: subOpacity, marginTop: 32 }}>
        Each one adds latency, crashes, and complexity.
      </div>
    </div>
  )
}
