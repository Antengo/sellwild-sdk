import { beforeEach, describe, expect, it, vi } from 'vitest'
import { SDK_VERSION, EVENTS_URL } from '../src/config'
import { debugLog, isDebugLogging, setDebugLogging } from '../src/debug-log'
import { eventQueue } from '../src/event-queue'
import {
  getFailureInternalErrors,
  logFailure,
  logFailuresWithFlags,
  resetFailuresForTests,
  setFailureContext,
  strictestFailureFlags,
  type ClientFailureEvent,
  type FailureSink,
  type LogFailureInput,
} from '../src/failures'
import { recordingSink, resetFailures, takeFailureEvents, takeRecordedFailures } from './support/failures'
import { validate } from './support/schemas'

// The logFailure shell (contracts/FAILURES.md section 3.4): context, kill
// switches, the debug echo, and that it never throws or recurses.

const NOW = 1790000000000
const UID = '8F2C1C1E-1B7B-4E0E-9A57-6C3E7C3F4E11'

function fixedDeps(): void {
  setFailureContext({ now: () => NOW, uid: () => UID })
}

const http503: LogFailureInput = {
  code: 'listings.fetch.http',
  component: 'listings',
  message: 'HTTP 503',
  httpStatus: 503,
  url: 'https://cache.sellwild.com/listings-img-data-sm?v=2',
  zoneId: 43,
}

describe('logFailure context', () => {
  beforeEach(fixedDeps)

  it('sends a core event with the SDK version and no partner until one is set', () => {
    logFailure(http503)

    expect(takeRecordedFailures()).toEqual([
      {
        event: {
          event: 'clientFailure',
          action: 'listings.fetch.http',
          label: 'listings',
          attributes: {
            code: 'unknown',
            client: 'core',
            clientVersion: SDK_VERSION,
            severity: 'error',
            fv: '1',
            msg: 'HTTP 503',
            httpStatus: '503',
            host: 'cache.sellwild.com',
            zoneId: '43',
            seq: '1',
            repeat: '1',
          },
          uid: UID,
          createdTime: NOW,
        },
        flushed: true,
      },
    ])
  })

  it('carries the partner, client, version and wrapper that were set', () => {
    setFailureContext({ partnerCode: 'weatherbug', client: 'react-native', clientVersion: '9.9.9', wrapper: 'flutter' })

    logFailure(http503)

    expect(takeFailureEvents()[0].attributes).toMatchObject({
      code: 'weatherbug',
      client: 'react-native',
      clientVersion: '9.9.9',
      wrapper: 'flutter',
    })
  })

  it('merges partial updates and goes back to the default for a field set to undefined', () => {
    setFailureContext({ partnerCode: 'weatherbug', client: 'react-native' })
    setFailureContext({ clientVersion: '2.0.0' })
    setFailureContext({ client: undefined })

    logFailure(http503)

    expect(takeFailureEvents()[0].attributes).toMatchObject({ code: 'weatherbug', client: 'core', clientVersion: '2.0.0' })
  })

  it('uses the injected clock and uid for every event', () => {
    let t = NOW
    setFailureContext({ now: () => (t += 1000), uid: () => 'uid-2' })

    logFailure(http503)
    logFailure({ code: 'config.fetch.http', component: 'remoteConfig' })

    expect(takeFailureEvents().map((e) => [e.uid, e.createdTime])).toEqual([
      ['uid-2', NOW + 1000],
      ['uid-2', NOW + 2000],
    ])
  })

  it('uses the shared queue uid and Date.now by default', () => {
    setFailureContext({ now: undefined, uid: undefined })
    vi.useFakeTimers({ now: NOW + 5 })

    logFailure(http503)

    const [event] = takeFailureEvents()
    expect(event.uid).toBe(eventQueue.getUid())
    expect(event.createdTime).toBe(NOW + 5)
  })

  it('turns an Error into errName, message and stack, all sanitized', () => {
    const error = new TypeError('fetch failed for jane@example.com')
    error.stack = 'TypeError: fetch failed\n    at load (https://cdn.example.com/app/bundle.js?v=3:10:5)\n    at run (/Users/x/app/main.js:2:1)'

    logFailure({ code: 'listings.fetch.network', component: 'listings', error, message: 'listings GET' })

    expect(takeFailureEvents()[0].attributes).toMatchObject({
      errName: 'TypeError',
      msg: 'listings GET: fetch failed for <email>',
      // A URL runs to the next space or parenthesis, line and column included.
      stack: 'at load (cdn.example.com)\nat run (main.js:2:1)',
    })
  })

  it('takes a string error as the message and ignores any other error value', () => {
    logFailure({ code: 'config.fetch.parse', component: 'remoteConfig', error: 'Unexpected token <' })
    logFailure({ code: 'config.fetch.network', component: 'remoteConfig', error: { message: 'not an Error' } })
    logFailure({ code: 'config.fetch.timeout', component: 'remoteConfig', error: 42 })

    const [fromString, fromObject, fromNumber] = takeFailureEvents()
    expect(fromString.attributes.msg).toBe('Unexpected token <')
    expect(fromString.attributes.errName).toBeUndefined()
    for (const e of [fromObject, fromNumber]) {
      expect(e.attributes).not.toHaveProperty('msg')
      expect(e.attributes).not.toHaveProperty('errName')
      expect(e.attributes).not.toHaveProperty('stack')
    }
  })

  it('flushes the first failure of the session and fatal ones, and batches the rest', () => {
    logFailure(http503)
    logFailure({ code: 'config.fetch.http', component: 'remoteConfig' })
    logFailure({ code: 'bridge.native_view.missing', component: 'bridge', severity: 'fatal' })

    expect(takeRecordedFailures().map((r) => [r.event.action, r.event.attributes.seq, r.flushed])).toEqual([
      ['listings.fetch.http', '1', true],
      ['config.fetch.http', '2', false],
      ['bridge.native_view.missing', '3', true],
    ])
  })

  it('keeps the gate state between calls: a repeat inside a minute is folded into the next one', () => {
    let t = NOW
    setFailureContext({ now: () => t })

    logFailure(http503)
    t += 30_000
    logFailure(http503)
    t += 60_000
    logFailure(http503)

    expect(takeFailureEvents().map((e) => [e.attributes.seq, e.attributes.repeat])).toEqual([
      ['1', '1'],
      ['2', '2'],
    ])
  })

  it('normalizes values a JS caller gets wrong', () => {
    logFailure({ code: 'Listings.Fetch.HTTP', component: 'Listings', severity: 'critical' } as unknown as LogFailureInput)

    expect(takeFailureEvents()[0]).toMatchObject({
      action: 'client.code.invalid',
      label: 'unknown',
      attributes: { severity: 'error' },
    })
  })

  it('builds events the client-failure-event schema accepts', () => {
    setFailureContext({ partnerCode: 'weatherbug', wrapper: 'react-native' })
    logFailure({ ...http503, error: new Error('boom') })

    const check = validate('client-failure-event', takeFailureEvents()[0])
    expect(check.ok, check.text).toBe(true)
  })
})

