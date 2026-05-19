import { loadFont } from '@remotion/google-fonts/DMSans'

const { fontFamily } = loadFont()

export const FONT = fontFamily
export const BG = '#0C0A09'        // stone-950
export const BG_CARD = '#1C1917'   // stone-900
export const TEXT = '#FAFAF9'      // stone-50
export const TEXT_DIM = '#A8A29E'  // stone-400
export const TEXT_MUTED = '#78716C' // stone-500
export const ACCENT = '#2563EB'    // blue-600
export const GREEN = '#22C55E'
export const RED = '#EF4444'
export const BORDER = '#292524'    // stone-800

export const baseStyle: React.CSSProperties = {
  width: '100%',
  height: '100%',
  display: 'flex',
  flexDirection: 'column',
  justifyContent: 'center',
  alignItems: 'center',
  fontFamily: FONT,
  backgroundColor: BG,
  color: TEXT,
  padding: 80,
}

export const heading: React.CSSProperties = {
  fontSize: 72,
  fontWeight: 800,
  letterSpacing: -2,
  lineHeight: 1.1,
  textAlign: 'center' as const,
  margin: 0,
}

export const subheading: React.CSSProperties = {
  fontSize: 32,
  fontWeight: 400,
  color: TEXT_DIM,
  textAlign: 'center' as const,
  lineHeight: 1.4,
  margin: 0,
  marginTop: 20,
}

export const badge: React.CSSProperties = {
  fontSize: 14,
  fontWeight: 700,
  letterSpacing: 2,
  textTransform: 'uppercase' as const,
  color: ACCENT,
  marginBottom: 24,
}
