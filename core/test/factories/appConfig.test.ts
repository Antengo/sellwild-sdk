import { describe, expect, it } from 'vitest'
import { appConfig, appConfigVariants, invalidAppConfigs } from '.'
import { contract } from '../support/contracts'
import { expectInvalid, expectInvalidCases, expectValid } from '../support/factory-checks'

describe('appConfig factory', () => {
  it('defaults to the real weatherbug config, without the fixture marker', () => {
    const config = appConfig()
    expect(config).toEqual(contract('samples/app-config/weatherbug_weatherbug-weatherbug.json'))
    expect(config.CODE).toBe('weatherbug')
    expectValid('app-config', config, 'default')
  })

  it('builds every sample and fixture variant as a valid config', () => {
    const names = Object.keys(appConfigVariants)
    expect(names).toEqual(expect.arrayContaining(['weatherbug', 'antengo', 'minimal', 'events-off-text', 'failures-off-sampled']))
    for (const name of names) {
      const config = appConfig({}, name)
      expect(config).not.toHaveProperty('_synthetic')
      expectValid('app-config', config, name)
    }
  })

  it('applies typed overrides and stays valid', () => {
    const config = appConfig({ FAILURES_ENABLED: 'off', FAILURES_SAMPLE_RATE: '0.25', EVENTS_ENABLED: false, AD_STACK: 'gamOnly' }, 'minimal')
    expect(config).toMatchObject({ CODE: 'minimal', FAILURES_ENABLED: 'off', FAILURES_SAMPLE_RATE: '0.25', EVENTS_ENABLED: false })
    expectValid('app-config', config, 'overrides')
  })

  it('fails the schema when an override breaks it', () => {
    expectInvalid('app-config', appConfig({ CODE: '' }), { instancePath: '/CODE', keyword: 'minLength' })
    expectInvalid('app-config', appConfig({ MOBILE_ZID: '43' as unknown as string[] }), { instancePath: '/MOBILE_ZID', keyword: 'type' })
  })

  it('fails the schema for each invalid contract fixture', () => {
    expectInvalidCases('app-config', invalidAppConfigs())
  })

  it('returns a fresh copy each time and rejects an unknown variant', () => {
    appConfig().MOBILE_ZID.push('changed')
    expect(appConfig().MOBILE_ZID).toEqual(['weatherbug-mobile-300x250'])
    expect(() => appConfig({}, 'nope')).toThrow("no app-config variant 'nope'")
  })
})
