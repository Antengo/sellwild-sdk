import { describe, expect, it } from 'vitest'
import { AD_DIMENSIONS } from '../src/bannerSizing'
import swiftRules from '../ios/SellwildRNBridgeRules.swift?raw'
import kotlinRules from '../android/src/main/java/com/sellwild/rnsdk/RnBridgeRules.kt?raw'
import iosBanner from '../ios/SellwildBannerViewManager.swift?raw'
import androidBanner from '../android/src/main/java/com/sellwild/rnsdk/SellwildBannerViewManager.kt?raw'
import iosModule from '../ios/SellwildRNModule.swift?raw'
import androidModule from '../android/src/main/java/com/sellwild/rnsdk/SellwildModule.kt?raw'

// The native bridges (react-native/ios, react-native/android) cannot run here:
// they need an RN host app build. What this checks is the agreement between
// them and JS that keeps a failure logged once (contracts/FAILURES.md 9):
// <SellwildBanner> reports a size label that is not a JS AdSize
// (ad.size.invalid), and the bridges report only a JS AdSize they have no
// native size for (bridge.props.invalid). Both need the same label list.

/** The string literals of the first `<name> ... = [...]` or `setOf(...)` declaration in `source`. */
function labelList(source: string, name: string): string[] {
  const match = new RegExp(`${name}[^=]*=\\s*(?:setOf\\(|\\[)([^\\])]*)[\\])]`).exec(source)
  if (!match) throw new Error(`no ${name} list`)
  // The test lib is ES2018: no String.prototype.matchAll.
  return (match[1].match(/"[^"]*"/g) ?? []).map((literal) => literal.slice(1, -1))
}

describe('the native bridges and JS agree on the size labels JS accepts', () => {
  const js = Object.keys(AD_DIMENSIONS).sort()

  it('iOS SellwildRNBridgeRules.jsAdSizeLabels', () => {
    expect(labelList(swiftRules, 'jsAdSizeLabels').sort()).toEqual(js)
  })

  it('Android RnBridgeRules.JS_AD_SIZE_LABELS', () => {
    expect(labelList(kotlinRules, 'JS_AD_SIZE_LABELS').sort()).toEqual(js)
  })

  it('both bridges decide a props problem with that rule before they set up an ad', () => {
    expect(iosBanner).toContain('SellwildRNBridgeRules.bannerPropsProblem(')
    expect(iosBanner).toContain('code: .bridgePropsInvalid')
    expect(androidBanner).toContain('RnBridgeRules.bannerPropsProblem(')
    expect(androidBanner).toContain('SellwildFailureCode.BRIDGE_PROPS_INVALID')
  })

  it('reads a list the way it is written', () => {
    expect(labelList('static let jsAdSizeLabels: Set<String> = ["a", "b"]', 'jsAdSizeLabels')).toEqual(['a', 'b'])
    expect(labelList('val JS_AD_SIZE_LABELS: Set<String> = setOf("a", "b")', 'JS_AD_SIZE_LABELS')).toEqual(['a', 'b'])
    expect(() => labelList('nothing here', 'jsAdSizeLabels')).toThrow('no jsAdSizeLabels list')
  })
})

// setGeo drops a geo field of the wrong type and reports it as
// bridge.geo.invalid on both platforms (the Android bridge used to crash on
// one). Both need the same fields with the same types, so a field one bridge
// drops the other does not keep.
describe('the native bridges agree on the geo fields setGeo reads', () => {
  /** Android GEO_FIELD_TYPES, split by the type each field needs. */
  function androidGeoFields(): { text: string[]; number: string[] } {
    const block = /GEO_FIELD_TYPES[^=]*=\s*linkedMapOf\(([^)]*)\)/.exec(kotlinRules)?.[1]
    if (!block) throw new Error('no GEO_FIELD_TYPES map')
    const fields = { text: [] as string[], number: [] as string[] }
    for (const pair of block.match(/"\w+" to "\w+"/g) ?? []) {
      const [, key, type] = /"(\w+)" to "(\w+)"/.exec(pair)!
      if (type === 'String') fields.text.push(key)
      else if (type === 'Number') fields.number.push(key)
      else throw new Error(`geo field ${key} needs ${type}`)
    }
    return fields
  }

  it('the same text and number fields, in the same order', () => {
    const android = androidGeoFields()
    expect(android.text).toEqual(labelList(swiftRules, 'geoTextFields'))
    expect(android.number).toEqual(labelList(swiftRules, 'geoNumberFields'))
    expect([...android.text, ...android.number]).toEqual(['country', 'state', 'city', 'zip', 'metro', 'lat', 'lon', 'type'])
  })

  it('both setGeo bridges check the fields and report bridge.geo.invalid', () => {
    expect(iosModule).toContain('SellwildRNBridgeRules.geoMap(')
    expect(iosModule).toContain('code: .bridgeGeoInvalid')
    expect(androidModule).toContain('RnGeo.parse(')
    expect(androidModule).toContain('SellwildFailureCode.BRIDGE_GEO_INVALID')
  })
})
