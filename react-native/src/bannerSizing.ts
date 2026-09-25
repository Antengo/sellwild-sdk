import type { AdSize } from '@sellwild/sdk-core'

// Pure slot sizing for <SellwildBanner>: the size the host asked for, the
// fallback sizes the remote config adds, and the size native reports back.

export interface SlotSize {
  width: number
  height: number
}

// Standard IAB mobile ad sizes — used to lock the host View dimensions.
// The actual ad size is also propagated to native as the `size` prop label.
// The native bridges keep a copy of these labels to decide which bad size
// they report (SellwildRNBridgeRules.swift, RnBridgeRules.kt);
// test/nativeGlue.test.ts keeps the copies equal.
export const AD_DIMENSIONS: Record<AdSize, SlotSize> = {
  '300x250': { width: 300, height: 250 },
  '320x50': { width: 320, height: 50 },
  '728x90': { width: 728, height: 90 },
  '160x600': { width: 160, height: 600 },
  '300x600': { width: 300, height: 600 },
  '1x1': { width: 1, height: 1 },
}

/**
 * The dimensions of an AdSize label, or null for any other value. JS callers
 * are not type-checked, and a plain index would also find Object.prototype
 * members ('toString').
 */
export function adDimensions(size: unknown): SlotSize | null {
  return typeof size === 'string' && Object.prototype.hasOwnProperty.call(AD_DIMENSIONS, size)
    ? AD_DIMENSIONS[size as AdSize]
    : null
}

// Parse a BANNER_SIZES value — `["300x250","320x50"]` or `[[300,250],…]`,
// possibly a JSON string — into {width,height}[]. Mirrors the native
// SellwildAdSizes parser so the RN slot reasons about the same size set the
// auction requests.
//
// Entries that do not parse are dropped here without a report: the native
// view parses the same `remote` value and reports them itself
// (config.banner_sizes.invalid in SellwildAdSizes on iOS and Android), and a
// failure is logged once, at the lowest layer (contracts/FAILURES.md 9).
export function parseSizeList(raw: unknown): SlotSize[] {
  let arr: unknown = raw
  if (typeof raw === 'string') {
    try {
      arr = JSON.parse(raw)
    } catch {
      // Not JSON: a single 'WxH' label, as the native parser reads it.
      arr = [raw]
    }
  }
  if (!Array.isArray(arr)) return []
  const out: SlotSize[] = []
  for (const e of arr) {
    if (typeof e === 'string') {
      const [w, h] = e.toLowerCase().split('x').map((s) => Number(s.trim()))
      if (w > 0 && h > 0) out.push({ width: w, height: h })
    } else if (Array.isArray(e) && e.length === 2) {
      const w = Number(e[0]); const h = Number(e[1])
      if (w > 0 && h > 0) out.push({ width: w, height: h })
    }
  }
  return out
}

/**
 * The widest/tallest size the auction may return for this placement: the
 * primary (`dim`) plus any BANNER_SIZES_BY_ZONE[zoneId] or BANNER_SIZES
 * fallbacks. `dim` is null for a size label that is not an AdSize; the slot
 * then holds the fallbacks, or 0x0 when there are none.
 */
export function bannerBaseline(dim: SlotSize | null, remote: unknown, zoneId: number | string): SlotSize {
  const values = (remote ?? {}) as Record<string, unknown>
  const byZone = values['BANNER_SIZES_BY_ZONE']
  const zoned = byZone && typeof byZone === 'object'
    ? (byZone as Record<string, unknown>)[String(zoneId)]
    : undefined
  const sizes = [...(dim ? [dim] : []), ...parseSizeList(zoned ?? values['BANNER_SIZES'])]
  return {
    width: Math.max(0, ...sizes.map((s) => s.width)),
    height: Math.max(0, ...sizes.map((s) => s.height)),
  }
}

/** The size an onAdResize event reports, or null when it has no positive width and height. */
export function resizedSlot(nativeEvent: { width?: number; height?: number } | undefined): SlotSize | null {
  const { width = 0, height = 0 } = nativeEvent ?? {}
  return width > 0 && height > 0 ? { width, height } : null
}
