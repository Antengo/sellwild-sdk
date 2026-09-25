import React, {useState} from 'react';
import {StyleSheet, Text, View} from 'react-native';
import {SellwildWidget} from '@sellwild/react-native-sdk';
import type {SellwildConfig} from '@sellwild/react-native-sdk';
import {SampleId} from './sampleIds';
import {colors, openListing} from './widgets';

/**
 * Legacy: the deprecated WebView widget. It runs Prebid.js in a WebView and
 * cannot earn the CPMs native ads do, so it is only on this screen.
 */
export function LegacyScreen({config}: {config: SellwildConfig}) {
  const [status, setStatus] = useState('Loading the widget');
  return (
    <View style={styles.fill}>
      <View style={styles.header}>
        <Text testID={SampleId.legacyTitle} style={styles.title}>
          Legacy WebView widget (deprecated)
        </Text>
        <Text style={styles.detail}>
          SellwildWidget. Use the Feed and Listings screens instead.
        </Text>
        <Text testID={SampleId.legacyStatus} style={styles.status}>
          {status}
        </Text>
      </View>
      <View
        testID={SampleId.legacyWebView}
        collapsable={false}
        style={styles.fill}>
        <SellwildWidget
          config={config}
          style={styles.fill}
          onListingPress={openListing}
          onLoad={() => setStatus('Widget loaded')}
          onError={error => setStatus(`Widget error: ${error.message}`)}
        />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  fill: {flex: 1},
  header: {paddingHorizontal: 16, paddingTop: 12, paddingBottom: 8},
  title: {fontSize: 20, fontWeight: '700', color: colors.text},
  detail: {fontSize: 13, color: colors.muted, marginTop: 4},
  status: {fontSize: 12, color: colors.faint, marginTop: 4},
});