describe('logFailure kill switches', () => {
  beforeEach(fixedDeps)

  it.each([
    ['EVENTS_ENABLED false', { eventsEnabled: false }],
    ['EVENTS_ENABLED "off"', { eventsEnabled: ' OFF ' }],
    ['FAILURES_ENABLED false', { failuresEnabled: false }],
    ['FAILURES_ENABLED 0', { failuresEnabled: 0 }],
    ['FAILURES_SAMPLE_RATE 0', { failuresSampleRate: 0 }],
  ])('%s drops the failure', (_name, flags) => {
    setFailureContext(flags)

    logFailure(http503)

    expect(takeFailureEvents()).toEqual([])
  })

  it('lets a fatal failure through sampling, but not through a kill switch', () => {
    setFailureContext({ failuresSampleRate: '0' })
    logFailure({ ...http503, severity: 'fatal' })
    expect(takeFailureEvents()).toHaveLength(1)

    setFailureContext({ failuresEnabled: 'no' })
    logFailure({ ...http503, code: 'config.fetch.http', severity: 'fatal' })
    expect(takeFailureEvents()).toEqual([])
  })

  it('reports while the flags are unset (before the remote config loads)', () => {
    setFailureContext({ eventsEnabled: undefined, failuresEnabled: undefined, failuresSampleRate: undefined })

    logFailure(http503)

    expect(takeFailureEvents()).toHaveLength(1)
  })

  it('applies a sample rate from the moment it is set', () => {
    // fnv1a32('uid-d:failures') / 2^32 is about 0.519 (contracts golden unit table).
    setFailureContext({ uid: () => 'uid-d', failuresSampleRate: 0.5 })
    logFailure(http503)
    expect(takeFailureEvents()).toEqual([])

    setFailureContext({ failuresSampleRate: 0.6 })
    logFailure(http503)
    expect(takeFailureEvents()).toHaveLength(1)
  })
})

