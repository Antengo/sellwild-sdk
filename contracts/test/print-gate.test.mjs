import test from 'node:test'
import assert from 'node:assert/strict'
import { scanRepo, scanSource, stripComments, compare, readAllowlist, totalsByPlatform, PRINT_EXEMPT, SCAN_ROOTS } from '../scripts/print-gate.mjs'

test('gate: no file prints or swallows more than the allowlist records', () => {
  const results = scanRepo()
  const allowlist = readAllowlist()
  const { increases } = compare(results, allowlist)
  const report = increases.map((x) => `${x.file} ${x.kind}: allowed ${x.allowed}, found ${x.found}\n${x.hits.map((h) => `  line ${h.line}: ${h.text}`).join('\n')}`)
  assert.deepEqual(report, [])
  const totals = totalsByPlatform(results)
  process.stdout.write(`print gate totals ${JSON.stringify(totals)}\n`)
  assert.deepEqual(Object.keys(totals), SCAN_ROOTS.map((r) => r.platform))
})

test('gate: the exempt list is exactly the A2 debug-echo and debug-logger modules', () => {
  assert.deepEqual(readAllowlist().exemptFromPrint, PRINT_EXEMPT)
  assert.equal(PRINT_EXEMPT.length, 8)
})

test('compare flags an increase and a new file, and tolerates a decrease', () => {
  const allowlist = { files: { 'a.ts': { print: 2, emptyCatch: 1 } } }
  const results = [
    { file: 'a.ts', print: 1, emptyCatch: 2, hits: [{ kind: 'emptyCatch', line: 3, text: 'catch {}' }] },
    { file: 'b.ts', print: 1, emptyCatch: 0, hits: [{ kind: 'print', line: 1, text: 'console.log(' }] },
  ]
  const { increases, decreases } = compare(results, allowlist)
  assert.deepEqual(increases.map((x) => `${x.file}:${x.kind}:${x.allowed}->${x.found}`), ['a.ts:emptyCatch:1->2', 'b.ts:print:0->1'])
  assert.deepEqual(decreases.map((x) => `${x.file}:${x.kind}`), ['a.ts:print'])
})

test('TypeScript: console calls and empty catches, comments and strings handled', () => {
  const src = [
    "console.error('x')",
    "// console.log('commented out')",
    "/* console.warn('block') */",
    "const s = 'console.log(not code)'",
    'try { a() } catch { }',
    'try { a() } catch (e) { /* ignore */ }',
    'try { a() } catch (e) { logFailure(e) }',
    'p.catch(() => {})',
    'p.catch((e) => undefined)',
    'p.catch((e) => logFailure(e))',
    'const re = /["\']\\/\\//g; console.info(re)',
    'const t = `${a ? `x` : "y"} // not a comment`; console.debug(t)',
  ].join('\n')
  const r = scanSource(src, 'ts')
  assert.equal(r.print, 4, JSON.stringify(r.hits))
  assert.equal(r.emptyCatch, 4, JSON.stringify(r.hits))
})

test('TypeScript: console calls inside a string are counted (injected page script)', () => {
  const r = scanSource("const html = `<script>try { x() } catch(e) { console.log(e) }</script>`", 'ts')
  assert.equal(r.print, 1)
})

test('Swift: print family and empty catch clauses', () => {
  const src = [
    'print("a")',
    'debugPrint(x)',
    'NSLog("%@", e)',
    'os_log("x")',
    'dump(obj)',
    'logger.print(x)',
    '// print("commented")',
    'let s = "print(inside string)"',
    'let t = "value \\(fmt("print(no)"))"',
    'do { try x() } catch { }',
    'do { try x() } catch let e as URLError {\n  // nothing\n}',
    'do { try x() } catch { SellwildFailures.log(code: "a.b.c", component: "feed", error: error) }',
  ].join('\n')
  const r = scanSource(src, 'swift')
  assert.equal(r.print, 5, JSON.stringify(r.hits))
  assert.equal(r.emptyCatch, 2, JSON.stringify(r.hits))
})

test('Kotlin: Log, println, printStackTrace, System.out and empty catch', () => {
  const src = [
    'Log.e(TAG, "x", e)',
    'Log.d(TAG, "y")',
    'println("z")',
    'e.printStackTrace()',
    'System.err.println("w")',
    'builder.print(x)',
    '/* Log.w(TAG, "a") /* nested */ still comment */',
    'val s = "Log.e(not code)"',
    'try { a() } catch (e: Exception) {}',
    'try { a() } catch (_: Throwable) { /* ok */ }',
    'try { a() } catch (e: Exception) { SellwildFailures.log(code = "a.b.c", component = "feed", error = e) }',
  ].join('\n')
  const r = scanSource(src, 'kotlin')
  assert.equal(r.print, 5, JSON.stringify(r.hits))
  assert.equal(r.emptyCatch, 2, JSON.stringify(r.hits))
})

test('Dart: print, debugPrint, catch, on X {} and catchError swallows', () => {
  const src = [
    "print('a');",
    'debugPrint(x);',
    "/// onImpression: () => print('Ad shown'),",
    "final s = r'print(raw)';",
    "final t = '''multi\nprint(inside)\n''';",
    'try { a(); } catch (_) {}',
    'try { a(); } on FormatException {}',
    'try { a(); } on FormatException catch (e) { SellwildFailures.log(code: "a.b.c", component: "feed", error: e); }',
    'f.catchError((_) {});',
    'f.catchError((e) => null);',
    'extension X on Foo {}',
  ].join('\n')
  const r = scanSource(src, 'dart')
  assert.equal(r.print, 2, JSON.stringify(r.hits))
  assert.equal(r.emptyCatch, 4, JSON.stringify(r.hits))
})

test('exempt modules may print but not swallow', () => {
  const r = scanSource("console.log('debug echo'); try { x() } catch {}", 'ts', { exemptPrint: true })
  assert.equal(r.print, 0)
  assert.equal(r.emptyCatch, 1)
})

test('stripComments keeps offsets and newlines', () => {
  const src = 'a // b\n/* c\nd */ e'
  const out = stripComments(src, 'ts')
  assert.equal(out.length, src.length)
  assert.equal(out.split('\n').length, 3)
  assert.match(out, /^a\s+\n\s+\n\s+e$/)
})
