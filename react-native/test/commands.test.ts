import { describe, expect, it } from 'vitest'
import type { SellwildEid } from '@sellwild/sdk-core'
import { missingNativeCommand, prewarm, setExternalUserIds, setGeo } from '../src/commands'
import { toNativeConfig } from '../src/nativeConfig'
import { eidBlob, rnGeo, rnNativeConfig, sellwildConfig, bridged } from './factories'
import { expectValid } from './support/schemas'
import { countLogFailureCallsIn, freshModulesRecording, recordFailures, takeFailureEvents } from './support/failures'
import { NativeModules } from './stubs/react-native'

recordFailures()

const eids = () => eidBlob() as unknown as SellwildEid[]

describe('missingNativeCommand', () => {
  const fn = () => undefined
  it.each([
    ['no module', undefined, 'SellwildRNModule is not linked, so setGeo does nothing'],
    ['a null module', null, 'SellwildRNModule is not linked, so setGeo does nothing'],
    ['a module that is not an object', 'SellwildRNModule', 'SellwildRNModule is not linked, so setGeo does nothing'],
    ['a module without the method', {}, 'SellwildRNModule has no setGeo (an older native SDK), so it does nothing'],
    ['a method that is not a function', { setGeo: true }, 'SellwildRNModule has no setGeo (an older native SDK), so it does nothing'],
    ['the method', { setGeo: fn }, null],
  ])('%s', (_name, module, reason) => {
    expect(missingNativeCommand(module, 'setGeo')).toBe(reason)
  })
})

describe('the native commands, with the native module linked', () => {
  it('setGeo sends the geo, and {} to clear it', () => {
    const module = NativeModules.SellwildRNModule!
    const geo = rnGeo({ lat: 40.7, lon: -74 })
    expectValid('rn-native-config', geo, undefined, '/$defs/geo')
    setGeo(geo)
    setGeo(null)

    expect(module.setGeo.mock.calls).toEqual([[geo], [{}]])
    // Called as a method of the module, as before.
    expect(module.setGeo.mock.contexts[0]).toBe(module)
  })

  it('setExternalUserIds sends the eids, and [] for none', () => {
    const blob = eids()
    expectValid('eid-blob', blob)
    setExternalUserIds(blob)
    setExternalUserIds(undefined as unknown as SellwildEid[])

    expect(NativeModules.SellwildRNModule!.setExternalUserIds.mock.calls).toEqual([[blob], [[]]])
  })

  it('prewarm sends the native config', () => {
    const config = sellwildConfig()
    prewarm(config)

    const [[sent]] = NativeModules.SellwildRNModule!.prewarm.mock.calls
    expect(sent).toEqual(toNativeConfig(config))
    expect(bridged(sent)).toEqual(rnNativeConfig())
  })

  it('reports nothing', () => {
    setGeo(null)
    setExternalUserIds([])
    prewarm(sellwildConfig())
    expect(takeFailureEvents()).toEqual([])
  })
})

describe('the native commands, without the native module', () => {
  it('stay no-ops and report bridge.native_module.missing once per command', async () => {
    NativeModules.SellwildRNModule = undefined
    const core = await freshModulesRecording()
    const commands = await import('../src/commands')

    const counts = await countLogFailureCallsIn(core, () => {
      for (let i = 0; i < 3; i++) {
        commands.setGeo(null)
        commands.setExternalUserIds([])
        commands.prewarm(sellwildConfig())
      }
    })

    expect(counts).toEqual({ 'bridge.native_module.missing': 3 })
    const events = takeFailureEvents()
    expect(events.map((e) => [e.label, e.attributes.severity, e.attributes.msg])).toEqual([
      ['bridge', 'warn', 'SellwildRNModule is not linked, so setGeo does nothing'],
      ['bridge', 'warn', 'SellwildRNModule is not linked, so setExternalUserIds does nothing'],
      ['bridge', 'warn', 'SellwildRNModule is not linked, so prewarm does nothing'],
    ])
    for (const event of events) expectValid('client-failure-event', event, 'native-module-missing')
  })

  it('report a method an older native module lacks, and still call the ones it has', async () => {
    const module = NativeModules.SellwildRNModule!
    delete (module as { prewarm?: unknown }).prewarm
    const core = await freshModulesRecording()
    const commands = await import('../src/commands')

    const counts = await countLogFailureCallsIn(core, () => {
      commands.prewarm(sellwildConfig())
      commands.prewarm(sellwildConfig())
      commands.setGeo(null)
    })

    expect(counts).toEqual({ 'bridge.native_module.missing': 1 })
    expect(takeFailureEvents().map((e) => e.attributes.msg)).toEqual([
      'SellwildRNModule has no prewarm (an older native SDK), so it does nothing',
    ])
    expect(module.setGeo).toHaveBeenCalledWith({})
  })
})
