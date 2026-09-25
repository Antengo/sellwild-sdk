import { describe, expect, it } from 'vitest'
import { clientFailureEvent, clientFailureEventVariants, invalidClientFailureEvents, sdkEvent, sdkEventVariants, wireEvents } from '.'
import { decideFailure } from '../../src/failures/core'
import { expectInvalid, expectInvalidCases, expectValid } from '../support/factory-checks'

describe('sdkEvent factory', () => {
  it('defaults to the iOS adError event, minus what the queue adds', () => {
    const event = sdkEvent()
    expect(event).toEqual({ event: 'adError', action: 'No fill', label: '43', attributes: { type: 'ios', sdkVersion: '1.7.7', code: 'weatherbug' } })
    expectValid('events-batch', wireEvents([event]), 'sdk-event-default')
  })

  it('builds the first event of every events-batch fixture as a valid wire event', () => {
    const names = Object.keys(sdkEventVariants)
    expect(names).toEqual(expect.arrayContaining(['android-render', 'flutter-minimal', 'web-winning-bid']))
    for (const name of names) {
      expect(sdkEvent({}, name)).not.toHaveProperty('uid')
      expectValid('events-batch', wireEvents([sdkEvent({}, name)]), `sdk-event-${name}`)
    }
    expectValid('events-batch', wireEvents([sdkEvent()])[0], undefined, '/$defs/event')
  })

  it('applies typed overrides and stays valid', () => {
    const event = sdkEvent({ event: 'click', label: '280', amount: 1, attributes: { code: 'weatherbug' } })
    expectValid('events-batch', wireEvents([event]), 'sdk-event-overrides')
  })

  it('fails the schema when an override breaks it', () => {
    expectInvalid('events-batch', wireEvents([sdkEvent({ event: '' })]), { instancePath: '/0/event', keyword: 'minLength' })
    expectInvalid('events-batch', wireEvents([sdkEvent({ attributes: { type: 'windows' } })]), { instancePath: '/0/attributes/type', keyword: 'enum' })
  })
})

describe('clientFailureEvent factory', () => {
  it('defaults to the listings HTTP 503 event', () => {
    const event = clientFailureEvent()
    expect(event).toMatchObject({ action: 'listings.fetch.http', label: 'listings', attributes: { httpStatus: '503', seq: '1' } })
    expectValid('client-failure-event', event, 'default')
  })

  it('builds every fixture variant as a valid event', () => {
    const names = Object.keys(clientFailureEventVariants)
    expect(names).toEqual(expect.arrayContaining(['minimal', 'all-16-attributes', 'invalid-code-replaced']))
    for (const name of names) expectValid('client-failure-event', clientFailureEvent({}, name), name)
  })

  it('merges attribute overrides and stays valid', () => {
    const event = clientFailureEvent({ action: 'config.fetch.timeout', label: 'remoteConfig', attributes: { client: 'core', msg: 'no answer in 5000 ms' } })
    expect(event.attributes).toMatchObject({ code: 'weatherbug', client: 'core', msg: 'no answer in 5000 ms', seq: '1' })
    expectValid('client-failure-event', event, 'overrides')
  })

  it('matches what the pure core builds for the same failure', () => {
    const { event } = decideFailure(null, {
      code: 'listings.fetch.http', component: 'listings', message: 'HTTP 503', httpStatus: 503,
      url: 'https://cache.sellwild.com/listings-img-data-sm', zoneId: '43',
    }, { partnerCode: 'weatherbug', client: 'ios', clientVersion: '1.7.7' }, '8F2C1C1E-1B7B-4E0E-9A57-6C3E7C3F4E11', 1790000000000)
    expect(event).toEqual(clientFailureEvent())
  })

  it('fails the schema when an override breaks it, and for each invalid contract fixture', () => {
    expectInvalid('client-failure-event', clientFailureEvent({ attributes: { seq: '21' } }), { instancePath: '/attributes/seq', keyword: 'pattern' })
    expectInvalid('client-failure-event', clientFailureEvent({ attributes: { stack: 'x'.repeat(801) } }), { instancePath: '/attributes/stack', keyword: 'maxLength' })
    expectInvalidCases('client-failure-event', invalidClientFailureEvents())
  })
})
