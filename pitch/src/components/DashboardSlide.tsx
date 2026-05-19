import { useCurrentFrame, useVideoConfig, interpolate, spring, Img, staticFile } from 'remotion'
import { BG, TEXT, TEXT_DIM, ACCENT, GREEN } from './theme'

export const DashboardSlide = () => {
  const frame = useCurrentFrame()
  const { fps } = useVideoConfig()

  const screenScale = spring({ frame, fps, config: { damping: 14, mass: 0.6 } })
  const screenY = interpolate(screenScale, [0, 1], [40, 0])
  const glowOpacity = interpolate(frame, [15, 40], [0, 0.4], { extrapolateRight: 'clamp' })
  const badgeOpacity = interpolate(frame, [20, 35], [0, 1], { extrapolateRight: 'clamp' })
  const titleOpacity = interpolate(frame, [10, 25], [0, 1], { extrapolateRight: 'clamp' })
  const titleY = interpolate(frame, [10, 25], [20, 0], { extrapolateRight: 'clamp' })

  return (
    <div style={base}>
      {/* Glow */}
      <div style={{
        position: 'absolute',
        width: 700,
        height: 400,
        borderRadius: '50%',
        background: `radial-gradient(circle, ${ACCENT}25 0%, transparent 70%)`,
        top: '45%',
        left: '50%',
        transform: 'translate(-50%, -50%)',
        opacity: glowOpacity,
        filter: 'blur(80px)',
      }} />

      {/* Badge */}
      <div style={{
        position: 'absolute',
        top: 40,
        left: 0,
        right: 0,
        textAlign: 'center',
        opacity: badgeOpacity,
      }}>
        <span style={{
          fontSize: 13,
          fontWeight: 700,
          letterSpacing: 3,
          color: ACCENT,
          textTransform: 'uppercase',
        }}>Real-Time Analytics</span>
      </div>

      {/* Title */}
      <div style={{
        position: 'absolute',
        top: 70,
        left: 0,
        right: 0,
        textAlign: 'center',
        opacity: titleOpacity,
        transform: `translateY(${titleY}px)`,
      }}>
        <h1 style={{
          fontSize: 40,
          fontWeight: 800,
          color: TEXT,
          letterSpacing: -1,
          margin: 0,
        }}>Sellwild Admin Dashboard</h1>
        <p style={{ fontSize: 18, color: TEXT_DIM, marginTop: 8 }}>
          32,711 auctions tracked. Every bid, every millisecond.
        </p>
      </div>

      {/* Dashboard screenshot — large, browser-frame style */}
      <div style={{
        marginTop: 80,
        transform: `scale(${screenScale}) translateY(${screenY}px)`,
        position: 'relative',
      }}>
        <div style={browserFrame}>
          {/* Browser chrome */}
          <div style={browserBar}>
            <div style={{ display: 'flex', gap: 6 }}>
              <div style={{ ...browserDot, background: '#EF4444' }} />
              <div style={{ ...browserDot, background: '#F59E0B' }} />
              <div style={{ ...browserDot, background: '#22C55E' }} />
            </div>
            <div style={browserUrl}>sellwild-admin.netlify.app</div>
          </div>
          {/* Dashboard content */}
          <Img src={staticFile('sellwild-admin-dashboard.gif')} style={browserContent} />
        </div>
      </div>
    </div>
  )
}

const base: React.CSSProperties = {
  width: '100%',
  height: '100%',
  display: 'flex',
  justifyContent: 'center',
  alignItems: 'center',
  fontFamily: '"DM Sans", system-ui, sans-serif',
  backgroundColor: BG,
  color: TEXT,
  position: 'relative',
  overflow: 'hidden',
}

const browserFrame: React.CSSProperties = {
  width: 1100,
  borderRadius: 12,
  overflow: 'hidden',
  border: '1px solid #44403C',
  boxShadow: '0 30px 80px rgba(0,0,0,0.5), 0 0 0 1px rgba(255,255,255,0.03)',
}

const browserBar: React.CSSProperties = {
  display: 'flex',
  alignItems: 'center',
  gap: 12,
  padding: '10px 16px',
  background: '#1C1917',
  borderBottom: '1px solid #292524',
}

const browserDot: React.CSSProperties = {
  width: 10,
  height: 10,
  borderRadius: 5,
}

const browserUrl: React.CSSProperties = {
  flex: 1,
  textAlign: 'center',
  fontSize: 12,
  color: '#78716C',
  fontFamily: '"IBM Plex Mono", monospace',
}

const browserContent: React.CSSProperties = {
  width: '100%',
  display: 'block',
}
