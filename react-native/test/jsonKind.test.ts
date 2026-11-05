import { describe, expect, it } from 'vitest'
import { jsonKind, parseErrorName } from '../src/jsonKind'

describe('jsonKind', () => {
  it.each([
    [null, 'null'],
    [undefined, 'undefined'],
    [[], 'an array'],
    [{}, 'an object'],
    ['x', 'a string'],
    [5, 'a number'],
    [true, 'a boolean'],
  ])('%j is %s', (value, kind) => {
    expect(jsonKind(value)).toBe(kind)
  })
})

describe('parseErrorName', () => {
  it('keeps only the name of a parse error', () => {
    let caught: unknown
    try {
      JSON.parse('{"listing": "105140231", secret')
    } catch (error) {
      caught = error
    }
    const named = parseErrorName(caught)
    expect(named).toBeInstanceOf(Error)
    expect([named?.name, named?.message, named?.stack]).toEqual(['SyntaxError', '', undefined])
  })

  it('gives undefined for something that is not an Error', () => {
    expect(parseErrorName('Unexpected token')).toBeUndefined()
    expect(parseErrorName(undefined)).toBeUndefined()
  })
})
