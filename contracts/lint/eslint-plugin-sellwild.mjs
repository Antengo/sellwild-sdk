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
//       1. call a reporter: `logFailure(...)` or `x.logFailure(...)` (option
//          `reporters`, names matched on the callee's last segment unless the
//          entry is dotted);
//       2. propagate it: a `throw` (outside a nested function) or
//          `Promise.reject(...)`;
//       3. hand it to code that reports it: a string that is a registry
//          code, `<area>.<operation>.<reason>` (option `codes`, when given,
//          must list it), such as `return { issue: { code:
//          'localized.config.parse', ... } }`; or, in a catch clause, a
//          `return` whose value holds the caught error (the pure-step
//          Result: `return { ok: false, error }`, whose caller logs it).
//     A catch inside a function named in `exemptFunctions` is skipped. Use it
//     only for the sites FAILURES.md exempts, per file, in the lint config:
//     transport never reports itself (8.4), the logFailure shell's own catch
//     (3.4 item 4) and log-once wrappers (9.2). Anything else goes through an
//     `eslint-disable-next-line sellwild/catch-reports-failure -- <why>`.
//     Empty catches are left to no-silent-catch, so each is reported once.
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

function matchesCallee (callee, names) {
  const full = dottedName(callee)
  if (full === null) return false
  const last = full.slice(full.lastIndexOf('.') + 1)
  return names.some((name) => (name.includes('.') ? full === name || full.endsWith(`.${name}`) : last === name))
}

function keyName (key) {
  if (key.type === 'Identifier' || key.type === 'PrivateIdentifier') return key.name
  if (key.type === 'Literal' && typeof key.value === 'string') return key.value
  return null
}

/** The name a function is known by: its own, or the variable, property, method or assignment target that holds it. */
function functionName (fn) {
  if (fn.id?.name) return fn.id.name
  const parent = fn.parent
  if (!parent) return null
  if (parent.type === 'VariableDeclarator' && parent.init === fn && parent.id.type === 'Identifier') return parent.id.name
  if (['MethodDefinition', 'Property', 'PropertyDefinition'].includes(parent.type) && parent.value === fn) return keyName(parent.key)
  if (parent.type === 'AssignmentExpression' && parent.right === fn) {
    const name = dottedName(parent.left)
    return name === null ? null : name.slice(name.lastIndexOf('.') + 1)
  }
  return null
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
        exemptFunctions: { type: 'array', items: { type: 'string', minLength: 1 }, uniqueItems: true },
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
    const exempt = new Set(options.exemptFunctions ?? [])
    const codes = options.codes ? new Set(options.codes) : null
    const sourceCode = context.sourceCode
    const keys = sourceCode.visitorKeys

    const isCode = (value) => typeof value === 'string' && value.length <= 64 && FAILURE_CODE_FORMAT.test(value) && (codes === null || codes.has(value))

    /** `param` is the caught error's variable when the caller may return it as a value (catch clauses only). */
    function handles (body, param = null) {
      for (const { node, nested } of walk(body, keys)) {
        if (node.type === 'CallExpression' && (matchesCallee(node.callee, reporters) || matchesCallee(node.callee, ['Promise.reject']))) return true
        if (node.type === 'ThrowStatement' && !nested) return true
        if (param !== null && node.type === 'ReturnStatement' && !nested && node.argument && reads(node.argument, param, keys)) return true
        if (node.type === 'Literal' && isCode(node.value)) return true
        if (node.type === 'TemplateLiteral' && node.expressions.length === 0 && isCode(node.quasis[0].value.cooked)) return true
      }
      return false
    }

    function isExempt (node) {
      if (exempt.size === 0) return false
      return sourceCode.getAncestors(node).some((ancestor) => FUNCTIONS.has(ancestor.type) && exempt.has(functionName(ancestor)))
    }

    function check (node, body, what, param = null) {
      if (handles(body, param) || isExempt(node)) return
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

const plugin = {
  meta: { name: 'eslint-plugin-sellwild', version: '1.0.0' },
  rules: {
    'no-silent-catch': noSilentCatch,
    'catch-reports-failure': catchReportsFailure,
  },
}

export default plugin
