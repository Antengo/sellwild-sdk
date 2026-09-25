// Unit tests for the house failure lint rules (lint/eslint-plugin-sellwild.mjs).
// The rules only look at CatchClause, CallExpression, ThrowStatement and
// literals, which are the same nodes in TypeScript, so espree covers them.

import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import { Linter, RuleTester } from 'eslint'
import plugin, { FAILURE_CODE_FORMAT } from '../lint/eslint-plugin-sellwild.mjs'

RuleTester.describe = describe
RuleTester.it = it
RuleTester.itOnly = it.only

const tester = new RuleTester({ languageOptions: { ecmaVersion: 'latest', sourceType: 'module' } })

describe('sellwild/no-silent-catch', () => {
  tester.run('no-silent-catch', plugin.rules['no-silent-catch'], {
    valid: [
      "try { a() } catch (e) { logFailure({ code: 'listings.fetch.network', component: 'listings', error: e }) }",
      'try { a() } catch { b() }',
      'try { a() } finally { b() }',
      'p.catch((e) => logFailure(e))',
      'p.catch((e) => fallback)',
      'p.catch(handle)',
      'p.then(() => {})',
      "p['catch'](() => {})",
    ],
    invalid: [
      { code: 'try { a() } catch {}', errors: [{ messageId: 'emptyCatch' }] },
      { code: 'try { a() } catch (e) { }', errors: [{ messageId: 'emptyCatch' }] },
      { code: 'try { a() } catch (e) { /* ignore */ }', errors: [{ messageId: 'emptyCatch' }] },
      { code: 'try { a() } catch (e) {\n  // expected\n}', errors: [{ messageId: 'emptyCatch', line: 1 }] },
      { code: 'try { a() } catch (e) { ; }', errors: [{ messageId: 'emptyCatch' }] },
      { code: 'try { a() } catch (e) { try { b() } catch {} }', errors: [{ messageId: 'emptyCatch', column: 37 }] },
      { code: 'p.catch(() => {})', errors: [{ messageId: 'swallow' }] },
      { code: 'p.catch((e) => { /* nothing */ })', errors: [{ messageId: 'swallow' }] },
      { code: 'p.catch(function () {})', errors: [{ messageId: 'swallow' }] },
      { code: 'p.catch(() => undefined)', errors: [{ messageId: 'swallow' }] },
      { code: 'p.catch(() => null)', errors: [{ messageId: 'swallow' }] },
      { code: 'p.catch(() => void 0)', errors: [{ messageId: 'swallow' }] },
      { code: 'p?.catch(() => {})', errors: [{ messageId: 'swallow' }] },
      { code: 'fetch(u).then(r => r.json()).catch(() => {})', errors: [{ messageId: 'swallow' }] },
    ],
  })
})

const reportOnly = (code, options) => ({ code, options: options ? [options] : [] })
const unreported = (code, what = 'catch', options) => ({
  code,
  options: options ? [options] : [],
  errors: [{ messageId: 'unreported', data: { what, reporters: (options?.reporters ?? ['logFailure']).join(' or ') } }],
})

