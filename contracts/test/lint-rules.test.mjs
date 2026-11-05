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
      reportOnly('try { a() } catch (e) { failures.logFailure(e) }', { reporters: ['failures.logFailure'] }),
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
      // ...passed to a call (such as collecting it for the caller), thrown, or an arrow handler's value.
      reportOnly("function f (issues) { try { a() } catch { issues.push({ code: 'config.fetch.parse', severity: 'warn' }) } }"),
      reportOnly("try { a() } catch { throw new SellwildError('listings.fetch.network') }"),
      reportOnly("function f () { try { a() } catch { if (x) return y ? 'listings.fetch.network' : 'listings.fetch.http' } }"),
      reportOnly("p.catch(() => ({ code: 'listings.fetch.network' }))"),
      reportOnly("try { a() } catch { queueMicrotask(() => issue('listings.fetch.network')) }"),
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
    ],
    invalid: [
      unreported('try { a() } catch (e) { fallback() }'),
      unreported('try { a() } catch (e) { console.error(e) }'),
      unreported('try { a() } catch (e) { logFailureLater(e) }'),
      unreported('try { a() } catch (e) { report(e) }', 'catch', { reporters: ['logFailure', 'failed'] }),
      unreported('try { a() } catch (e) { other.log(e) }', 'catch', { reporters: ['SellwildFailures.log'] }),
      // W12: a reporter name matches the whole callee, so any method of that name is not one.
      unreported('const o = { report: () => undefined }; try { a() } catch (e) { o.report(e) }', 'catch', { reporters: ['report'] }),
      unreported('try { a() } catch (e) { failures.logFailure(e) }'),
      unreported('try { a() } catch (e) { this.report(e) }', 'catch', { reporters: ['report'] }),
      unreported('try { a() } catch (e) { x.SellwildFailures.log(e) }', 'catch', { reporters: ['SellwildFailures.log'] }),
      // A throw inside a nested function does not propagate this failure.
      unreported('try { a() } catch (e) { setTimeout(() => { throw e }) }'),
      // Strings that are not registry codes.
      unreported("function f () { try { a() } catch { return 'not a code' } }"),
      unreported("function f () { try { a() } catch { return 'listings.fetch' } }"),
      unreported("function f () { try { a() } catch { return 'Listings.fetch.network' } }"),
      unreported('function f () { try { a() } catch { return `listings.fetch.${reason}` } }'),
      unreported(`function f () { try { a() } catch { return '${'a'.repeat(40)}.${'b'.repeat(20)}.network' } }`),
      unreported("function f () { try { a() } catch { return { code: 'config.fetch.parse' } } }", 'catch', { codes: ['config.fetch.network'] }),
      // TE2: a registry code that goes nowhere: stored, assigned, or returned by a nested function.
      unreported("try { JSON.parse('1') } catch { const _c = 'listings.fetch.network' }"),
      unreported("let last; try { a() } catch { last = 'listings.fetch.network' }"),
      unreported("function f () { try { a() } catch { const issue = { code: 'listings.fetch.network' }; return fallback } }"),
      unreported("try { a() } catch { list.map(() => { return 'listings.fetch.network' }) }"),
      unreported("try { a() } catch { list.map(() => 'listings.fetch.network') }"),
      unreported("try { a() } catch { if ('listings.fetch.network') b() }"),
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
    ],
  })

  it('has no whole-function exemption: exemptFunctions is not an option', () => {
    const linter = new Linter({ configType: 'flat' })
    const config = [{ plugins: { sellwild: plugin }, rules: { 'sellwild/catch-reports-failure': ['error', { exemptFunctions: ['flush'] }] } }]
    assert.throws(() => linter.verify('x()', config), /exemptFunctions|should NOT have additional properties|must NOT have additional properties/)
  })

  it('TR6: an exempt catch is exempt on its own line only, so a second catch in the same function is still checked', () => {
    const linter = new Linter({ configType: 'flat' })
    const config = [{
      plugins: { sellwild: plugin },
      linterOptions: { reportUnusedDisableDirectives: 'error' },
      rules: { 'sellwild/catch-reports-failure': 'error', 'sellwild/disable-reason': 'error' },
    }]
    const code = [
      'function useListings () {',
      '  load()',
      '    // eslint-disable-next-line sellwild/catch-reports-failure -- FAILURES.md 9.2: core already logged it',
      '    .catch((err) => setError(err))',
      '  try { refresh() } catch { setLoading(false) }',
      '}',
    ].join('\n')
    assert.deepEqual(linter.verify(code, config).map((m) => `${m.line}:${m.ruleId}`), ['5:sellwild/catch-reports-failure'])
  })
})

