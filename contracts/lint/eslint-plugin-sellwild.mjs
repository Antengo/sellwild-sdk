// The house failure rules (FAILURES.md sections 1, 8.4 and 9) as ESLint rules.
//
// One copy for every TypeScript lane: sellwild-sdk core/ and react-native/
// import this file, and sellwild-widget vendors a byte-equal copy
// (contracts/vendor/lint/, sha256 sync check). It imports nothing, so it runs
// under any ESLint 9 install and adds no dependency.
//
// Rules:
//
//   sellwild/no-silent-catch
//     FAILURES.md 1.3 and 1.4. A catch clause whose body is empty or holds
//     only comments, and an inline promise `.catch(handler)` that swallows:
//     `() => {}`, `() => { /* ignore */ }`, `() => undefined`, `() => null`,
//     `() => void 0`. The print gate (section 11.4) counts the same shapes.
//
//   sellwild/catch-reports-failure
//     FAILURES.md 1.1. Every catch clause, and every inline promise
//     `.catch(handler)`, reports or passes on the failure. The body must do
//     one of these:
//       1. call a reporter (option `reporters`, default logFailure). A name
//          matches the whole callee: `logFailure` matches `logFailure(...)`
//          only, not `x.logFailure(...)` or `o.report(...)`; list a receiver
//          when it is one (`SellwildFailures.log`);
//       2. propagate it: a `throw` (outside a nested function) or
//          `Promise.reject(...)`;
//       3. hand it to code that reports it: a string that is a registry
//          code, `<area>.<operation>.<reason>` (option `codes`, when given,
//          must list it), passed to a call, returned or thrown, such as
//          `return { issue: { code: 'localized.config.parse', ... } }`. A
//          code only stored in a variable does not count. Or, in a catch
//          clause, a `return` whose value holds the caught error (the
//          pure-step Result: `return { ok: false, error }`, whose caller
//          logs it).
//     The sites FAILURES.md exempts (transport never reports itself, 8.4;
//     log once, 9.2) each carry their own
//     `// eslint-disable-next-line sellwild/catch-reports-failure -- FAILURES.md <section>: <why>`,
//     so every other catch in the same function is still checked. The
//     logFailure shell's own catch (3.4 item 4) is turned off per file in
//     the lint config. Empty catches are left to no-silent-catch, so each is
//     reported once.
//
//   sellwild/no-global-console
//     FAILURES.md 1.2. `console` reached through the global object:
//     `globalThis.console.error(...)`, `window.console`, `self['console']`,
//     `const { console: c } = global`. The core no-console rule sees only the
//     bare name. Turn it off where no-console is off (the A2 modules).
//
//   sellwild/disable-reason
//     A comment that turns off a sellwild/* rule (eslint-disable,
//     eslint-disable-line, eslint-disable-next-line, or an `eslint` rule
//     comment), or turns off every rule, must say why after ` -- ` and cite
//     the FAILURES.md section that allows it, such as
//     `-- FAILURES.md 8.4: transport never reports itself`.
//
// What ESLint cannot see: catches and prints inside page scripts built in
// template strings (the print gate scans those), and a `.catch(handler)`
// whose handler is not written inline.

