import { describe, expect, it, vi } from 'vitest'
import * as core from '@sellwild/sdk-core'
import * as rnFailures from '../src/failures'
import { expectValid } from './support/schemas'
import { recordFailures, recordingSink, takeFailureEvents, TEST_NOW, TEST_UID } from './support/failures'

recordFailures()

// A fresh module graph: core's failure context starts empty (client `core`)
// and records into the test sink. Returns that copy of core.
async function freshCore() {
  vi.resetModules()
  const fresh = await import('@sellwild/sdk-core')
  fresh.setFailureContext({ sink: recordingSink, uid: () => TEST_UID, now: () => TEST_NOW })
  return fresh
}

describe('src/failures.ts', () => {
  it("re-exports core's logFailure and code list", () => {
    expect(rnFailures.logFailure).toBe(core.logFailure)
    expect(rnFailures.FAILURE_CODES).toBe(core.FAILURE_CODES)
    expect(rnFailures.FAILURE_CODES).toEqual(
      expect.arrayContaining(['bridge.script.exception', 'widget.webview_load.network']),
    )
  })

  it('marks every failure client react-native once it loads', async () => {
    const fresh = await freshCore()
    fresh.logFailure({ code: 'listings.fetch.network', component: 'listings' })

    const rn = await import('../src/failures')
    rn.logFailure({ code: 'bridge.script.exception', component: 'webview', message: 'Script error.' })
    // Core's own reports carry it too: it is the context, not the call.
    fresh.logFailure({ code: 'config.fetch.network', component: 'remoteConfig' })

    const events = takeFailureEvents()
    expect(events.map((e) => [e.action, e.attributes.client])).toEqual([
      ['listings.fetch.network', 'core'],
      ['bridge.script.exception', 'react-native'],
      ['config.fetch.network', 'react-native'],
    ])
    // No wrapper: that marks native failures under React Native, and the
    // native bridges set it.
    expect(events[1]).toEqual({
      event: 'clientFailure',
      action: 'bridge.script.exception',
      label: 'webview',
      attributes: {
        code: 'unknown',
        client: 'react-native',
        clientVersion: core.SDK_VERSION,
        severity: 'error',
        fv: '1',
        msg: 'Script error.',
        seq: '2',
        repeat: '1',
      },
      uid: TEST_UID,
      createdTime: TEST_NOW,
    })
    expectValid('client-failure-event', events[1], 'rn-script-exception')
  })

  it('is loaded by the package index', async () => {
    const fresh = await freshCore()
    await import('../src/index')

    fresh.logFailure({ code: 'config.fetch.network', component: 'remoteConfig' })

    expect(takeFailureEvents().map((e) => e.attributes.client)).toEqual(['react-native'])
  })
})
