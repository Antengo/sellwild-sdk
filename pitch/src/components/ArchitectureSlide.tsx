import { useCurrentFrame, useVideoConfig, interpolate, spring } from 'remotion'
import { baseStyle, badge, BG_CARD, TEXT, TEXT_DIM, ACCENT, BORDER, GREEN } from './theme'

const ssps = ['AppNexus', 'PubMatic', 'Magnite', 'IX', 'OpenX', 'TripleLift']

export const ArchitectureSlide = () => {
  const frame = useCurrentFrame()
  const { fps } = useVideoConfig()

  const badgeOpacity = interpolate(frame, [0, 15], [0, 1], { extrapolateRight: 'clamp' })

  const makeSpring = (delay: number) =>
    spring({ frame: Math.max(0, frame - delay), fps, config: { damping: 14, stiffness: 80 } })

  const box1X = interpolate(makeSpring(10), [0, 1], [-200, 0])
  const box1Opacity = interpolate(frame, [10, 25], [0, 1], { extrapolateRight: 'clamp' })

  const arrow1Opacity = interpolate(frame, [30, 45], [0, 1], { extrapolateRight: 'clamp' })
  const arrow1Width = interpolate(makeSpring(30), [0, 1], [0, 80])

  const box2X = interpolate(makeSpring(40), [0, 1], [-100, 0])
  const box2Opacity = interpolate(frame, [40, 55], [0, 1], { extrapolateRight: 'clamp' })

  const arrow2Opacity = interpolate(frame, [55, 70], [0, 1], { extrapolateRight: 'clamp' })
  const arrow2Width = interpolate(makeSpring(55), [0, 1], [0, 80])

  const box3X = interpolate(makeSpring(65), [0, 1], [-100, 0])
  const box3Opacity = interpolate(frame, [65, 80], [0, 1], { extrapolateRight: 'clamp' })

  const boxStyle: React.CSSProperties = {
    background: BG_CARD,
    border: `2px solid ${BORDER}`,
    borderRadius: 12,
    padding: '24px 32px',
    fontSize: 22,
    fontWeight: 700,
    color: TEXT,
    textAlign: 'center' as const,
  }

  const arrowStyle = (opacity: number, width: number): React.CSSProperties => ({
    height: 3,
    width,
    background: ACCENT,
    opacity,
    position: 'relative' as const,
    display: 'flex',
    alignItems: 'center',
  })

  return (
    <div style={baseStyle}>
      <div style={{ ...badge, opacity: badgeOpacity }}>HOW IT WORKS</div>

      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: 0,
          marginTop: 40,
          marginBottom: 60,
        }}
      >
        {/* Your App */}
        <div
          style={{
            ...boxStyle,
            opacity: box1Opacity,
            transform: `translateX(${box1X}px)`,
            borderColor: BORDER,
          }}
        >
          Your App
        </div>

        {/* Arrow 1 */}
        <div style={{ opacity: arrow1Opacity, display: 'flex', alignItems: 'center' }}>
          <div style={{ width: arrow1Width, height: 3, background: ACCENT }} />
          <div
            style={{
              width: 0,
              height: 0,
              borderTop: '8px solid transparent',
              borderBottom: '8px solid transparent',
              borderLeft: `12px solid ${ACCENT}`,
            }}
          />
        </div>

        {/* Sellwild SDK */}
        <div
          style={{
            ...boxStyle,
            opacity: box2Opacity,
            transform: `translateX(${box2X}px)`,
            borderColor: ACCENT,
            boxShadow: `0 0 30px ${ACCENT}33`,
          }}
        >
          Sellwild SDK
        </div>

        {/* Arrow 2 */}
        <div style={{ opacity: arrow2Opacity, display: 'flex', alignItems: 'center' }}>
          <div style={{ width: arrow2Width, height: 3, background: ACCENT }} />
          <div
            style={{
              width: 0,
              height: 0,
              borderTop: '8px solid transparent',
              borderBottom: '8px solid transparent',
              borderLeft: `12px solid ${ACCENT}`,
            }}
          />
        </div>

        {/* Prebid Server */}
        <div
          style={{
            ...boxStyle,
            opacity: box3Opacity,
            transform: `translateX(${box3X}px)`,
            borderColor: GREEN,
          }}
        >
          Prebid Server
        </div>
      </div>

      {/* SSP fan-out */}
      <div
        style={{
          display: 'flex',
          flexWrap: 'wrap',
          gap: 12,
          justifyContent: 'center',
          maxWidth: 700,
        }}
      >
        {ssps.map((ssp, i) => {
          const delay = 85 + i * 8
          const chipOpacity = interpolate(frame, [delay, delay + 12], [0, 1], {
            extrapolateRight: 'clamp',
          })
          const chipY = interpolate(
            spring({
              frame: Math.max(0, frame - delay),
              fps,
              config: { damping: 12, stiffness: 100 },
            }),
            [0, 1],
            [20, 0],
          )
          return (
            <div
              key={ssp}
              style={{
                padding: '10px 20px',
                background: BG_CARD,
                border: `1px solid ${BORDER}`,
                borderRadius: 8,
                fontSize: 16,
                fontWeight: 600,
                color: GREEN,
                opacity: chipOpacity,
                transform: `translateY(${chipY}px)`,
              }}
            >
              {ssp}
            </div>
          )
        })}
      </div>
    </div>
  )
}
