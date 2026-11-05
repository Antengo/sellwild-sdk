import { describe, expect, it } from 'vitest'
import {
  invalidLocalizedListingsConfigs,
  invalidLocalizedListingsResponses,
  listing,
  localizedListingsConfig,
  localizedListingsConfigVariants,
  localizedListingsResponse,
  localizedListingsResponseVariants,
} from '.'
import { resolveLocalizedListings } from '../../src/localized-listings'
import { expectInvalid, expectInvalidCases, expectValid } from '../support/factory-checks'

describe('localizedListingsConfig factory', () => {
  it('defaults to the full fixture, which core resolves', () => {
    const config = localizedListingsConfig()
    expectValid('localized-listings-config', config, 'default')
    expect(resolveLocalizedListings({ localizedListings: config as never })).toMatchObject({ source: 'sportserver', forceState: 'AL', frequency: 25 })
  })

  it('builds every fixture variant as a valid config', () => {
    const names = Object.keys(localizedListingsConfigVariants)
    expect(names).toEqual(expect.arrayContaining(['full', 'minimal', 'disabled-only', 'frequency-text']))
    for (const name of names) expectValid('localized-listings-config', localizedListingsConfig({}, name), name)
  })

  it('applies typed overrides and stays valid', () => {
    const config = localizedListingsConfig({ frequency: '20', forceState: 'ga', enabled: false })
    expect(config).toMatchObject({ frequency: '20', forceState: 'ga', enabled: false })
    expectValid('localized-listings-config', config, 'overrides')
  })

  it('fails the schema when an override breaks it, and for each invalid contract fixture', () => {
    expectInvalid('localized-listings-config', localizedListingsConfig({ urlTemplate: 'sports.json' }), { instancePath: '/urlTemplate', keyword: 'pattern' })
    expectInvalidCases('localized-listings-config', invalidLocalizedListingsConfigs())
  })
})

describe('localizedListingsResponse factory', () => {
  it('defaults to the real Alabama sports cache', () => {
    const body = localizedListingsResponse()
    expect(body.result.state).toBe('AL')
    expect(body.result.rs.length).toBeGreaterThan(0)
    expectValid('localized-listings-response', body, 'default')
  })

  it('builds every sample and fixture variant as a valid response', () => {
    const names = Object.keys(localizedListingsResponseVariants)
    expect(names).toEqual(expect.arrayContaining(['sports-img-data-sm-webp-ga', 'minimal', 'one-item']))
    for (const name of names) expectValid('localized-listings-response', localizedListingsResponse({}, name), name)
  })

  it('applies typed overrides to result and stays valid', () => {
    const body = localizedListingsResponse({ state: 'GA', rs: [listing()] })
    expect(body.result).toMatchObject({ state: 'GA', rs: [{ id: '105140231' }] })
    expectValid('localized-listings-response', body, 'overrides')
  })

  it('fails the schema when an override breaks it, and for each invalid contract fixture', () => {
    expectInvalid('localized-listings-response', localizedListingsResponse({ state: 'al' }), { instancePath: '/result/state', keyword: 'pattern' })
    expectInvalidCases('localized-listings-response', invalidLocalizedListingsResponses())
  })
})
