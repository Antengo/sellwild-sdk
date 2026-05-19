import { useCurrentFrame, useVideoConfig, interpolate, spring, Img, staticFile } from 'remotion'
import { BG, BG_CARD, TEXT, TEXT_DIM, TEXT_MUTED, ACCENT, GREEN, BORDER } from './theme'

export const DemoAuctionSlide = () => {
  const frame = useCurrentFrame()
  const { fps } = useVideoConfig()

  const phoneSpring = spring({ frame, fps, config: { damping: 12, mass: 0.5 } })
  const contentSpring = spring({ frame: frame - 10, fps, config: { damping: 12, mass: 0.5 } })

  const b1 = spring({ frame: frame - 25, fps, config: { damping: 12 } })
  const b2 = spring({ frame: frame - 35, fps, config: { damping: 12 } })
  const b3 = spring({ frame: frame - 45, fps, config: { damping: 12 } })
  const b4 = spring({ frame: frame - 55, fps, config: { damping: 12 } })
  const winSpring = spring({ frame: frame - 70, fps, config: { damping: 10 } })

  const bidders = [
    { name: 'appnexus', ms: 31, bid: '$1.50', color: GREEN, s: b1 },
    { name: 'pubmatic', ms: 23, bid: '$15.00', color: GREEN, s: b2 },
    { name: 'medianet', ms: 78, bid: null, color: null, s: b3 },
    { name: 'sharethrough', ms: 18, bid: null, color: null, s: b4 },
  ]

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
      {/* Background */}
      <div style={{
        position: 'absolute',
        inset: 0,
        background: `
          radial-gradient(ellipse 80% 60% at 25% 50%, ${GREEN}10 0%, transparent 100%),
          radial-gradient(ellipse 60% 80% at 75% 20%, ${ACCENT}08 0%, transparent 100%)
        `,
      }} />
      <div style={{
        position: 'absolute',
        inset: 0,
        opacity: 0.03,
        backgroundImage: `linear-gradient(rgba(255,255,255,0.1) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.1) 1px, transparent 1px)`,
        backgroundSize: '60px 60px',
      }} />

      {/* Left: Phone */}
      <div style={{
        flex: '0 0 480px',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        marginLeft: -20,
        transform: `translateX(${interpolate(phoneSpring, [0, 1], [-80, 0])}px)`,
        opacity: interpolate(phoneSpring, [0, 1], [0, 1]),
      }}>
        <div style={{
          width: 380,
          height: 800,
          borderRadius: 44,
          border: '5px solid #3A3633',
          overflow: 'hidden',
          backgroundColor: '#000',
          boxShadow: `0 40px 100px rgba(0,0,0,0.6), 0 0 0 1px rgba(255,255,255,0.05), 0 0 80px ${GREEN}10`,
        }}>
          <Img src={staticFile('app-auction.png')} style={{
            width: '100%',
            height: '100%',
            objectFit: 'cover',
            objectPosition: 'top',
          }} />
        </div>
      </div>

      {/* Right: Content */}
      <div style={{
        flex: 1,
        display: 'flex',
        flexDirection: 'column',
        justifyContent: 'center',
        paddingRight: 100,
        paddingLeft: 40,
        opacity: interpolate(contentSpring, [0, 1], [0, 1]),
        transform: `translateX(${interpolate(contentSpring, [0, 1], [30, 0])}px)`,
      }}>
        <div style={{
          fontSize: 14,
          fontWeight: 700,
          letterSpacing: 4,
          color: GREEN,
          textTransform: 'uppercase' as const,
          marginBottom: 20,
        }}>Auction Transparency</div>

        <h1 style={{
          fontSize: 64,
          fontWeight: 800,
          color: TEXT,
          letterSpacing: -2,
          lineHeight: 1.05,
          margin: 0,
        }}>
          Every Bid.
          <br />
          <span style={{ color: GREEN }}>Every Millisecond.</span>
        </h1>

        <p style={{
          fontSize: 20,
          color: TEXT_DIM,
          marginTop: 20,
          lineHeight: 1.5,
        }}>
          Full per-SSP auction data in real-time.
        </p>

        {/* Bidder table */}
        <div style={{
          marginTop: 32,
          backgroundColor: BG_CARD,
          border: `1px solid ${BORDER}`,
          borderRadius: 16,
          padding: '20px 24px',
        }}>
          {bidders.map(({ name, ms, bid, color, s }) => (
            <div key={name} style={{
              display: 'flex',
              alignItems: 'center',
              padding: '10px 0',
              borderBottom: `1px solid ${BORDER}`,
              opacity: interpolate(s, [0, 1], [0, 1]),
              transform: `translateX(${interpolate(s, [0, 1], [15, 0])}px)`,
            }}>
              <div style={{
                width: 10, height: 10, borderRadius: 5,
                backgroundColor: bid ? GREEN : TEXT_MUTED,
                boxShadow: bid ? `0 0 8px ${GREEN}60` : 'none',
                marginRight: 14,
              }} />
              <span style={{ flex: 1, fontSize: 17, fontWeight: 600, color: TEXT }}>{name}</span>
              <span style={{ fontSize: 15, color: TEXT_MUTED, marginRight: 24 }}>{ms}ms</span>
              <span style={{
                fontSize: 17, fontWeight: 700,
                color: bid ? GREEN : TEXT_MUTED,
              }}>{bid || 'no bid'}</span>
            </div>
          ))}

          {/* Winner */}
          <div style={{
            marginTop: 14,
            padding: '14px 18px',
            backgroundColor: `${GREEN}12`,
            borderRadius: 10,
            border: `1px solid ${GREEN}25`,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            opacity: interpolate(winSpring, [0, 1], [0, 1]),
            transform: `scale(${interpolate(winSpring, [0, 1], [0.96, 1])})`,
          }}>
            <div>
              <div style={{ fontSize: 15, fontWeight: 700, color: GREEN }}>Winner: pubmatic</div>
              <div style={{ fontSize: 13, color: TEXT_DIM, marginTop: 2 }}>300x250 video — Prebid S2S</div>
            </div>
            <div style={{ fontSize: 28, fontWeight: 800, color: GREEN }}>$15.00</div>
          </div>
        </div>

        {/* Stats */}
        <div style={{ display: 'flex', gap: 14, marginTop: 20 }}>
          {[
            { v: '4', l: 'SSPs' },
            { v: '$16.50', l: 'Total CPM', c: GREEN },
            { v: '126ms', l: 'Latency' },
            { v: '100%', l: 'Fill', c: GREEN },
          ].map(({ v, l, c }) => (
            <div key={l} style={{
              flex: 1,
              backgroundColor: BG_CARD,
              border: `1px solid ${BORDER}`,
              borderRadius: 12,
              padding: '14px 0',
              textAlign: 'center' as const,
            }}>
              <div style={{ fontSize: 22, fontWeight: 800, color: c || TEXT }}>{v}</div>
              <div style={{ fontSize: 11, color: TEXT_MUTED, marginTop: 3 }}>{l}</div>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