describe('strictestFailureFlags', () => {
  it.each([
    [{}, {}, { eventsEnabled: true, failuresEnabled: true, failuresSampleRate: 1 }],
    [{ eventsEnabled: 'off' }, { eventsEnabled: true }, { eventsEnabled: false, failuresEnabled: true, failuresSampleRate: 1 }],
    [{ failuresEnabled: true }, { failuresEnabled: 0 }, { eventsEnabled: true, failuresEnabled: false, failuresSampleRate: 1 }],
    [{ failuresSampleRate: '0.25' }, { failuresSampleRate: 0.75 }, { eventsEnabled: true, failuresEnabled: true, failuresSampleRate: 0.25 }],
    [{ failuresSampleRate: 0.75 }, { failuresSampleRate: '50%' }, { eventsEnabled: true, failuresEnabled: true, failuresSampleRate: 0.75 }],
    [{ eventsEnabled: {} }, { failuresSampleRate: -2 }, { eventsEnabled: true, failuresEnabled: true, failuresSampleRate: 0 }],
  ])('combines %j and %j into %j', (a, b, expected) => {
    expect(strictestFailureFlags(a, b)).toEqual(expected)
    expect(strictestFailureFlags(b, a)).toEqual(expected)
  })
})

describe('logFailuresWithFlags', () => {
  beforeEach(fixedDeps)

  it('reports each input under the given flags', () => {
    logFailuresWithFlags({ failuresEnabled: 'on' }, [http503, { ...http503, code: 'config.fetch.http' }])

    expect(takeFailureEvents().map((e) => e.action)).toEqual(['listings.fetch.http', 'config.fetch.http'])
  })

  it.each([
    [{ eventsEnabled: false }],
    [{ failuresEnabled: 'no' }],
    [{ failuresSampleRate: 0 }],
  ])('drops them under %j, and the next report goes out as before', (flags) => {
    logFailuresWithFlags(flags, [http503])
    expect(takeFailureEvents()).toEqual([])

    logFailure(http503)
    expect(takeFailureEvents().map((e) => e.action)).toEqual(['listings.fetch.http'])
  })

  it('drops them while the context is off, even under flags that are on, and leaves it off', () => {
    setFailureContext({ failuresEnabled: false })

    logFailuresWithFlags({ eventsEnabled: true, failuresEnabled: true, failuresSampleRate: 1 }, [http503])
    logFailure({ ...http503, code: 'config.fetch.http' })

    expect(takeFailureEvents()).toEqual([])
  })

  it('samples them at the lower rate, and puts the context rate back', () => {
    // fnv1a32('uid-d:failures') / 2^32 is about 0.519 (contracts golden unit table).
    setFailureContext({ uid: () => 'uid-d', failuresSampleRate: 0.6 })
    logFailuresWithFlags({ failuresSampleRate: 0.5 }, [http503])
    expect(takeFailureEvents()).toEqual([])

    logFailure(http503)
    expect(takeFailureEvents()).toHaveLength(1)
  })

  it('keeps context changes a report makes that are not the flags', () => {
    const sink: FailureSink = {
      push: (event) => {
        recordingSink.push(event)
        setFailureContext({ partnerCode: 'set-by-sink' })
      },
      flushNow: () => recordingSink.flushNow(),
    }
    setFailureContext({ sink })

    logFailuresWithFlags({ failuresEnabled: true }, [http503])
    logFailure({ ...http503, code: 'config.fetch.http' })

    expect(takeFailureEvents().map((e) => [e.action, e.attributes.code])).toEqual([
      ['listings.fetch.http', 'unknown'],
      ['config.fetch.http', 'set-by-sink'],
    ])
  })

  it('does nothing with no inputs', () => {
    logFailuresWithFlags({ failuresEnabled: false }, [])
    logFailure(http503)

    expect(takeFailureEvents()).toHaveLength(1)
  })
})

