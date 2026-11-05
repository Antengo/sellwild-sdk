import { describe, expect, it } from 'vitest'
import {
  eidBlob,
  eidBlobVariants,
  eidEntry,
  growthCodeSyncResponse,
  growthCodeSyncResponseVariants,
  invalidEidBlobs,
  invalidGrowthCodeSyncResponses,
} from '.'
import { parseEidBlob, parseGrowthCodeResponse } from '../../src/growthcode'
import { expectInvalid, expectInvalidCases, expectValid } from '../support/factory-checks'

describe('growthCodeSyncResponse factory', () => {
  it('defaults to the full fixture, which core parses', () => {
    const body = growthCodeSyncResponse()
    expectValid('growthcode-sync-response', body, 'default')
    expect(parseGrowthCodeResponse(body)).toMatchObject({ gcId: 'gc-fixture-0001', idInject: true, version: 4 })
  })

  it('builds every fixture variant as a valid response', () => {
    const names = Object.keys(growthCodeSyncResponseVariants)
    expect(names).toEqual(expect.arrayContaining(['full', 'empty', 'gc-id-null']))
    for (const name of names) expectValid('growthcode-sync-response', growthCodeSyncResponse({}, name), name)
  })

  it('carries an eid blob as eb text', () => {
    const body = growthCodeSyncResponse({ gc_id: null, eb: JSON.stringify(eidBlob([eidEntry({ source: 'id5-sync.com' })])) })
    expectValid('growthcode-sync-response', body, 'overrides')
    expect(parseEidBlob(body.eb)).toEqual([{ source: 'id5-sync.com', uids: [{ id: 'A4AAAABj-fixture-uid2', atype: 3 }] }])
  })

  it('fails the schema when an override breaks it, and for each invalid contract fixture', () => {
    expectInvalid('growthcode-sync-response', growthCodeSyncResponse({ idi: 'yes' as unknown as boolean }), { instancePath: '/idi', keyword: 'type' })
    expectInvalidCases('growthcode-sync-response', invalidGrowthCodeSyncResponses())
  })
})

describe('eidBlob factory', () => {
  it('defaults to the full fixture, which core parses', () => {
    const blob = eidBlob()
    expectValid('eid-blob', blob, 'default')
    expect(parseEidBlob(JSON.stringify(blob)).map((e) => e.source)).toEqual(['uidapi.com', 'id5-sync.com'])
  })

  it('builds every fixture variant as a valid blob', () => {
    const names = Object.keys(eidBlobVariants)
    expect(names).toEqual(expect.arrayContaining(['full', 'minimal']))
    for (const name of names) expectValid('eid-blob', eidBlob(undefined, name), name)
  })

  it('takes typed entries', () => {
    const blob = eidBlob([eidEntry({ source: 'liveramp.com', uids: [{ id: 'xY', atype: '3' }] })])
    expectValid('eid-blob', blob, 'overrides')
  })

  it('fails the schema when an override breaks it, and for each invalid contract fixture', () => {
    expectInvalid('eid-blob', eidBlob([eidEntry({ source: '' })]), { instancePath: '/0/source', keyword: 'minLength' })
    expectInvalidCases('eid-blob', invalidEidBlobs())
  })
})
