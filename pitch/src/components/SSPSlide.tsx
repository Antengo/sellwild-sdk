import { useCurrentFrame, useVideoConfig, interpolate, spring } from 'remotion'
import { baseStyle, badge, heading, subheading, BG_CARD, TEXT, BORDER, GREEN } from './theme'

const ssps = [
  'AppNexus', 'PubMatic', 'Magnite', 'Index Exchange',
  'OpenX', 'TripleLift', 'Sharethrough', 'InMobi',
  'Smaato', 'Yieldmo', 'Taboola', 'Media.net',
  'Sovrn', 'Unruly', 'LoopMe', 'Nativo',
]

export const SSPSlide = () => {
  const frame = useCurrentFrame()
  const { fps } = useVideoConfig()

  const badgeOpacity = interpolate(frame, [0, 15], [0, 1], { extrapolateRight: 'clamp' })

  const headingOpacity = interpolate(frame, [10, 25], [0, 1], { extrapolateRight: 'clamp' })
  const headingY = interpolate(
    spring({ frame: Math.max(0, frame - 10), fps, config: { damping: 14 } }),
    [0, 1],
    [30, 0],
  )

  const subOpacity = interpolate(frame, [140, 160], [0, 1], { extrapolateRight: 'clamp' })

  return (
    <div style={baseStyle}>
      <div style={{ ...badge, opacity: badgeOpacity }}>YOUR DEMAND PARTNERS</div>

      <div
        style={{
          ...heading,
          fontSize: 56,
          opacity: headingOpacity,
          transform: `translateY(${headingY}px)`,
          marginBottom: 48,
        }}
      >
        400+ SSP Adapters
      </div>

      <div
        style={{
          display: 'flex',
          flexWrap: 'wrap',
          gap: 12,
          justifyContent: 'center',
          maxWidth: 900,
        }}
      >
        {ssps.map((name, i) => {
          const delay = 30 + i * 5
          const chipOpacity = interpolate(frame, [delay, delay + 12], [0, 1], {
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
                display: 'flex',
                alignItems: 'center',
                gap: 8,
                padding: '10px 20px',
                background: BG_CARD,
                border: `1px solid ${BORDER}`,
                borderRadius: 8,
                fontSize: 16,
                fontWeight: 600,
                color: TEXT,
                opacity: chipOpacity,
                transform: `scale(${chipScale})`,
              }}
            >
              <div
                style={{
                  width: 8,
                  height: 8,
                  borderRadius: '50%',
                  background: GREEN,
                  boxShadow: `0 0 6px ${GREEN}`,
                }}
              />
              {name}
            </div>
          )
        })}
      </div>

      <div style={{ ...subheading, fontSize: 26, opacity: subOpacity, marginTop: 40 }}>
        Every SSP in your app-ads.txt. Day one.
      </div>
    </div>
  )
}
