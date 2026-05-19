import { useCurrentFrame, useVideoConfig, interpolate, spring } from 'remotion'
import { baseStyle, badge, subheading, BG_CARD, TEXT, TEXT_DIM, ACCENT, BORDER, GREEN } from './theme'

const stats = [
  { value: '15M', label: 'MAU' },
  { value: '$10', label: 'eCPM' },
  { value: '100%', label: 'Fill with house ads' },
]

export const RevenueSlide = () => {
  const frame = useCurrentFrame()
  const { fps } = useVideoConfig()

  const badgeOpacity = interpolate(frame, [0, 15], [0, 1], { extrapolateRight: 'clamp' })

  // Animated counter for $10M
  const counterProgress = interpolate(frame, [20, 80], [0, 10000000], {
    extrapolateRight: 'clamp',
  })
  const counterOpacity = interpolate(frame, [15, 30], [0, 1], { extrapolateRight: 'clamp' })
  const counterScale = interpolate(
    spring({ frame: Math.max(0, frame - 15), fps, config: { damping: 10, stiffness: 60 } }),
    [0, 1],
    [0.8, 1],
  )

  const displayValue =
    frame >= 80
      ? '$10M'
      : `$${Math.floor(counterProgress).toLocaleString()}`

  const subtitleOpacity = interpolate(frame, [85, 100], [0, 1], { extrapolateRight: 'clamp' })

  return (
    <div style={baseStyle}>
      <div style={{ ...badge, opacity: badgeOpacity }}>THE OPPORTUNITY</div>

      <div
        style={{
          fontSize: 120,
          fontWeight: 800,
          color: GREEN,
          letterSpacing: -4,
          opacity: counterOpacity,
          transform: `scale(${counterScale})`,
          marginBottom: 8,
        }}
      >
        {displayValue}
      </div>

      <div
        style={{
          ...subheading,
          fontSize: 28,
          opacity: subtitleOpacity,
          marginBottom: 60,
        }}
      >
        Annual revenue opportunity
      </div>

      <div style={{ display: 'flex', gap: 40 }}>
        {stats.map((stat, i) => {
          const delay = 100 + i * 18
          const cardOpacity = interpolate(frame, [delay, delay + 18], [0, 1], {
            extrapolateRight: 'clamp',
          })
          const cardY = interpolate(
            spring({
              frame: Math.max(0, frame - delay),
              fps,
              config: { damping: 12, stiffness: 80 },
            }),
            [0, 1],
            [40, 0],
          )
          return (
            <div
              key={stat.label}
              style={{
                background: BG_CARD,
                border: `1px solid ${BORDER}`,
                borderRadius: 12,
                padding: '28px 40px',
                textAlign: 'center' as const,
                opacity: cardOpacity,
                transform: `translateY(${cardY}px)`,
              }}
            >
              <div
                style={{
                  fontSize: 36,
                  fontWeight: 800,
                  color: ACCENT,
                  marginBottom: 8,
                }}
              >
                {stat.value}
              </div>
              <div style={{ fontSize: 16, color: TEXT_DIM, fontWeight: 500 }}>
                {stat.label}
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}
