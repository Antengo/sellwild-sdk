import { useCurrentFrame, useVideoConfig, interpolate, spring } from 'remotion'
import { FONT, BG, TEXT, TEXT_DIM, ACCENT, baseStyle } from './theme'

export const TitleSlide = () => {
  const frame = useCurrentFrame()
  const { fps } = useVideoConfig()

  const titleY = interpolate(
    spring({ frame, fps, config: { damping: 14, stiffness: 80 } }),
    [0, 1],
    [60, 0],
  )
  const titleOpacity = interpolate(frame, [0, 20], [0, 1], { extrapolateRight: 'clamp' })

  const subtitleOpacity = interpolate(frame, [15, 35], [0, 1], { extrapolateRight: 'clamp' })
  const subtitleY = interpolate(
    spring({ frame: Math.max(0, frame - 15), fps, config: { damping: 14, stiffness: 80 } }),
    [0, 1],
    [40, 0],
  )

  const lineWidth = interpolate(
    spring({ frame: Math.max(0, frame - 25), fps, config: { damping: 12, stiffness: 60 } }),
    [0, 1],
    [0, 400],
  )

  const urlOpacity = interpolate(frame, [40, 55], [0, 1], { extrapolateRight: 'clamp' })

  return (
    <div style={baseStyle}>
      <div
        style={{
          fontSize: 96,
          fontWeight: 800,
          letterSpacing: -3,
          fontFamily: FONT,
          color: TEXT,
          transform: `translateY(${titleY}px)`,
          opacity: titleOpacity,
        }}
      >
        Sellwild SDK
      </div>

      <div
        style={{
          width: lineWidth,
          height: 4,
          background: `linear-gradient(90deg, ${ACCENT}, #7C3AED)`,
          borderRadius: 2,
          marginTop: 24,
          marginBottom: 24,
        }}
      />

      <div
        style={{
          fontSize: 36,
          fontWeight: 400,
          color: TEXT_DIM,
          opacity: subtitleOpacity,
          transform: `translateY(${subtitleY}px)`,
          textAlign: 'center' as const,
          fontFamily: FONT,
        }}
      >
        Server-Side Header Bidding for Mobile Apps
      </div>

      <div
        style={{
          position: 'absolute',
          bottom: 60,
          fontSize: 20,
          fontWeight: 500,
          color: TEXT_DIM,
          opacity: urlOpacity,
          fontFamily: FONT,
          letterSpacing: 1,
        }}
      >
        prebid.sellwild.com
      </div>
    </div>
  )
}
