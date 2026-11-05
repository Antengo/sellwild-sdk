// CDN app configs that break the contract in one field, built from a valid
// app-config fixture (core's appConfig factory) plus that field.
// wrongTypedAppConfig.test.ts checks each fails the schema with `error`.

import { appConfig, type AppConfigPayload, type InvalidCase } from '../../../core/test/factories'

export const wrongTypedAppConfigs: Record<string, { value: () => AppConfigPayload; error: InvalidCase['error'] }> = {
  // BANNER_SIZES_BY_ZONE as a size label instead of a zone map (the contract
  // allows a map, or the CMS's '' for unset). BANNER_SIZES is a JSON text list.
  'by-zone-label': {
    value: () => ({ ...appConfig({}, 'banner-sizes-json-text'), BANNER_SIZES_BY_ZONE: '728x90' }),
    error: { instancePath: '/BANNER_SIZES_BY_ZONE', keyword: 'anyOf' },
  },
}

/** A wrong-typed app config (wrongTypedAppConfigs). */
export function wrongTypedAppConfig(name: string): AppConfigPayload {
  const entry = wrongTypedAppConfigs[name]
  if (!entry) throw new Error(`no wrong-typed app-config '${name}'`)
  return entry.value()
}
