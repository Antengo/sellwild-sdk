import { describe, expect, it } from 'vitest'
import { AD_DIMENSIONS, adDimensions, bannerBaseline, parseSizeList, resizedSlot, type SlotSize } from '../src/bannerSizing'
import { appConfig, wrongTypedAppConfig } from './factories'
import { expectValid } from './support/schemas'

const remoteOf = (variant: string) => {
  const remote = appConfig({}, variant)
  expectValid('app-config', remote)
  return remote
}

describe('adDimensions', () => {
  it('gives each AdSize its IAB box', () => {
    for (const [size, dim] of Object.entries(AD_DIMENSIONS)) {
      expect(adDimensions(size)).toBe(dim)
      expect(`${dim.width}x${dim.height}`).toBe(size)
    }
  })

  it.each([['320x100'], ['300X250'], ['toString'], ['constructor'], [''], [undefined], [300]])('gives null for %j', (size) => {
    expect(adDimensions(size)).toBeNull()
  })
})

describe('parseSizeList, over the BANNER_SIZES fixtures', () => {
  const cases: Array<[string, SlotSize[]]> = [
    ['banner-sizes-json-text', [{ width: 300, height: 250 }, { width: 320, height: 50 }]],
    ['banner-sizes-pairs', [{ width: 300, height: 250 }, { width: 728, height: 90 }, { width: 320, height: 50 }]],
    ['banner-sizes-single-string', [{ width: 300, height: 250 }]],
    ['banner-sizes-string-list', [{ width: 300, height: 250 }, { width: 320, height: 50 }, { width: 728, height: 90 }]],
    // The CMS's "unset" is the empty string.
    ['by-zone-maps-empty', []],
    ['weatherbug', []],
  ]

  it.each(cases)('%s', (variant, sizes) => {
    expect(parseSizeList(remoteOf(variant).BANNER_SIZES)).toEqual(sizes)
  })

  it('drops entries that are not positive WxH labels or [w, h] pairs (native reports them)', () => {
    expect(parseSizeList(['0x250', 'x', '300x', 'axb', [300], [300, 250, 1], [0, 50], ['320', '50'], null, 7])).toEqual([
      { width: 320, height: 50 },
    ])
  })

  it('reads text that is not JSON as one label, and gives nothing for other kinds', () => {
    expect(parseSizeList('320x50')).toEqual([{ width: 320, height: 50 }])
    expect(parseSizeList('not a size')).toEqual([])
    expect(parseSizeList('{"300x250":1}')).toEqual([])
    expect(parseSizeList(undefined)).toEqual([])
    expect(parseSizeList({ '0': '300x250' })).toEqual([])
  })
})

describe('bannerBaseline', () => {
  const mrec = AD_DIMENSIONS['300x250']
  const banner = AD_DIMENSIONS['320x50']

  it('is the requested size when the config adds none', () => {
    expect(bannerBaseline(mrec, remoteOf('weatherbug'), 43)).toEqual({ width: 300, height: 250 })
    expect(bannerBaseline(mrec, undefined, 43)).toEqual({ width: 300, height: 250 })
  })

  it('reserves the widest and tallest of the requested and the fallback sizes', () => {
    // 320x50 is wider than a 300x250 MREC.
    expect(bannerBaseline(mrec, remoteOf('banner-sizes-json-text'), 43)).toEqual({ width: 320, height: 250 })
    expect(bannerBaseline(banner, remoteOf('banner-sizes-pairs'), 43)).toEqual({ width: 728, height: 250 })
  })

  it('takes the zone entry of BANNER_SIZES_BY_ZONE over BANNER_SIZES, by number or text zone id', () => {
    const remote = remoteOf('by-zone-maps-objects')
    expect(bannerBaseline(banner, remote, 43)).toEqual({ width: 320, height: 250 })
    expect(bannerBaseline(banner, remote, '280')).toEqual({ width: 320, height: 600 })
    // No entry for the zone: the global list.
    expect(bannerBaseline(banner, remote, 7)).toEqual({ width: 320, height: 250 })
  })

  it("treats the CMS's '' BANNER_SIZES_BY_ZONE as unset", () => {
    expect(bannerBaseline(banner, remoteOf('by-zone-maps-empty'), 43)).toEqual({ width: 320, height: 50 })
  })

  it('ignores a BANNER_SIZES_BY_ZONE that is text, not a map: BANNER_SIZES applies', () => {
    const remote = wrongTypedAppConfig('by-zone-label')
    // Indexing the text '728x90' by zone 0 or 1 would find '7' or '2', which
    // is no size, and so lose the BANNER_SIZES fallback (320 wide).
    expect(bannerBaseline(mrec, remote, 0)).toEqual({ width: 320, height: 250 })
    expect(bannerBaseline(mrec, remote, '1')).toEqual({ width: 320, height: 250 })
  })

  it('holds only the fallbacks, or 0x0, for a size that is not an AdSize', () => {
    expect(bannerBaseline(null, remoteOf('banner-sizes-json-text'), 43)).toEqual({ width: 320, height: 250 })
    expect(bannerBaseline(null, remoteOf('weatherbug'), 43)).toEqual({ width: 0, height: 0 })
  })
})

describe('resizedSlot', () => {
  it.each([
    [{ width: 320, height: 50 }, { width: 320, height: 50 }],
    [{ width: 0, height: 50 }, null],
    [{ width: 320, height: 0 }, null],
    [{ width: 320 }, null],
    [{}, null],
    [undefined, null],
  ])('%j gives %j', (event, slot) => {
    expect(resizedSlot(event)).toEqual(slot)
  })
})
