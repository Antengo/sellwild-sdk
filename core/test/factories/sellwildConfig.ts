// A typed SellwildConfig, merged the way configure() merges it (defaults →
// partner and slug → mapped remote config → overrides), from an app-config
// payload. No fetch. Default: the real weatherbug config.

import { buildConfig } from '../../src/config'
import { mapRemoteConfig } from '../../src/remote-config'
import type { SellwildConfig } from '../../src/types'
import { appConfig, type AppConfigPayload } from './appConfig'

export function sellwildConfig(overrides: Partial<SellwildConfig> = {}, remote: AppConfigPayload = appConfig()): SellwildConfig {
  return {
    ...buildConfig({ partnerCode: remote.CODE, slug: remote.SLUG }),
    ...mapRemoteConfig(remote),
    ...overrides,
  }
}