/** FAILURES.md 4.1: `<area>.<operation>.<reason>`, at most 64 characters. */
export const FAILURE_CODE_FORMAT = /^[a-z][a-z0-9]*\.[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$/

const FUNCTIONS = new Set(['FunctionDeclaration', 'FunctionExpression', 'ArrowFunctionExpression'])

/** Every node under `node` (itself included), with whether it sits in a function nested below `node`. */
function * walk (node, keys, nested = false) {
  yield { node, nested }
  const inner = nested || FUNCTIONS.has(node.type)
  for (const key of keys[node.type] ?? []) {
    const child = node[key]
    for (const item of Array.isArray(child) ? child : [child]) {
      if (item && typeof item.type === 'string') yield * walk(item, keys, inner)
    }
  }
}

/** `a.b.c` for an identifier or a chain of plain member accesses, else null. */
function dottedName (node) {
  if (node.type === 'ChainExpression') return dottedName(node.expression)
  if (node.type === 'Identifier') return node.name
  if (node.type === 'MemberExpression' && !node.computed && node.property.type === 'Identifier') {
    const object = node.object.type === 'ThisExpression' ? 'this' : dottedName(node.object)
    return object === null ? `?.${node.property.name}` : `${object}.${node.property.name}`
  }
  return null
}

/** Whether a callee is one of `names`, written out in full: `report` is `report(...)`, not `o.report(...)`. */
function matchesCallee (callee, names) {
  const full = dottedName(callee)
  return full !== null && names.includes(full)
}

/**
 * Whether a registry-code string under a catch `body` is handed on: its value
 * flows, through expressions only, into a call's arguments, or into a
 * `return` or `throw` of the catch itself (not of a function nested in it).
 * A string stored in a variable, assigned, or returned by a nested function
 * is not handed on. An expression-bodied `.catch` handler returns its body.
 */
function isHandedOn (node, body) {
  for (let child = node; ; child = child.parent) {
    // Reached the body itself: only an expression body (an arrow handler's) is returned.
    if (child === body) return body.type !== 'BlockStatement'
    const parent = child.parent
    if (!parent) return false
    if ((parent.type === 'CallExpression' || parent.type === 'NewExpression') && parent.arguments.includes(child)) return true
    if (parent.type === 'ReturnStatement' || parent.type === 'ThrowStatement') return !nestedFunctionBetween(parent, body)
    if (FUNCTIONS.has(parent.type) || /(?:Statement|Declaration|Declarator)$/.test(parent.type)) return false
  }
}

/** Whether a function lies between `node` and the catch `body` above it. */
function nestedFunctionBetween (node, body) {
  for (let up = node.parent; up && up !== body; up = up.parent) {
    if (FUNCTIONS.has(up.type)) return true
  }
  return false
}

/**
 * Whether `node` reads the variable `name`: an identifier of that name that is
 * not a property key or a member property (`{ error: 1 }`, `x.error`).
 */
function reads (node, name, keys) {
  for (const { node: found } of walk(node, keys)) {
    if (found.type !== 'Identifier' || found.name !== name) continue
    const parent = found.parent
    if (parent?.type === 'Property' && parent.key === found && !parent.computed && !parent.shorthand) continue
    if (parent?.type === 'MemberExpression' && parent.property === found && !parent.computed) continue
    return true
  }
  return false
}

/** The handler of `x.catch(handler)` when it is written inline, else null. */
function inlineCatchHandler (call) {
  const callee = call.callee
  if (callee.type !== 'MemberExpression' || callee.computed || callee.property.type !== 'Identifier' || callee.property.name !== 'catch') return null
  const handler = call.arguments[0]
  return handler && (handler.type === 'ArrowFunctionExpression' || handler.type === 'FunctionExpression') ? handler : null
}

function isEmptyBlock (block) {
  return block.type === 'BlockStatement' && block.body.every((statement) => statement.type === 'EmptyStatement')
}

/** `undefined`, `null` or `void <x>`: a handler that returns one of these swallows the rejection. */
function isNothing (expression) {
  if (expression.type === 'Identifier') return expression.name === 'undefined'
  if (expression.type === 'Literal') return expression.value === null && !expression.regex && !('bigint' in expression)
  return expression.type === 'UnaryExpression' && expression.operator === 'void'
}

/** Whether an inline `.catch` handler swallows the rejection. */
function isSwallowingHandler (handler) {
  if (handler.body.type === 'BlockStatement') return isEmptyBlock(handler.body)
  return isNothing(handler.body)
}

const noSilentCatch = {
  meta: {
    type: 'problem',
    docs: { description: 'Disallow catch clauses that are empty or hold only comments, and promise .catch handlers that swallow (contracts/FAILURES.md 1.3, 1.4).' },
    schema: [],
    messages: {
      emptyCatch: 'Empty catch: a body of only comments is empty too (contracts/FAILURES.md 1.3). Call logFailure with a registry code, or rethrow.',
      swallow: 'This .catch handler swallows the rejection (contracts/FAILURES.md 1.4). Call logFailure with a registry code, or rethrow.',
    },
  },
  create (context) {
    return {
      CatchClause (node) {
        if (isEmptyBlock(node.body)) context.report({ node, messageId: 'emptyCatch' })
      },
      CallExpression (node) {
        const handler = inlineCatchHandler(node)
        if (handler && isSwallowingHandler(handler)) context.report({ node: handler, messageId: 'swallow' })
      },
    }
  },
}

const catchReportsFailure = {
  meta: {
    type: 'problem',
    docs: { description: 'Require every catch clause and inline promise .catch handler to call logFailure, rethrow, return the caught error, or hand on a registry failure code (contracts/FAILURES.md 1.1).' },
    schema: [{
      type: 'object',
      properties: {
        reporters: { type: 'array', items: { type: 'string', minLength: 1 }, uniqueItems: true },
        codes: { type: 'array', items: { type: 'string' } },
      },
      additionalProperties: false,
    }],
    messages: {
      unreported: 'This {{what}} neither reports nor passes on the failure: call {{reporters}} with a registry code, rethrow, return the caught error, or hand a registry code to the caller (contracts/FAILURES.md 1.1).',
    },
  },
  create (context) {
    const options = context.options[0] ?? {}
    const reporters = options.reporters ?? ['logFailure']
    const codes = options.codes ? new Set(options.codes) : null
    const keys = context.sourceCode.visitorKeys

    const isCode = (value) => typeof value === 'string' && value.length <= 64 && FAILURE_CODE_FORMAT.test(value) && (codes === null || codes.has(value))

    /** `param` is the caught error's variable when the caller may return it as a value (catch clauses only). */
    function handles (body, param = null) {
      for (const { node, nested } of walk(body, keys)) {
        if (node.type === 'CallExpression' && (matchesCallee(node.callee, reporters) || matchesCallee(node.callee, ['Promise.reject']))) return true
        if (node.type === 'ThrowStatement' && !nested) return true
        if (param !== null && node.type === 'ReturnStatement' && !nested && node.argument && reads(node.argument, param, keys)) return true
        if (node.type === 'Literal' && isCode(node.value) && isHandedOn(node, body)) return true
        if (node.type === 'TemplateLiteral' && node.expressions.length === 0 && isCode(node.quasis[0].value.cooked) && isHandedOn(node, body)) return true
      }
      return false
    }

    function check (node, body, what, param = null) {
      if (handles(body, param)) return
      context.report({ node, messageId: 'unreported', data: { what, reporters: reporters.join(' or ') } })
    }

    return {
      CatchClause (node) {
        if (isEmptyBlock(node.body)) return
        check(node, node.body, 'catch', node.param?.type === 'Identifier' ? node.param.name : null)
      },
      CallExpression (node) {
        const handler = inlineCatchHandler(node)
        if (!handler || isSwallowingHandler(handler)) return
        check(handler, handler.body, '.catch handler')
      },
    }
  },
}

/** The names of the global object. */
const GLOBALS = new Set(['globalThis', 'window', 'self', 'global'])

/** The property name a member access or a pattern key reads, when it is written out. */
function propertyName (node, computed) {
  if (!computed && node.type === 'Identifier') return node.name
  if (node.type === 'Literal' && typeof node.value === 'string') return node.value
  if (node.type === 'TemplateLiteral' && node.expressions.length === 0) return node.quasis[0].value.cooked
  return null
}

const noGlobalConsole = {
  meta: {
    type: 'problem',
    docs: { description: 'Disallow console reached through the global object (globalThis.console, window.console, self.console, global.console), which no-console does not see (contracts/FAILURES.md 1.2).' },
    schema: [],
    messages: {
      globalConsole: '{{object}}.console is console: do not print (contracts/FAILURES.md 1.2). Call logFailure with a registry code; trace output goes through the debug logger.',
    },
  },
  create (context) {
    const sourceCode = context.sourceCode

    /** `a.b.c` when every segment names the global object and none is a local variable, else null. */
    function globalObject (node) {
      const name = dottedName(node)
      if (name === null || !name.split('.').every((part) => GLOBALS.has(part))) return null
      const root = name.split('.')[0]
      for (let scope = sourceCode.getScope(node); scope; scope = scope.upper) {
        const variable = scope.set.get(root)
        if (variable) return variable.defs.length === 0 ? name : null
      }
      return name
    }

    function checkPattern (pattern, init) {
      if (pattern?.type !== 'ObjectPattern' || !init) return
      const object = globalObject(init)
      if (object === null) return
      for (const property of pattern.properties) {
        if (property.type === 'Property' && propertyName(property.key, property.computed) === 'console') {
          context.report({ node: property, messageId: 'globalConsole', data: { object } })
        }
      }
    }

    return {
      MemberExpression (node) {
        if (propertyName(node.property, node.computed) !== 'console') return
        const object = globalObject(node.object)
        if (object !== null) context.report({ node, messageId: 'globalConsole', data: { object } })
      },
      VariableDeclarator (node) { checkPattern(node.id, node.init) },
      AssignmentExpression (node) { checkPattern(node.left, node.right) },
    }
  },
}

/** `eslint-disable`, `eslint-disable-line`, `eslint-disable-next-line` or an `eslint` rule comment, split into its rules and its description. */
const DIRECTIVE = /^(eslint-disable(?:-next-line|-line)?|eslint)(?:\s+([\s\S]*))?$/
/** ESLint's own description separator: two or more dashes with white space around them. */
const DESCRIPTION = /\s-{2,}\s/
/** A description must cite the section of FAILURES.md that allows the exception. */
const CITES_SECTION = /FAILURES\.md\s+\d+(?:\.\d+)*/

const disableReason = {
  meta: {
    type: 'problem',
    docs: { description: 'Require a comment that turns off a sellwild/* rule to say why after " -- " and cite the FAILURES.md section that allows it.' },
    schema: [],
    messages: {
      missing: 'This comment turns off {{rules}} without a reason. Add " -- FAILURES.md <section>: <why>" (the section that allows this exception), or fix the code.',
      uncited: 'The reason must cite the FAILURES.md section that allows this exception, such as "FAILURES.md 8.4".',
    },
  },
  create (context) {
    return {
      Program () {
        for (const comment of context.sourceCode.getAllComments()) {
          // Trailing white space kept: ESLint reads "x -- " as rule x with an empty reason.
          const match = DIRECTIVE.exec(comment.value.replace(/^\s+/, ''))
          if (!match) continue
          const [head, ...rest] = (match[2] ?? '').split(DESCRIPTION)
          const description = rest.join(' ').trim()
          const blanket = match[1] !== 'eslint' && head.trim() === ''
          const named = (match[1] === 'eslint' ? [...head.matchAll(/(sellwild\/[\w-]+)\s*:/g)].map((m) => m[1]) : head.split(',').map((rule) => rule.trim()))
            .filter((rule) => rule.startsWith('sellwild/'))
          if (!blanket && named.length === 0) continue
          const rules = blanket ? 'every rule' : named.join(', ')
          if (description === '') context.report({ loc: comment.loc, messageId: 'missing', data: { rules } })
          else if (!CITES_SECTION.test(description)) context.report({ loc: comment.loc, messageId: 'uncited' })
        }
      },
    }
  },
}

const plugin = {
  meta: { name: 'eslint-plugin-sellwild', version: '1.1.0' },
  rules: {
    'no-silent-catch': noSilentCatch,
    'catch-reports-failure': catchReportsFailure,
    'no-global-console': noGlobalConsole,
    'disable-reason': disableReason,
  },
}

export default plugin