describe('sellwild/no-global-console', () => {
  const globalConsole = (code, object) => ({ code, errors: [{ messageId: 'globalConsole', data: { object } }] })
  tester.run('no-global-console', plugin.rules['no-global-console'], {
    valid: [
      'logger.console.log(1)',
      'const c = window.document',
      'function f (self) { self.console.log(1) }',
      'const window = { console: 1 }; window.console',
      'globalThis[name].log(1)',
      'const { document } = window',
      'console.log(1)',
    ],
    invalid: [
      globalConsole("globalThis.console.error('x')", 'globalThis'),
      globalConsole('window.console.log(1)', 'window'),
      globalConsole('self.console.warn(1)', 'self'),
      globalConsole('global.console.info(1)', 'global'),
      globalConsole("globalThis['console'].error('x')", 'globalThis'),
      globalConsole('window?.console?.log(1)', 'window'),
      globalConsole('const c = window.console; c.log(1)', 'window'),
      globalConsole('window.self.console.log(1)', 'window.self'),
      globalConsole('const { console: c } = globalThis', 'globalThis'),
      globalConsole('let c; ({ console: c } = self)', 'self'),
    ],
  })
})

describe('sellwild/disable-reason', () => {
  // Linter, not RuleTester: a directive names other rules, which must exist.
  const linter = new Linter({ configType: 'flat' })
  const config = [{
    plugins: { sellwild: plugin },
    rules: { 'sellwild/disable-reason': 'error', 'sellwild/catch-reports-failure': 'error', 'sellwild/no-silent-catch': 'error', 'sellwild/no-global-console': 'error', 'no-eval': 'error', 'no-console': 'error' },
  }]
  const found = (code) => linter.verify(code, config).filter((m) => m.ruleId === 'sellwild/disable-reason').map((m) => `${m.line}:${m.message}`)
  const missing = (rules) => `This comment turns off ${rules} without a reason. Add " -- FAILURES.md <section>: <why>" (the section that allows this exception), or fix the code.`
  const uncited = 'The reason must cite the FAILURES.md section that allows this exception, such as "FAILURES.md 8.4".'

  it('passes a sellwild/* exception that says why and cites FAILURES.md, and directives for other rules', () => {
    for (const code of [
      '// eslint-disable-next-line sellwild/catch-reports-failure -- FAILURES.md 8.4: transport never reports itself\ntry { a() } catch (e) { b() }',
      '/* eslint-disable sellwild/no-silent-catch -- contracts/vendor/FAILURES.md 1.3 does not apply to fixtures */\ntry { a() } catch {}',
      'try { a() } catch (e) { b() } // eslint-disable-line sellwild/catch-reports-failure --- FAILURES.md 9.2 log once',
      '// eslint-disable-next-line no-eval\neval(x)',
      '/* eslint no-console: off */',
      '/* eslint sellwild/no-silent-catch: error -- FAILURES.md 1.3 on again */ x()',
      '// eslint is not a directive here',
    ]) assert.deepEqual(found(code), [], code)
  })

  it('fails a sellwild/* exception with no reason, or one that cites no FAILURES.md section', () => {
    assert.deepEqual(found('// eslint-disable-next-line sellwild/catch-reports-failure\ntry { a() } catch (e) { b() }'), [`1:${missing('sellwild/catch-reports-failure')}`])
    assert.deepEqual(found('try { a() } catch {} // eslint-disable-line sellwild/no-silent-catch, no-empty'), [`1:${missing('sellwild/no-silent-catch')}`])
    assert.deepEqual(found('x()\n/* eslint-disable sellwild/no-global-console */\nwindow.console.log(1)'), [`2:${missing('sellwild/no-global-console')}`])
    assert.deepEqual(found('x()\n/* eslint sellwild/catch-reports-failure: off */'), [`2:${missing('sellwild/catch-reports-failure')}`])
    assert.deepEqual(found('// eslint-disable-next-line sellwild/catch-reports-failure -- \ntry { a() } catch (e) { b() }'), [`1:${missing('sellwild/catch-reports-failure')}`])
    assert.deepEqual(found('// eslint-disable-next-line sellwild/catch-reports-failure -- it is fine\ntry { a() } catch (e) { b() }'), [`1:${uncited}`])
    assert.deepEqual(found('// eslint-disable-next-line sellwild/catch-reports-failure -- see FAILURES.md\ntry { a() } catch (e) { b() }'), [`1:${uncited}`])
  })

  it('fails a next-line disable of every rule', () => {
    assert.deepEqual(found('// eslint-disable-next-line\ntry { a() } catch (e) { b() }'), [`1:${missing('every rule')}`])
  })

  it('cannot see a blanket eslint-disable or eslint-disable-line, which turns it off too (the config tests scan for those)', () => {
    assert.deepEqual(found('/* eslint-disable */\ntry { a() } catch (e) { b() }'), [])
    assert.deepEqual(found('try { a() } catch (e) { b() } // eslint-disable-line'), [])
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

  it('has the four house rules', () => {
    assert.deepEqual(Object.keys(plugin.rules), ['no-silent-catch', 'catch-reports-failure', 'no-global-console', 'disable-reason'])
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
