import { describe, expect, it } from 'vitest'
import { jsonKind, parseErrorName } from '../src/json-kind'

describe('jsonKind', () => {
  it.each([
    [null, 'null'], [undefined, 'undefined'], [[], 'an array'], [{}, 'an object'], ['x', 'a string'], [0, 'a number'], [false, 'a boolean'],
  ])('names %j as %j, never the value', (value, kind) => {
    expect(jsonKind(value)).toBe(kind)
  })
})

describe('parseErrorName', () => {
  it('keeps only the name of a parse error: the message quotes the text, and the stack repeats it', () => {
    let caught: unknown
    try {
      JSON.parse('ID5*private-token')
    } catch (error) {
      caught = error
    }
    expect(String((caught as Error).message)).toMatch(/ID5/)

    const named = parseErrorName(caught)

    expect(named).toBeInstanceOf(Error)
    expect(named).toMatchObject({ name: 'SyntaxError', message: '', stack: undefined })
    expect(named).not.toBe(caught)
    expect(JSON.stringify({ ...named, text: String(named) })).not.toMatch(/ID5|private|token/)
  })

  it('gives undefined for anything that is not an Error', () => {
    expect(parseErrorName('Unexpected token')).toBeUndefined()
    expect(parseErrorName({ name: 'SyntaxError', message: 'x' })).toBeUndefined()
    expect(parseErrorName(undefined)).toBeUndefined()
  })
})
