import { useCurrentFrame, useVideoConfig, interpolate, spring } from 'remotion'
import { FONT, BG, TEXT, TEXT_DIM, ACCENT, baseStyle } from './theme'

export const ClosingSlide = () => {
  const frame = useCurrentFrame()
  const { fps } = useVideoConfig()

  const headingOpacity = interpolate(frame, [0, 20], [0, 1], { extrapolateRight: 'clamp' })
  const headingY = interpolate(
    spring({ frame, fps, config: { damping: 12, stiffness: 60 } }),
    [0, 1],
    [60, 0],
  )

  const lineWidth = interpolate(
    spring({ frame: Math.max(0, frame - 20), fps, config: { damping: 12, stiffness: 60 } }),
    [0, 1],
    [0, 300],
  )

  const emailOpacity = interpolate(frame, [30, 50], [0, 1], { extrapolateRight: 'clamp' })
  const emailY = interpolate(
    spring({ frame: Math.max(0, frame - 30), fps, config: { damping: 14 } }),
    [0, 1],
    [30, 0],
  )

  const urlOpacity = interpolate(frame, [45, 60], [0, 1], { extrapolateRight: 'clamp' })

  return (
    <div style={baseStyle}>
      <div
        style={{
          fontSize: 96,
          fontWeight: 800,
          letterSpacing: -3,
          color: TEXT,
          fontFamily: FONT,
          opacity: headingOpacity,
          transform: `translateY(${headingY}px)`,
        }}
      >
        Let's Go.
      </div>

      <div
        style={{
          width: lineWidth,
          height: 4,
          background: `linear-gradient(90deg, ${ACCENT}, #7C3AED)`,
          borderRadius: 2,
          marginTop: 32,
          marginBottom: 32,
        }}
      />

      <div
        style={{
          fontSize: 32,
          fontWeight: 600,
          color: ACCENT,
          opacity: emailOpacity,
          transform: `translateY(${emailY}px)`,
          fontFamily: FONT,
          marginBottom: 12,
        }}
      >
        sdk@sellwild.com
      </div>

      <div
        style={{
          fontSize: 22,
          fontWeight: 500,
          color: TEXT_DIM,
          opacity: urlOpacity,
          fontFamily: FONT,
          letterSpacing: 1,
        }}
      >
        sdk.sellwild.com
      </div>
    </div>
  )
}
