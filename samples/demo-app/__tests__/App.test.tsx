import 'react-native';
import React from 'react';
import {act, create} from 'react-test-renderer';
import type {ReactTestInstance} from 'react-test-renderer';
import {describe, expect, it, jest} from '@jest/globals';
import type {SellwildConfig} from '@sellwild/react-native-sdk';
import {buildConfig} from '@sellwild/sdk-core';
import type {ClientFailureEvent} from '@sellwild/sdk-core';
import {DiagnosticsScreen} from '../src/DiagnosticsScreen';
import {SampleId} from '../src/sampleIds';
import {
  configSourceOf,
  failureCodesText,
  failureSink,
  FailureLog,
  listingsStatus,
  SampleSettings,
  withSampleValues,
} from '../src/sampleModel';

// configure is never reached: the App test checks the tab bar before boot.
jest.mock('../src/sampleModel', () => {
  const actual = jest.requireActual<object>('../src/sampleModel');
  return {...actual, bootSample: () => new Promise(() => undefined)};
});

function sampleConfig(extra: Partial<SellwildConfig> = {}): SellwildConfig {
  return {
    ...buildConfig({partnerCode: SampleSettings.partnerCode}),
    slug: SampleSettings.slug,
    listingsUrl: SampleSettings.listingsUrl,
    ...extra,
  };
}

function failureEvent(action: string): ClientFailureEvent {
  return {
    event: 'clientFailure',
    action,
    label: 'remoteConfig',
    attributes: {},
    uid: 'uid',
    createdTime: 0,
  };
}

// The host Text element with testID `id` (a string type), and its text.
function textById(root: ReactTestInstance, id: string): string {
  const node = root.find(
    n => n.props.testID === id && typeof n.type === 'string',
  );
  return [node.props.children].flat().join('');
}

describe('App', () => {
  it('shows the four tabs with their ids and titles', () => {
    const App = jest.requireActual<{default: React.ComponentType}>(
      '../App',
    ).default;
    const tree = create(<App />);
    const tabs = [
      [SampleId.tabFeed, 'Feed'],
      [SampleId.tabAds, 'Ads'],
      [SampleId.tabListings, 'Listings'],
      [SampleId.tabDiagnostics, 'Diagnostics'],
    ];
    for (const [id, title] of tabs) {
      const tab = tree.root.findAll(n => n.props.testID === id)[0];
      expect(tab).toBeDefined();
      expect(tab.findByType('Text' as never).props.children).toBe(title);
    }
    tree.unmount();
  });
});

describe('sample model', () => {
  it('says fallback without a CDN config and remote with one', () => {
    expect(configSourceOf(sampleConfig())).toBe('fallback');
    expect(configSourceOf(sampleConfig({remote: {TITLE: 'x'}}))).toBe('remote');
  });

  it('fills the zones and title only where the config has none', () => {
    const filled = withSampleValues(sampleConfig());
    expect(filled.mobileZids).toEqual([SampleSettings.mrecZone]);
    expect(filled.mobileBannerZid).toBe(SampleSettings.bannerZone);
    expect(filled.title).toBe('Sellwild Sample');
    const kept = withSampleValues(
      sampleConfig({mobileZids: ['7'], mobileBannerZid: '8', title: 'T'}),
    );
    expect(kept.mobileZids).toEqual(['7']);
    expect(kept.mobileBannerZid).toBe('8');
    expect(kept.title).toBe('T');
  });

  it('writes the listings status the flows read', () => {
    expect(listingsStatus(12, 0, true, null)).toBe('Loading listings (load 1)');
    expect(listingsStatus(12, 1, false, null)).toBe('12 listings, load 1');
    expect(listingsStatus(12, 2, false, null)).toBe('12 listings, load 2');
    expect(listingsStatus(0, 1, false, new Error('HTTP 500'))).toBe(
      'Listings failed (load 1): HTTP 500',
    );
  });

  it('lists each failure code once, with a count', () => {
    expect(failureCodesText([])).toBe('none yet');
    expect(
      failureCodesText(['config.fetch.http', 'a.b.c', 'config.fetch.http']),
    ).toBe('config.fetch.http x2, a.b.c');
  });

  it('records each failure code and sends the event on', async () => {
    const log = new FailureLog();
    const heard: (readonly string[])[] = [];
    log.subscribe(codes => heard.push(codes));
    const pushed: ClientFailureEvent[] = [];
    let flushes = 0;
    const sink = failureSink(log, {
      push: event => pushed.push(event),
      flush: () => (flushes += 1),
    });
    sink.push(failureEvent('config.fetch.http'));
    sink.flushNow();
    expect(log.current).toEqual(['config.fetch.http']);
    expect(pushed.map(e => e.action)).toEqual(['config.fetch.http']);
    expect(flushes).toBe(1);
    await Promise.resolve();
    expect(heard).toEqual([['config.fetch.http']]);
  });
});

describe('DiagnosticsScreen', () => {
  it('shows partner and slug, the config source and the failure codes', async () => {
    const log = new FailureLog();
    const boot = {config: sampleConfig(), source: 'fallback' as const};
    const tree = create(<DiagnosticsScreen boot={boot} failures={log} />);
    const root = tree.root;
    expect(textById(root, SampleId.diagPartner)).toBe(
      'sellwild / sellwild-sample',
    );
    expect(textById(root, SampleId.diagConfigSource)).toBe('fallback');
    expect(textById(root, SampleId.diagListingsUrl)).toBe(
      SampleSettings.listingsUrl,
    );
    expect(textById(root, SampleId.diagFailures)).toBe('none yet');
    await act(async () => {
      log.record('config.fetch.http');
      await Promise.resolve();
    });
    expect(textById(root, SampleId.diagFailures)).toBe('config.fetch.http');
    tree.unmount();
  });
});