describe('logFailure debug echo', () => {
  beforeEach(fixedDeps)

  it('prints nothing while debug is off, on any path', () => {
    const log = vi.spyOn(console, 'log').mockImplementation(() => undefined)
    const others = (['error', 'warn', 'info', 'debug', 'trace'] as const).map((m) =>
      vi.spyOn(console, m).mockImplementation(() => undefined),
    )

    logFailure(http503)
    setFailureContext({ eventsEnabled: false })
    logFailure(http503)
    setFailureContext({ eventsEnabled: true, now: () => { throw new Error('clock') } })
    logFailure(http503)

    expect(log).not.toHaveBeenCalled()
    for (const spy of others) expect(spy).not.toHaveBeenCalled()
    expect(takeFailureEvents()).toHaveLength(1)
    expect(getFailureInternalErrors()).toBe(1)
  })

  it('prints one line per call when debug is on, with the sanitized message and the gate result', () => {
    const log = vi.spyOn(console, 'log').mockImplementation(() => undefined)
    setFailureContext({ debug: true })

    logFailure({ ...http503, message: 'HTTP 503 for jane@example.com' })
    logFailure({ ...http503, message: 'HTTP 503 for jane@example.com' })
    logFailure({ code: 'config.fetch.network', component: 'remoteConfig', severity: 'warn' })

    expect(log.mock.calls).toEqual([
      ['[Sellwild] failure listings.fetch.http listings error sent HTTP 503 for <email>'],
      ['[Sellwild] failure listings.fetch.http listings error deduped HTTP 503 for <email>'],
      ['[Sellwild] failure config.fetch.network remoteConfig warn sent'],
    ])
    expect(takeFailureEvents()).toHaveLength(2)
  })

  it('echoes a dropped failure with the kill switch that dropped it', () => {
    const log = vi.spyOn(console, 'log').mockImplementation(() => undefined)
    setFailureContext({ debug: true, failuresEnabled: false })

    logFailure(http503)

    expect(log).toHaveBeenCalledExactlyOnceWith('[Sellwild] failure listings.fetch.http listings error failures_disabled HTTP 503')
    expect(takeFailureEvents()).toEqual([])
  })

  it('echoes its own internal error by name only', () => {
    const log = vi.spyOn(console, 'log').mockImplementation(() => undefined)
    setFailureContext({ debug: true, uid: () => { throw new RangeError('secret detail') } })

    logFailure(http503)
    setFailureContext({ uid: () => { throw 'a string' } })
    logFailure(http503)

    expect(log.mock.calls).toEqual([
      ['[Sellwild] failure internal-error RangeError'],
      ['[Sellwild] failure internal-error string'],
    ])
    expect(getFailureInternalErrors()).toBe(2)
  })

  it('turns debug on only for true through setFailureContext too', () => {
    for (const debug of ['yes', 1, {}]) {
      setFailureContext({ debug: debug as never })
      expect(isDebugLogging(), JSON.stringify(debug)).toBe(false)
    }
    setFailureContext({ debug: true })
    expect(isDebugLogging()).toBe(true)
    setFailureContext({ debug: false })
    expect(isDebugLogging()).toBe(false)
  })

  it('shares its switch with debugLog, and only true turns it on', () => {
    const log = vi.spyOn(console, 'log').mockImplementation(() => undefined)

    debugLog('off')
    setFailureContext({ debug: true })
    expect(isDebugLogging()).toBe(true)
    debugLog('trace', { zone: 43 })
    setDebugLogging('yes' as unknown as boolean)
    debugLog('off again')
    setFailureContext({ debug: true })
    setFailureContext({ debug: undefined })
    debugLog('reset by undefined')

    expect(log.mock.calls).toEqual([['[Sellwild]', 'trace', { zone: 43 }]])
    expect(isDebugLogging()).toBe(false)
  })

  it('keeps debug when an update does not name it', () => {
    setFailureContext({ debug: true })
    setFailureContext({ partnerCode: 'p' })
    expect(isDebugLogging()).toBe(true)
  })
})

