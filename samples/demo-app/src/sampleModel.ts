import {configure} from '@sellwild/react-native-sdk';
import type {SellwildConfig} from '@sellwild/react-native-sdk';
import {eventQueue, setFailureContext} from '@sellwild/sdk-core';
import type {ClientFailureEvent, FailureSink} from '@sellwild/sdk-core';

// What the sample passes to the SDK. It is the same on every platform's
// sample app, so the e2e flows see the same app.
export const SampleSettings = {
  // Sellwild's own partner code. Never use a real partner's code here.
  partnerCode: 'sellwild',
  // There is no app config for this slug on the CDN (it answers 403). So
  // configure keeps the SDK's built-in config and reports config.fetch.http
  // once a launch. That is expected.
  slug: 'sellwild-sample',
  // Sellwild's own listings feed, passed as the public listingsUrl.
  listingsUrl: 'https://cache.sellwild.com/listings-img-data-sm-avif-fandom',
  // This app's bundle id (iOS) and application id (Android).
  appId: 'com.sellwild.sample.rn',
  // Zone ids for the ad slots when the config has none (the same as the
  // native samples).
  bannerZone: 'sellwild-sample-banner',
  mrecZone: 'sellwild-sample-mrec',
  // How long configure waits for the CDN.
  configTimeoutMs: 5000,
} as const;

/** Where the config came from: the CDN, or the SDK's built-in fallback. */
export type ConfigSource = 'remote' | 'fallback';

/** configure sets `remote` only when the CDN answered with a config. */
export function configSourceOf(config: SellwildConfig): ConfigSource {
  return config.remote ? 'remote' : 'fallback';
}

/**
 * The sample's values over what configure returned. The CDN wins for the
 * title and the zones when it has them; the configure overrides already set
 * the listings URL, the app id and debug.
 */
export function withSampleValues(config: SellwildConfig): SellwildConfig {
  return {
    ...config,
    title: config.title || 'Sellwild Sample',
    mobileZids:
      config.mobileZids.length > 0
        ? config.mobileZids
        : [SampleSettings.mrecZone],
    mobileBannerZid: config.mobileBannerZid || SampleSettings.bannerZone,
  };
}

/** What configure gave at launch. */
export interface SampleBoot {
  config: SellwildConfig;
  source: ConfigSource;
}

/** Runs configure once, with the sample's values. */
export async function bootSample(): Promise<SampleBoot> {
  const config = await configure(
    SampleSettings.partnerCode,
    SampleSettings.slug,
    {
      timeout: SampleSettings.configTimeoutMs,
      overrides: {
        listingsUrl: SampleSettings.listingsUrl,
        appBundleId: SampleSettings.appId,
        debug: true,
      },
    },
  );
  return {config: withSampleValues(config), source: configSourceOf(config)};
}

type CodesListener = (codes: readonly string[]) => void;

/**
 * The failure codes the SDK sent this launch, oldest first. Diagnostics
 * shows them. Listeners hear of a new code in a microtask: the SDK may report
 * while React renders.
 */
export class FailureLog {
  private codes: readonly string[] = [];
  private readonly listeners = new Set<CodesListener>();

  get current(): readonly string[] {
    return this.codes;
  }

  record(code: string): void {
    this.codes = [...this.codes, code];
    const codes = this.codes;
    Promise.resolve().then(() => {
      for (const listener of this.listeners) {
        listener(codes);
      }
    });
  }

  subscribe(listener: CodesListener): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }
}

/** Where a failure event goes after the log has seen it. */
export interface EventForwarder {
  push(event: ClientFailureEvent): void;
  flush(): void;
}

/**
 * The failure sink of the sample: it records each code, then sends the event
 * on to the SDK's events queue, as the SDK does when no sink is set. The SDK
 * calls it for each failure its gate lets through (after sampling and
 * dedupe), so the log holds what was sent.
 */
export function failureSink(
  log: FailureLog,
  forward: EventForwarder = eventQueue,
): FailureSink {
  return {
    push: event => {
      log.record(event.action);
      forward.push(event);
    },
    flushNow: () => forward.flush(),
  };
}

/** The app's one failure log. */
export const failureLog = new FailureLog();

/**
 * Makes failureLog the SDK's failure sink (setFailureContext, from
 * @sellwild/sdk-core). Call it before configure, so configure's own
 * failures are seen too. It sees what React Native JS and core report; the
 * native SDKs under the bridge report theirs without it.
 */
export function installFailureSink(): void {
  setFailureContext({sink: failureSink(failureLog)});
}

/**
 * The failure codes line: each code once, in the order first seen, with a
 * count when it was sent more than once.
 */
export function failureCodesText(codes: readonly string[]): string {
  if (codes.length === 0) {
    return 'none yet';
  }
  const counts = new Map<string, number>();
  for (const code of codes) {
    counts.set(code, (counts.get(code) ?? 0) + 1);
  }
  return [...counts]
    .map(([code, count]) => (count === 1 ? code : `${code} x${count}`))
    .join(', ');
}

/**
 * The listings status (contracts/e2e/ids.json, sw.listings.status). After a
 * good load: '<count> listings, load <n>', where n counts loads this launch.
 */
export function listingsStatus(
  count: number,
  loads: number,
  loading: boolean,
  error: Error | null,
): string {
  if (loading) {
    return `Loading listings (load ${loads + 1})`;
  }
  if (error) {
    return `Listings failed (load ${loads}): ${error.message}`;
  }
  return `${count} listings, load ${loads}`;
}
