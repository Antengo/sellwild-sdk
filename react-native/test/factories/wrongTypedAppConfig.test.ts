import { describe, expect, it } from 'vitest'
import { appConfig, wrongTypedAppConfig, wrongTypedAppConfigs } from '.'
import { expectInvalid, expectValid } from '../support/schemas'

describe('wrongTypedAppConfig factory', () => {
  it('builds app configs that fail the contract in the one field they change', () => {
    expect(Object.keys(wrongTypedAppConfigs)).toEqual(['by-zone-label'])
    for (const [name, { error }] of Object.entries(wrongTypedAppConfigs)) {
      expectInvalid('app-config', wrongTypedAppConfig(name), error, name)
    }
    expect(() => wrongTypedAppConfig('nope')).toThrow("no wrong-typed app-config 'nope'")
  })

  it('changes only that field of a valid base', () => {
    const { BANNER_SIZES_BY_ZONE, ...rest } = wrongTypedAppConfig('by-zone-label')
    expect(BANNER_SIZES_BY_ZONE).toBe('728x90')
    const base = appConfig({}, 'banner-sizes-json-text')
    expect(base).not.toHaveProperty('BANNER_SIZES_BY_ZONE')
    expect(rest).toEqual(base)
    expectValid('app-config', base, 'wrong-typed-base-by-zone-label')
  })
})