describe('logFailure never throws', () => {
  beforeEach(fixedDeps)

  function circular(): Record<string, unknown> {
    const o: Record<string, unknown> = { name: 'loop' }
    o.self = o
    return o
  }

  function throwingGetters<T extends object>(target: T, keys: string[]): T {
    for (const key of keys) {
      Object.defineProperty(target, key, { get: () => { throw new Error(`getter ${key}`) } })
    }
    return target
  }

  const hostileProxy = new Proxy({}, {
    get: () => { throw new Error('trap get') },
    getPrototypeOf: () => { throw new Error('trap getPrototypeOf') },
    has: () => { throw new Error('trap has') },
  })

  it.each([
    ['null', null],
    ['undefined', undefined],
    ['a string', 'listings.fetch.http'],
    ['a number', 7],
    ['a circular object', circular()],
    ['circular fields', { code: 'listings.fetch.http', component: 'listings', error: circular(), message: circular(), zoneId: circular(), url: circular() }],
    ['a proxy that throws on every read', hostileProxy],
    ['throwing getters', throwingGetters({}, ['code', 'component', 'severity', 'error', 'message', 'httpStatus', 'url', 'zoneId'])],
    ['an Error with throwing getters', { code: 'listings.fetch.network', component: 'listings', error: throwingGetters(new Error('x'), ['name', 'message', 'stack']) }],
    ['a proxy as the error', { code: 'listings.fetch.network', component: 'listings', error: hostileProxy }],
  ])('with %s as input', (_name, input) => {
    expect(() => logFailure(input as unknown as LogFailureInput)).not.toThrow()
    for (const event of takeFailureEvents()) {
      const check = validate('client-failure-event', event)
      expect(check.ok, check.text).toBe(true)
    }
  })

  it('cuts long text before sanitizing it, so a huge message cannot stall the thread', () => {
    // Unbounded, the sanitizer takes about a minute on this message.
    const huge = 'x'.repeat(100_000)
    const error = new Error(huge)
    error.stack = `Error: ${huge}\n${'at f (a.js:1:1)\n'.repeat(10_000)}`
    const started = performance.now()

    logFailure({ code: 'listings.fetch.http', component: 'listings', message: huge, error })

    expect(performance.now() - started).toBeLessThan(1000)
    const [event] = takeFailureEvents()
    expect(event.attributes.msg).toBe('x'.repeat(199) + '…')
    // The V8 header repeats the huge message; it is dropped before the cut, so frames survive.
    expect(event.attributes.stack).toBe(Array(5).fill('at f (a.js:1:1)').join('\n'))
    logFailure({ code: 'config.fetch.parse', component: 'remoteConfig', error: huge })
    expect(takeFailureEvents()[0].attributes.msg).toBe('x'.repeat(199) + '…')
  })

  it('still reports the failure when some fields cannot be read', () => {
    const before = getFailureInternalErrors()

    logFailure(throwingGetters({ code: 'listings.fetch.http', component: 'listings' }, ['message', 'url']) as LogFailureInput)

    expect(takeFailureEvents()).toMatchObject([{ action: 'listings.fetch.http', label: 'listings' }])
    expect(getFailureInternalErrors() - before).toBe(2)
  })

  it.each<[string, Partial<Record<'uid' | 'now', () => never>> | { sink: FailureSink }]>([
    ['the uid provider throws', { uid: () => { throw new Error('uid') } }],
    ['the clock throws', { now: () => { throw new Error('clock') } }],
    ['the sink push throws', { sink: { push: () => { throw new Error('push') }, flushNow: () => undefined } }],
    ['the sink flush throws', { sink: { push: () => undefined, flushNow: () => { throw new Error('flush') } } }],
  ])('counts an internal error when %s', (_name, deps) => {
    setFailureContext(deps)

    expect(() => logFailure(http503)).not.toThrow()

    expect(getFailureInternalErrors()).toBe(1)
  })

  it('does not throw when the debug echo itself cannot print', () => {
    vi.spyOn(console, 'log').mockImplementation(() => { throw new Error('console gone') })
    setFailureContext({ debug: true })

    expect(() => logFailure(http503)).not.toThrow()
    setFailureContext({ uid: () => { throw new Error('uid') } })
    expect(() => logFailure(http503)).not.toThrow()

    // Each call: the echo (or the uid) throws before the push, and then the
    // internal-error echo throws too.
    expect(takeFailureEvents()).toEqual([])
    expect(getFailureInternalErrors()).toBe(4)
  })
})

