import React, {useState} from 'react';
import {ScrollView, StyleSheet, Text, View} from 'react-native';
import type {LayoutChangeEvent} from 'react-native';
import {SellwildBanner} from '@sellwild/react-native-sdk';
import type {SellwildConfig} from '@sellwild/react-native-sdk';
import {SampleSettings} from './sampleModel';
import {SampleId} from './sampleIds';
import {colors, ScreenHeader} from './widgets';

/**
 * Ads: each native ad surface the React Native SDK has. Test ads may not
 * fill; each slot keeps its size either way, and the label under it shows
 * the measured size.
 */
export function AdsScreen({config}: {config: SellwildConfig}) {
  return (
    <ScrollView contentContainerStyle={styles.content}>
      <ScreenHeader
        title="Ads"
        detail="SellwildBanner: native Prebid Mobile + GAM. No WebView in the ad path."
      />
      <AdSlot
        title="Banner 320x50"
        detail={'<SellwildBanner size="320x50">'}
        id={SampleId.adBanner}
        sizeId={SampleId.adBannerSize}>
        <SellwildBanner
          config={config}
          size="320x50"
          zoneId={SampleSettings.bannerZone}
        />
      </AdSlot>
      <AdSlot
        title="MREC 300x250"
        detail={'<SellwildBanner size="300x250">'}
        id={SampleId.adMrec}
        sizeId={SampleId.adMrecSize}>
        <SellwildBanner
          config={config}
          size="300x250"
          zoneId={SampleSettings.mrecZone}
        />
      </AdSlot>
      <Note
        title="Native ad"
        text="Not in the React Native SDK. SellwildFeed shows native ads between listings."
      />
      <Note
        title="House ad"
        text="Not in the React Native SDK. House backfill runs inside SellwildBanner when a slot does not fill."
      />
    </ScrollView>
  );
}

/** One ad slot: a title, the ad, and the ad's measured size. */
function AdSlot({
  title,
  detail,
  id,
  sizeId,
  children,
}: {
  title: string;
  detail: string;
  id: string;
  sizeId: string;
  children: React.ReactNode;
}) {
  const [size, setSize] = useState('0x0');
  const measure = (event: LayoutChangeEvent) => {
    const {width, height} = event.nativeEvent.layout;
    setSize(`${Math.round(width)}x${Math.round(height)}`);
  };
  return (
    <View style={styles.slot}>
      <Text style={styles.slotTitle}>{title}</Text>
      <Text style={styles.slotDetail}>{detail}</Text>
      <View
        testID={id}
        collapsable={false}
        style={styles.ad}
        onLayout={measure}>
        {children}
      </View>
      <Text testID={sizeId} style={styles.size}>
        {size}
      </Text>
    </View>
  );
}

/** A surface the React Native SDK does not have, and why. */
function Note({title, text}: {title: string; text: string}) {
  return (
    <View style={styles.slot}>
      <Text style={styles.slotTitle}>{title}</Text>
      <Text style={styles.slotDetail}>{text}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  content: {paddingBottom: 24},
  slot: {paddingHorizontal: 16, paddingTop: 20},
  slotTitle: {fontSize: 16, fontWeight: '600', color: colors.text},
  slotDetail: {
    fontSize: 12,
    color: colors.muted,
    marginTop: 2,
    marginBottom: 8,
  },
  ad: {alignSelf: 'center', backgroundColor: colors.border},
  size: {
    alignSelf: 'center',
    fontSize: 12,
    color: colors.muted,
    marginTop: 4,
    fontVariant: ['tabular-nums'],
  },
});
