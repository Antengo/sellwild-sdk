import { describe, expect, it } from 'vitest'
import { appConfig, appConfigVariants, localizedListingsConfig, sellwildConfig } from '.'
import { buildConfig } from '../../src/config'
import type { SellwildConfig } from '../../src/types'
import { expectInvalid, expectValid } from '../support/factory-checks'

describe('sellwildConfig factory', () => {
  it('merges defaults, the real weatherbug config and nothing else by default', () => {
    const config: SellwildConfig = sellwildConfig()
    expect(config).toMatchObject({
      partnerCode: 'weatherbug',
      slug: 'weatherbug-weatherbug',
      iabCats: ['IAB15'],
      adStack: 'prebidOnly',
      eventsEnabled: true,
      failuresEnabled: true,
      failuresSampleRate: 1,
    })
    // Every default key is present, typed.
    expect(Object.keys(config)).toEqual(expect.arrayContaining(Object.keys(buildConfig({ partnerCode: 'x' }))))
    expectValid('app-config', config.remote, 'sellwild-config-remote')
  })

  it('carries a valid remote payload for every app-config variant', () => {
    for (const name of Object.keys(appConfigVariants)) {
      const config = sellwildConfig({}, appConfig({}, name))
      expect(config.partnerCode, name).toBe(appConfig({}, name).CODE)
      expectValid('app-config', config.remote, undefined)
    }
  })

  it('applies typed overrides last, as configure does', () => {
    const localizedListings = localizedListingsConfig({ frequency: 50 }) as SellwildConfig['localizedListings']
    const config = sellwildConfig({ debug: true, failuresEnabled: false, localizedListings }, appConfig({ FAILURES_SAMPLE_RATE: '0.25' }))
    expect(config).toMatchObject({ debug: true, failuresEnabled: false, failuresSampleRate: 0.25 })
    expectValid('localized-listings-config', config.localizedListings)
    expectValid('rn-native-config', { enabled: true, partnerId: 'p' }, undefined, '/$defs/growthCode')
  })

  it('carries a remote payload that fails the schema when the app config is broken', () => {
    const { CODE, ...withoutCode } = appConfig()
    expect(CODE).toBe('weatherbug')
    expectInvalid('app-config', sellwildConfig({}, { ...withoutCode, CODE: '' }).remote, { instancePath: '/CODE', keyword: 'minLength' })
  })
})
