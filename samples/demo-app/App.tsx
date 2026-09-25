/**
 * Sellwild Sample, React Native: the same four tabs as the iOS and Android
 * samples, so one set of Maestro flows (e2e/maestro) covers them all.
 *
 *   Feed         SellwildFeed: native listings with native ads between them
 *   Ads          SellwildBanner 320x50 and 300x250 (native Prebid + GAM)
 *   Listings     useSellwildListings + SellwildListingCard, with Refresh
 *   Diagnostics  SDK version, partner / slug, config source, failure codes
 *
 * Run it with scripts/e2e/run.sh rn-ios or rn-android (e2e/README.md).
 */
import React, {useEffect, useState} from 'react';
import {
  ActivityIndicator,
  SafeAreaView,
  StatusBar,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import {AdsScreen} from './src/AdsScreen';
import {DiagnosticsScreen} from './src/DiagnosticsScreen';
import {FeedScreen} from './src/FeedScreen';
import {ListingsScreen} from './src/ListingsScreen';
import {SampleId} from './src/sampleIds';
import {bootSample, failureLog, installFailureSink} from './src/sampleModel';
import type {SampleBoot} from './src/sampleModel';
import {colors} from './src/widgets';

// Before configure runs, so its failures reach Diagnostics too.
installFailureSink();

type Tab = 'feed' | 'ads' | 'listings' | 'diagnostics';

export const TABS: readonly {key: Tab; title: string; id: string}[] = [
  {key: 'feed', title: 'Feed', id: SampleId.tabFeed},
  {key: 'ads', title: 'Ads', id: SampleId.tabAds},
  {key: 'listings', title: 'Listings', id: SampleId.tabListings},
  {key: 'diagnostics', title: 'Diagnostics', id: SampleId.tabDiagnostics},
];

export default function App() {
  const [tab, setTab] = useState<Tab>('feed');
  const [boot, setBoot] = useState<SampleBoot | null>(null);
  const [bootError, setBootError] = useState<string | null>(null);

  useEffect(() => {
    let live = true;
    bootSample().then(
      result => live && setBoot(result),
      (error: unknown) => live && setBootError(String(error)),
    );
    return () => {
      live = false;
    };
  }, []);

  return (
    <SafeAreaView style={styles.root}>
      <StatusBar barStyle="dark-content" backgroundColor={colors.surface} />
      <View style={styles.screen}>
        {boot ? (
          <Screen tab={tab} boot={boot} />
        ) : (
          <View style={styles.center}>
            {bootError ? null : <ActivityIndicator color={colors.accent} />}
            <Text style={styles.bootText}>
              {bootError ? `Configure failed: ${bootError}` : 'Loading config'}
            </Text>
          </View>
        )}
      </View>
      <View style={styles.tabBar} accessibilityRole="tablist">
        {TABS.map(t => {
          const selected = t.key === tab;
          return (
            <TouchableOpacity
              key={t.key}
              testID={t.id}
              accessibilityRole="tab"
              accessibilityState={{selected}}
              style={styles.tab}
              onPress={() => setTab(t.key)}>
              <Text style={[styles.tabTitle, selected && styles.tabSelected]}>
                {t.title}
              </Text>
            </TouchableOpacity>
          );
        })}
      </View>
    </SafeAreaView>
  );
}

/** The selected tab's screen. The others are unmounted. */
function Screen({tab, boot}: {tab: Tab; boot: SampleBoot}) {
  switch (tab) {
    case 'feed':
      return <FeedScreen config={boot.config} />;
    case 'ads':
      return <AdsScreen config={boot.config} />;
    case 'listings':
      return <ListingsScreen config={boot.config} />;
    case 'diagnostics':
      return <DiagnosticsScreen boot={boot} failures={failureLog} />;
  }
}

const styles = StyleSheet.create({
  root: {flex: 1, backgroundColor: colors.background},
  screen: {flex: 1},
  center: {flex: 1, alignItems: 'center', justifyContent: 'center'},
  bootText: {marginTop: 8, color: colors.muted},
  tabBar: {
    flexDirection: 'row',
    backgroundColor: colors.surface,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.border,
  },
  tab: {flex: 1, alignItems: 'center', paddingVertical: 12},
  tabTitle: {fontSize: 12, fontWeight: '600', color: colors.faint},
  tabSelected: {color: colors.accent},
});
