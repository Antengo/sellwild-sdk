// Reads the attributes of one start tag the way an HTML parser does (the
// WHATWG tokenizer's attribute states), so a test can check what the widget
// really gets from element.getAttribute(): a `"` inside a double-quoted value
// ends the value, text after it starts new attributes, and `>` ends the tag.
// Character references are decoded in values. Only what the SDK's generated
// pages need: no comments, no CDATA, no legacy references without `;`.

export interface StartTag {
  /** Attribute name (lower case) to decoded value. The first of two same-named attributes wins. */
  attributes: Map<string, string>
  /** Index just past the tag's `>`, or -1 when the text ends first. */
  end: number
}

const NAMED: Record<string, string> = { amp: '&', quot: '"', apos: "'", lt: '<', gt: '>', nbsp: ' ' }

/** Decodes `&name;`, `&#N;` and `&#xH;` references. Anything else is left as it is. */
export function decodeCharacterReferences(text: string): string {
  return text.replace(/&(#[0-9]+|#[xX][0-9a-fA-F]+|[a-zA-Z]+);/g, (whole, ref: string) => {
    if (ref[0] !== '#') return NAMED[ref] ?? whole
    const code = ref[1] === 'x' || ref[1] === 'X' ? parseInt(ref.slice(2), 16) : parseInt(ref.slice(1), 10)
    return String.fromCodePoint(code)
  })
}

const isSpace = (c: string | undefined) => c === ' ' || c === '\n' || c === '\t' || c === '\f' || c === '\r'

/** The first `<tagName ...>` start tag in `html`, parsed. Throws when there is none. */
export function parseStartTag(html: string, tagName: string): StartTag {
  const open = html.indexOf(`<${tagName}`)
  if (open === -1) throw new Error(`no <${tagName}> in the page`)
  const attributes = new Map<string, string>()
  let i = open + 1 + tagName.length
  const add = (name: string, value: string) => {
    if (!attributes.has(name)) attributes.set(name, decodeCharacterReferences(value))
  }
  while (i < html.length) {
    // Before attribute name.
    while (isSpace(html[i]) || html[i] === '/') {
      if (html[i] === '/' && html[i + 1] === '>') return { attributes, end: i + 2 }
      i += 1
    }
    if (i >= html.length) break
    if (html[i] === '>') return { attributes, end: i + 1 }
    // Attribute name: up to space, '/', '>' or '=' (a leading '=' belongs to the name).
    let name = html[i]
    i += 1
    while (i < html.length && !isSpace(html[i]) && html[i] !== '/' && html[i] !== '>' && html[i] !== '=') {
      name += html[i]
      i += 1
    }
    name = name.toLowerCase()
    // After attribute name.
    while (isSpace(html[i])) i += 1
    if (html[i] !== '=') {
      add(name, '')
      continue
    }
    i += 1
    while (isSpace(html[i])) i += 1
    const quote = html[i]
    if (quote === '"' || quote === "'") {
      const close = html.indexOf(quote, i + 1)
      if (close === -1) return { attributes, end: -1 }
      add(name, html.slice(i + 1, close))
      i = close + 1
      // After a quoted value a missing space is a parse error: the next
      // character starts the next attribute name all the same.
      continue
    }
    let value = ''
    while (i < html.length && !isSpace(html[i]) && html[i] !== '>') {
      value += html[i]
      i += 1
    }
    add(name, value)
  }
  return { attributes, end: -1 }
}
