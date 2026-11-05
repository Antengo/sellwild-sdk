import { describe, expect, it } from 'vitest'
import * as factories from '.'
import * as coreFactories from '../../../core/test/factories'
import { expectValid } from '../support/schemas'

describe('factories index', () => {
  it('re-exports every core factory unchanged', () => {
    const names = Object.keys(coreFactories)
    expect(names).toEqual(expect.arrayContaining(['appConfig', 'clientFailureEvent', 'listing', 'listingsResponse', 'sellwildConfig']))
    for (const name of names) {
      expect(factories[name as keyof typeof factories], name).toBe(coreFactories[name as keyof typeof coreFactories])
    }
  })

  it('gives React Native tests the core payloads, valid against the contract', () => {
    expectValid('app-config', factories.appConfig(), 'core-app-config')
    expectValid('listings-response', factories.listingsResponse(), 'core-listings-response')
    expectValid(
      'client-failure-event',
      factories.clientFailureEvent({ attributes: { client: 'react-native' } }),
      'core-client-failure-event-react-native',
    )
  })
})