describe('logFailure reentrancy', () => {
  beforeEach(fixedDeps)

  it('ignores a nested call from the sink and keeps working after it', () => {
    const pushed: ClientFailureEvent[] = []
    setFailureContext({
      sink: {
        push(event) {
          pushed.push(event)
          logFailure({ code: 'config.fetch.network', component: 'remoteConfig' })
        },
        flushNow: () => undefined,
      },
    })

    logFailure(http503)
    logFailure({ code: 'config.fetch.http', component: 'remoteConfig' })

    expect(pushed.map((e) => [e.action, e.attributes.seq])).toEqual([
      ['listings.fetch.http', '1'],
      ['config.fetch.http', '2'],
    ])
  })

  it('ignores a nested call from the clock, even when the outer call then fails', () => {
    setFailureContext({
      now: () => {
        logFailure({ code: 'config.fetch.network', component: 'remoteConfig' })
        throw new Error('clock')
      },
    })

    logFailure(http503)
    setFailureContext({ now: () => NOW })
    logFailure({ code: 'config.fetch.http', component: 'remoteConfig' })

    expect(takeFailureEvents().map((e) => e.action)).toEqual(['config.fetch.http'])
    expect(getFailureInternalErrors()).toBe(1)
  })
})

describe('resetFailuresForTests', () => {
  it('clears the gate state, the internal error count, debug and the context', () => {
    const log = vi.spyOn(console, 'log').mockImplementation(() => undefined)
    fixedDeps()
    setFailureContext({ partnerCode: 'weatherbug', debug: true, eventsEnabled: false })
    setFailureContext({ uid: () => { throw new Error('uid') } })
    logFailure(http503)
    expect(getFailureInternalErrors()).toBe(1)
    expect(log).toHaveBeenCalledExactlyOnceWith('[Sellwild] failure internal-error Error')

    resetFailuresForTests()
    expect(getFailureInternalErrors()).toBe(0)
    expect(isDebugLogging()).toBe(false)

    setFailureContext({ sink: recordingSink, now: () => NOW, uid: () => UID })
    logFailure(http503)
    expect(takeFailureEvents()).toMatchObject([{ attributes: { code: 'unknown', seq: '1' } }])
  })
})

describe('logFailure through the shared events queue', () => {
  it('pushes into eventQueue and flushes the first failure to the events endpoint', async () => {
    resetFailures()
    setFailureContext({ sink: undefined, partnerCode: 'weatherbug' })
    const fetchMock = vi.fn(async (_url: string, _init: RequestInit) => new Response(null, { status: 204 }))
    vi.stubGlobal('fetch', fetchMock)

    logFailure(http503)

    expect(fetchMock).toHaveBeenCalledOnce()
    const [url, init] = fetchMock.mock.calls[0]
    expect(url).toBe(EVENTS_URL)
    const body = JSON.parse(String(init.body)) as unknown[]
    expect(body).toMatchObject([
      {
        event: 'clientFailure',
        action: 'listings.fetch.http',
        attributes: { code: 'weatherbug', client: 'core', sdkVersion: SDK_VERSION, seq: '1' },
        uid: eventQueue.getUid(),
      },
    ])
    const check = validate('events-batch', body)
    expect(check.ok, check.text).toBe(true)
    await Promise.resolve()
  })
})

