import { useCurrentFrame, useVideoConfig, interpolate, spring } from 'remotion'
import { baseStyle, badge, heading, BG_CARD, TEXT, TEXT_DIM, ACCENT, BORDER, GREEN } from './theme'

const stats = [
  { value: '1 SDK', label: 'Replacing 40+', color: ACCENT },
  { value: '<200ms', label: 'Auction time', color: GREEN },
  { value: '+2MB', label: 'App size', color: ACCENT },
]

export const SolutionSlide = () => {
  const frame = useCurrentFrame()
  const { fps } = useVideoConfig()

  const badgeOpacity = interpolate(frame, [0, 15], [0, 1], { extrapolateRight: 'clamp' })

  const headingOpacity = interpolate(frame, [10, 25], [0, 1], { extrapolateRight: 'clamp' })
  const headingY = interpolate(
    spring({ frame: Math.max(0, frame - 10), fps, config: { damping: 14 } }),
    [0, 1],
    [30, 0],
  )

  return (
    <div style={baseStyle}>
      <div style={{ ...badge, opacity: badgeOpacity }}>THE SOLUTION</div>

      <div
        style={{
          ...heading,
          fontSize: 60,
          opacity: headingOpacity,
          transform: `translateY(${headingY}px)`,
          marginBottom: 60,
        }}
      >
        One SDK. All your demand.
      </div>

      <div style={{ display: 'flex', gap: 32 }}>
        {stats.map((stat, i) => {
          const delay = 30 + i * 20
          const cardOpacity = interpolate(frame, [delay, delay + 20], [0, 1], {
            extrapolateRight: 'clamp',
          })
          const cardY = interpolate(
            spring({
              frame: Math.max(0, frame - delay),
              fps,
              config: { damping: 12, stiffness: 80 },
            }),
            [0, 1],
            [50, 0],
          )
          return (
            <div
              key={stat.value}
              style={{
                background: BG_CARD,
                border: `1px solid ${BORDER}`,
                borderRadius: 16,
                padding: '48px 56px',
                textAlign: 'center' as const,
                opacity: cardOpacity,
                transform: `translateY(${cardY}px)`,
                minWidth: 220,
              }}
            >
              <div
                style={{
                  fontSize: 52,
                  fontWeight: 800,
                  color: stat.color,
                  letterSpacing: -1,
                  marginBottom: 12,
                }}
              >
                {stat.value}
              </div>
              <div style={{ fontSize: 18, color: TEXT_DIM, fontWeight: 500 }}>
                {stat.label}
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}
