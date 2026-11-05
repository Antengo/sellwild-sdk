// Events: an SdkEvent as a host pushes it into the queue, and a clientFailure
// event as logFailure builds it. Bases are the contract fixtures.

import type { ClientFailureEvent } from '../../src/failures'
import type { SdkEvent } from '../../src/types'
import { contract, contractFiles, variantName } from '../support/contracts'
import { fixtureVariants, invalidCases, load, variantsOf, type InvalidCase } from './base'

// The first event of each events-batch fixture, minus what the queue adds.
export const sdkEventVariants = variantsOf(
  contractFiles('fixtures/events-batch/valid').map((file): [string, () => unknown] => [
    variantName(file),
    () => {
      const [first] = contract<Array<Record<string, unknown>>>(`fixtures/events-batch/valid/${file}`)
      const { uid, createdTime, ...event } = first
      return event
    },
  ]),
)

export function sdkEvent(overrides: Partial<SdkEvent> = {}, variant = 'ios-ad-error'): SdkEvent {
  return { ...load<SdkEvent>('events-batch', sdkEventVariants, variant), ...overrides }
}

/** The wire form of pushed events: what the queue POSTs (before stamping). */
export function wireEvents(events: SdkEvent[], uid = '8F2C1C1E-1B7B-4E0E-9A57-6C3E7C3F4E11', createdTime = 1790000000000) {
  return events.map((e) => ({ ...e, uid, createdTime }))
}

export const clientFailureEventVariants = fixtureVariants('client-failure-event')

export type ClientFailureEventOverrides = Partial<Omit<ClientFailureEvent, 'attributes'>> & {
  /** Merged into the variant's attributes. */
  attributes?: ClientFailureEvent['attributes']
}

export function clientFailureEvent(overrides: ClientFailureEventOverrides = {}, variant = 'listings-http'): ClientFailureEvent {
  const base = load<ClientFailureEvent>('client-failure-event', clientFailureEventVariants, variant)
  return { ...base, ...overrides, attributes: { ...base.attributes, ...overrides.attributes } }
}

export function invalidClientFailureEvents(): InvalidCase[] {
  return invalidCases('client-failure-event')
}
