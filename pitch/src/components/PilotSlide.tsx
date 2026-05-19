import { useCurrentFrame, useVideoConfig, interpolate, spring } from 'remotion'
import { baseStyle, badge, heading, subheading, BG_CARD, TEXT, TEXT_DIM, ACCENT, BORDER, GREEN } from './theme'

const steps = [
  { num: '1', text: 'Give us your SSP seat IDs' },
  { num: '2', text: 'We configure your Prebid Server' },
  { num: '3', text: 'Run on 5% of traffic, compare CPMs' },
]

export const PilotSlide = () => {
  const frame = useCurrentFrame()
  const { fps } = useVideoConfig()

  const badgeOpacity = interpolate(frame, [0, 15], [0, 1], { extrapolateRight: 'clamp' })

  const headingOpacity = interpolate(frame, [10, 25], [0, 1], { extrapolateRight: 'clamp' })
  const headingY = interpolate(
    spring({ frame: Math.max(0, frame - 10), fps, config: { damping: 14 } }),
    [0, 1],
    [30, 0],
  )

  const subOpacity = interpolate(frame, [160, 180], [0, 1], { extrapolateRight: 'clamp' })

  return (
    <div style={baseStyle}>
      <div style={{ ...badge, opacity: badgeOpacity }}>ZERO RISK</div>

      <div
        style={{
          ...heading,
          fontSize: 60,
          opacity: headingOpacity,
          transform: `translateY(${headingY}px)`,
          marginBottom: 52,
        }}
      >
        30-Day Pilot
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 20, maxWidth: 700 }}>
        {steps.map((step, i) => {
          const delay = 40 + i * 30
          const stepOpacity = interpolate(frame, [delay, delay + 20], [0, 1], {
            extrapolateRight: 'clamp',
          })
          const stepX = interpolate(
            spring({
              frame: Math.max(0, frame - delay),
              fps,
              config: { damping: 14, stiffness: 80 },
            }),
            [0, 1],
            [-60, 0],
          )

          // Arrow between steps
          const arrowDelay = delay + 20
          const arrowOpacity =
            i < steps.length - 1
              ? interpolate(frame, [arrowDelay, arrowDelay + 10], [0, 1], {
                  extrapolateRight: 'clamp',
                })
              : 0

          return (
            <div key={step.num}>
              <div
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: 24,
                  background: BG_CARD,
                  border: `1px solid ${BORDER}`,
                  borderRadius: 12,
                  padding: '24px 32px',
                  opacity: stepOpacity,
                  transform: `translateX(${stepX}px)`,
                }}
              >
                <div
                  style={{
                    width: 48,
                    height: 48,
                    borderRadius: '50%',
                    background: ACCENT,
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    fontSize: 22,
                    fontWeight: 800,
                    color: TEXT,
                    flexShrink: 0,
                  }}
                >
                  {step.num}
                </div>
                <div style={{ fontSize: 24, fontWeight: 600, color: TEXT }}>
                  {step.text}
                </div>
              </div>
              {i < steps.length - 1 && (
                <div
                  style={{
                    display: 'flex',
                    justifyContent: 'center',
                    opacity: arrowOpacity,
                    padding: '4px 0',
                  }}
                >
                  <div
                    style={{
                      width: 2,
                      height: 16,
                      background: ACCENT,
                    }}
                  />
                </div>
              )}
            </div>
          )
        })}
      </div>

      <div style={{ ...subheading, fontSize: 24, opacity: subOpacity, marginTop: 40 }}>
        If we don't match your current yield, you walk.
      </div>
    </div>
  )
}
