import { useCurrentFrame, useVideoConfig, interpolate, spring, Img, staticFile } from 'remotion'
import { BG, TEXT, TEXT_DIM, ACCENT, GREEN } from './theme'

export const DemoListingsSlide = () => {
  const frame = useCurrentFrame()
  const { fps } = useVideoConfig()

  const phoneSpring = spring({ frame, fps, config: { damping: 12, mass: 0.5 } })
  const contentSpring = spring({ frame: frame - 10, fps, config: { damping: 12, mass: 0.5 } })

  const feat1 = spring({ frame: frame - 25, fps, config: { damping: 12 } })
  const feat2 = spring({ frame: frame - 40, fps, config: { damping: 12 } })
  const feat3 = spring({ frame: frame - 55, fps, config: { damping: 12 } })

  return (
    <div style={{
      width: '100%',
      height: '100%',
      display: 'flex',
      fontFamily: '"DM Sans", system-ui, sans-serif',
      backgroundColor: BG,
      color: TEXT,
      position: 'relative',
      overflow: 'hidden',
    }}>
      {/* Full-bleed gradient background */}
      <div style={{
        position: 'absolute',
        inset: 0,
        background: `
          radial-gradient(ellipse 80% 60% at 75% 50%, ${ACCENT}12 0%, transparent 100%),
          radial-gradient(ellipse 60% 80% at 25% 80%, ${GREEN}08 0%, transparent 100%)
        `,
      }} />

      {/* Subtle grid pattern */}
      <div style={{
        position: 'absolute',
        inset: 0,
        opacity: 0.03,
        backgroundImage: `linear-gradient(rgba(255,255,255,0.1) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.1) 1px, transparent 1px)`,
        backgroundSize: '60px 60px',
      }} />

      {/* Left content */}
      <div style={{
        flex: 1,
        display: 'flex',
        flexDirection: 'column',
        justifyContent: 'center',
        paddingLeft: 100,
        paddingRight: 40,
        opacity: interpolate(contentSpring, [0, 1], [0, 1]),
        transform: `translateX(${interpolate(contentSpring, [0, 1], [-30, 0])}px)`,
      }}>
        <div style={{
          fontSize: 14,
          fontWeight: 700,
          letterSpacing: 4,
          color: ACCENT,
          textTransform: 'uppercase' as const,
          marginBottom: 20,
        }}>Live Demo</div>

        <h1 style={{
          fontSize: 64,
          fontWeight: 800,
          color: TEXT,
          letterSpacing: -2,
          lineHeight: 1.05,
          margin: 0,
        }}>
          Native Listings
          <br />
          <span style={{ color: ACCENT }}>+ Real Ads</span>
        </h1>

        <p style={{
          fontSize: 22,
          color: TEXT_DIM,
          marginTop: 24,
          lineHeight: 1.6,
          maxWidth: 480,
        }}>
          Marketplace cards rendered natively with programmatic ads served via Prebid Server.
        </p>

        {/* Feature pills */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 16, marginTop: 40 }}>
          {[
            { label: 'Native listing cards from real API data', color: GREEN, s: feat1 },
            { label: 'Display ad — AppNexus $1.50 CPM via S2S', color: ACCENT, s: feat2 },
            { label: 'WeatherBug house ad on no-fill slots', color: '#A855F7', s: feat3 },
          ].map(({ label, color, s }) => (
            <div key={label} style={{
              display: 'flex',
              alignItems: 'center',
              gap: 14,
              opacity: interpolate(s, [0, 1], [0, 1]),
              transform: `translateX(${interpolate(s, [0, 1], [-20, 0])}px)`,
            }}>
              <div style={{
                width: 10,
                height: 10,
                borderRadius: 5,
                backgroundColor: color,
                boxShadow: `0 0 12px ${color}60`,
              }} />
              <span style={{ fontSize: 18, color: TEXT_DIM, fontWeight: 500 }}>{label}</span>
            </div>
          ))}
        </div>
      </div>

      {/* Right: Phone — LARGE, vertically centered, slight overlap off right edge */}
      <div style={{
        flex: '0 0 480px',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        marginRight: -20,
        transform: `translateX(${interpolate(phoneSpring, [0, 1], [80, 0])}px)`,
        opacity: interpolate(phoneSpring, [0, 1], [0, 1]),
      }}>
        <div style={{
          width: 380,
          height: 800,
          borderRadius: 44,
          border: '5px solid #3A3633',
          overflow: 'hidden',
          backgroundColor: '#000',
          boxShadow: `
            0 40px 100px rgba(0,0,0,0.6),
            0 0 0 1px rgba(255,255,255,0.05),
            0 0 80px ${ACCENT}15
          `,
        }}>
          <Img src={staticFile('app-listings.png')} style={{
            width: '100%',
            height: '100%',
            objectFit: 'cover',
            objectPosition: 'top',
          }} />
        </div>
      </div>
    </div>
  )
}
