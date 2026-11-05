import React, {useRef, useState} from 'react';
import {StyleSheet, View} from 'react-native';
import {SellwildFeed} from '@sellwild/react-native-sdk';
import type {SellwildConfig} from '@sellwild/react-native-sdk';
import {SampleId} from './sampleIds';
import {ScreenHeader, StatusLine} from './widgets';

/**
 * Feed: SellwildFeed, the all-in-one native feed. Listing cards with native
 * ads between them, laid out by the config's COL1 schedule. The SDK sets
 * sw.listing.card and sw.feed.ad on its rows.
 */
export function FeedScreen({config}: {config: SellwildConfig}) {
  const [status, setStatus] = useState('Loading the feed');
  const impressions = useRef(0);

  return (
    <View style={styles.fill}>
      <ScreenHeader
        title="Feed"
        detail="SellwildFeed: native listings with native ads between them."
      />
      <StatusLine id={SampleId.feedStatus} text={status} />
      <View testID={SampleId.feedList} collapsable={false} style={styles.fill}>
        <SellwildFeed
          config={config}
          onFeedReady={count => setStatus(`Feed loaded: ${count} listings`)}
          onAdImpression={() => {
            impressions.current += 1;
            setStatus(`Feed loaded, ${impressions.current} ad impression(s)`);
          }}
          onError={error => setStatus(`Feed error: ${error.message}`)}
        />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  fill: {flex: 1},
});