// FAILURES.md 3.3 item 4: the shell cuts message and errMessage to 1000
// UTF-16 units and the stack to 2000 before the pure core.
describe('logFailure input cap', () => {
  beforeEach(fixedDeps)

  it('hands the core only the first 1000 units of message and error message', () => {
    // 998 digits sanitize to "<n>", so whatever follows them would be sent.
    const long = `${'1'.repeat(998)}ABCDEFG`

    logFailure({ code: 'listings.fetch.http', component: 'listings', message: long, error: new Error(long) })
    logFailure({ code: 'config.fetch.parse', component: 'remoteConfig', error: long })

    const [fromError, fromString] = takeFailureEvents()
    expect(fromError.attributes.msg).toBe('<n>AB')
    expect(fromString.attributes.msg).toBe('<n>AB')
  })

  it('turns a surrogate pair split by the cut into U+FFFD, as every platform does', () => {
    logFailure({ code: 'listings.fetch.http', component: 'listings', message: `${'1'.repeat(999)}😀tail` })

    expect(takeFailureEvents()[0].attributes.msg).toBe('<n>�')
  })

  it('cuts at exactly 1000 units', () => {
    logFailure({ code: 'listings.fetch.http', component: 'listings', message: `${'1'.repeat(996)}WXYZ` })
    logFailure({ code: 'listings.fetch.http', component: 'listings', message: `${'1'.repeat(997)}WXYZ` })

    expect(takeFailureEvents().map((e) => e.attributes.msg)).toEqual(['<n>WXYZ', '<n>WXY'])
  })

  it('keeps the frames when a long error message fills the V8 header', () => {
    const message = 'm'.repeat(2418)
    const error = new Error(message)
    error.stack = `Error: ${message}\n    at mk (a.js:4:25)\n    at run (b.js:6:13)`

    logFailure({ code: 'listings.fetch.network', component: 'listings', error })

    expect(takeFailureEvents()[0].attributes.stack).toBe('at mk (a.js:4:25)\nat run (b.js:6:13)')
  })

  it('leaves a stack under the cap to the pure core, header and all', () => {
    const error = new TypeError('bad')
    error.stack = 'TypeError: bad\n    at mk (a.js:4:25)'

    logFailure({ code: 'listings.fetch.network', component: 'listings', error })

    expect(takeFailureEvents()[0].attributes).toMatchObject({ errName: 'TypeError', msg: 'bad', stack: 'at mk (a.js:4:25)' })
  })

  // A two-line message makes a two-line V8 header. The pure core drops only
  // its first line; the shell drops all of it, but only over the cap.
  it('leaves a stack of exactly 2000 units to the pure core, and strips the header from one of 2001', () => {
    const frame = '\n    at mk (a.js:4:25)'
    const stackFor = (padding: number) => {
      const error = new Error(`${'m'.repeat(padding)}\nsecond`)
      error.stack = `Error: ${error.message}${frame}`
      return error
    }
    const atCap = stackFor(1964)
    const overCap = stackFor(1965)
    expect([atCap.stack!.length, overCap.stack!.length]).toEqual([2000, 2001])

    logFailure({ code: 'listings.fetch.network', component: 'listings', error: atCap })
    logFailure({ code: 'config.fetch.network', component: 'remoteConfig', error: overCap })

    expect(takeFailureEvents().map((e) => e.attributes.stack)).toEqual(['second\nat mk (a.js:4:25)', 'at mk (a.js:4:25)'])
  })

  it('drops a header that is the name alone when the message is empty', () => {
    const error = new Error('')
    error.name = 'E'.repeat(2100)
    error.stack = `${error.name}\n    at mk (a.js:4:25)`

    logFailure({ code: 'listings.fetch.network', component: 'listings', error })

    const { attributes } = takeFailureEvents()[0]
    expect(attributes.stack).toBe('at mk (a.js:4:25)')
    // The shell passes the name through uncut; the pure core cuts it to 64 code points.
    expect(attributes.errName).toBe(`${'E'.repeat(63)}…`)
  })

  it('sends no stack when it is nothing but an over-long header', () => {
    const message = 'm'.repeat(2500)
    const error = new Error(message)
    error.stack = `Error: ${message}`

    logFailure({ code: 'listings.fetch.network', component: 'listings', error })

    const [event] = takeFailureEvents()
    expect(event.attributes.stack).toBeUndefined()
    expect(event.attributes.msg).toBe(`${'m'.repeat(199)}…`)
  })

  it('does not strip text that only starts like the header', () => {
    const message = 'm'.repeat(2418)
    const error = new Error(message)
    error.stack = `Error: ${message}zzz\n    at mk (a.js:4:25)`

    logFailure({ code: 'listings.fetch.network', component: 'listings', error })

    // Cut as is: the frame is past 2000 units, and the core drops the header line.
    expect(takeFailureEvents()[0].attributes.stack).toBeUndefined()
  })

  it('still cuts the stack when the error name is not text', () => {
    const error = new Error('x')
    Object.defineProperty(error, 'name', { value: 42 })
    error.stack = `${' '.repeat(1995)}\na (x.js:1:1)`

    logFailure({ code: 'listings.fetch.network', component: 'listings', error })

    expect(takeFailureEvents()[0].attributes.stack).toBe('a (x')
  })

  it('cuts a stack with no V8 header (JSC, Hermes) at exactly 2000 units', () => {
    const error = new Error('x')
    // The blank first line is dropped by the core; 4 units of the frame fit.
    error.stack = `${' '.repeat(1995)}\na (x.js:1:1)`

    logFailure({ code: 'listings.fetch.network', component: 'listings', error })

    expect(takeFailureEvents()[0].attributes.stack).toBe('a (x')
  })
})