describe('sellwild/catch-reports-failure', () => {
  tester.run('catch-reports-failure', plugin.rules['catch-reports-failure'], {
    valid: [
      // 1. A reporter call, direct, through an object, optional, or conditional.
      reportOnly("try { a() } catch (error) { logFailure({ code: 'listings.fetch.network', component: 'listings', error }) }"),
      reportOnly('try { a() } catch (e) { failures.logFailure(e) }'),
      reportOnly('try { a() } catch (e) { logFailure?.(e) }'),
      reportOnly('try { a() } catch (e) { if (!aborted()) report(e) }', { reporters: ['report'] }),
      reportOnly("function f () { try { a() } catch (error) { failed({ error }); return empty() } }", { reporters: ['logFailure', 'failed'] }),
      reportOnly('try { a() } catch (e) { SellwildFailures.log(e) }', { reporters: ['SellwildFailures.log'] }),
      reportOnly('try { a() } catch (e) { queueMicrotask(() => logFailure(e)) }'),
      // 2. Propagation.
      reportOnly('try { a() } catch (e) { cleanup(); throw e }'),
      reportOnly("function f () { try { a() } catch (e) { if (e.name === 'AbortError') return; throw new Error('x', { cause: e }) } }"),
      reportOnly('async function f () { try { await a() } catch (e) { return Promise.reject(e) } }'),
      // 3. A registry code handed to code that reports it.
      reportOnly("function f () { try { a() } catch (error) { return { issue: { code: 'localized.config.parse', error } } } }"),
      reportOnly("function f () { try { a() } catch (error) { return issue('growthcode.eid.parse', 'eid blob is not JSON') } }"),
      reportOnly('function f () { try { a() } catch (error) { return decoded(null, { code: `bridge.message.parse` }) } }'),
      reportOnly("function f () { try { a() } catch { return { code: 'config.fetch.parse' } } }", { codes: ['config.fetch.parse'] }),
      // 3. The caught error returned to the caller (a pure step's Result).
      reportOnly('function f () { try { a() } catch (error) { return { ok: false, error } } }'),
      reportOnly("function f () { try { a() } catch (error) { return Promise.resolve({ kind: 'network', error }) } }"),
      reportOnly("function f () { try { a() } catch (error) { return { issue: invalid('not JSON', errorName(error)) } } }"),
      reportOnly('function f () { try { a() } catch (e) { return { ok: false, cause: e } } }'),
      // Promise handlers.
      reportOnly('p.catch((error) => logFailure({ error }))'),
      reportOnly('p.catch((error) => { throw error })'),
      reportOnly('p.catch(handle)'),
      // Empty ones belong to no-silent-catch, so each is reported once.
      reportOnly('try { a() } catch {}'),
      reportOnly('p.catch(() => {})'),
      // Exempt functions: every catch below a function of that name.
      reportOnly('class EventQueue { flush () { this.fetch(u).catch(() => { this.requeue() }) } }', { exemptFunctions: ['flush'] }),
      reportOnly('const drainQueue = () => { try { send() } catch (e) { retry() } }', { exemptFunctions: ['drainQueue'] }),
      reportOnly('function getUid () { try { return localStorage.uid } catch { return random() } }', { exemptFunctions: ['getUid'] }),
      reportOnly('const q = { flush: function () { try { a() } catch (e) { b() } } }', { exemptFunctions: ['flush'] }),
      reportOnly('queue.flush = () => { try { a() } catch (e) { b() } }', { exemptFunctions: ['flush'] }),
      reportOnly('class Q { #uid = () => { try { a() } catch (e) { b() } } }', { exemptFunctions: ['uid'] }),
      reportOnly('function useListings () { useEffect(() => { load().catch((err) => setError(err)) }) }', { exemptFunctions: ['useListings'] }),
    ],
    invalid: [
      unreported('try { a() } catch (e) { fallback() }'),
      unreported('try { a() } catch (e) { console.error(e) }'),
      unreported('try { a() } catch (e) { logFailureLater(e) }'),
      unreported('try { a() } catch (e) { report(e) }', 'catch', { reporters: ['logFailure', 'failed'] }),
      unreported('try { a() } catch (e) { other.log(e) }', 'catch', { reporters: ['SellwildFailures.log'] }),
      // A throw inside a nested function does not propagate this failure.
      unreported('try { a() } catch (e) { setTimeout(() => { throw e }) }'),
      // Strings that are not registry codes.
      unreported("function f () { try { a() } catch { return 'not a code' } }"),
      unreported("function f () { try { a() } catch { return 'listings.fetch' } }"),
      unreported("function f () { try { a() } catch { return 'Listings.fetch.network' } }"),
      unreported('function f () { try { a() } catch { return `listings.fetch.${reason}` } }'),
      unreported(`function f () { try { a() } catch { return '${'a'.repeat(40)}.${'b'.repeat(20)}.network' } }`),
      unreported("function f () { try { a() } catch { return { code: 'config.fetch.parse' } } }", 'catch', { codes: ['config.fetch.network'] }),
      // A return that does not hold the caught error, or not from this catch.
      unreported('function f () { try { a() } catch (error) { return { ok: false } } }'),
      unreported('function f () { try { a() } catch (error) { return { ok: false, error: 1 } } }'),
      unreported('function f () { try { a() } catch (error) { return state.error } }'),
      unreported('function f () { try { a() } catch { return fallback } }'),
      unreported('function f () { try { a() } catch (e) { list.map(() => { return e }) } }'),
      // Promise handlers.
      unreported('p.catch((error) => ({ ok: false, error }))', '.catch handler'),
      unreported('p.catch((e) => fallback())', '.catch handler'),
      unreported('p.catch(function (e) { this.retry() })', '.catch handler'),
      // Exemptions are by function name, and only below that function.
      unreported('function other () { try { a() } catch (e) { b() } }', 'catch', { exemptFunctions: ['flush'] }),
      unreported('function flushLater () { try { a() } catch (e) { b() } }', 'catch', { exemptFunctions: ['flush'] }),
      unreported('try { a() } catch (e) { b() } function flush () {}', 'catch', { exemptFunctions: ['flush'] }),
    ],
  })
})

describe('eslint-plugin-sellwild', () => {
  it('matches the FAILURES.md 4.1 code format', () => {
    assert.ok(FAILURE_CODE_FORMAT.test('listings.fetch.network'))
    assert.ok(FAILURE_CODE_FORMAT.test('widget.host_callback.exception'))
    assert.ok(!FAILURE_CODE_FORMAT.test('listings.fetch'))
    assert.ok(!FAILURE_CODE_FORMAT.test('Listings.fetch.network'))
    assert.ok(!FAILURE_CODE_FORMAT.test('listings.fetch.network.extra'))
  })

  it('runs as a flat-config plugin and reports each empty catch once', () => {
    const linter = new Linter({ configType: 'flat' })
    const config = [{
      plugins: { sellwild: plugin },
      rules: { 'sellwild/no-silent-catch': 'error', 'sellwild/catch-reports-failure': 'error' },
    }]
    const code = 'try { a() } catch {}\ntry { a() } catch (e) { b() }\np.catch(() => null)\n'
    const found = linter.verify(code, config).map((m) => `${m.line}:${m.ruleId}`)
    assert.deepEqual(found, ['1:sellwild/no-silent-catch', '2:sellwild/catch-reports-failure', '3:sellwild/no-silent-catch'])
  })

  it('imports nothing, so a vendored copy needs no dependency', async () => {
    const fs = await import('node:fs')
    const source = fs.readFileSync(new URL('../lint/eslint-plugin-sellwild.mjs', import.meta.url), 'utf8')
    assert.doesNotMatch(source, /^\s*import\s/m)
    assert.doesNotMatch(source, /\brequire\(/)
  })
})
