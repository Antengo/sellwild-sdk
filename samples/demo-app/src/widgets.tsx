import React from 'react';
import {Linking, StyleSheet, Text, View} from 'react-native';
import type {SellwildListing} from '@sellwild/react-native-sdk';

export const colors = {
  accent: '#2563EB',
  background: '#F8FAFC',
  surface: '#FFFFFF',
  border: '#E2E8F0',
  text: '#0F172A',
  muted: '#64748B',
  faint: '#94A3B8',
};

/** A screen's title and one line about what it shows. */
export function ScreenHeader({title, detail}: {title: string; detail: string}) {
  return (
    <View style={styles.header}>
      <Text style={styles.title}>{title}</Text>
      <Text style={styles.detail}>{detail}</Text>
    </View>
  );
}

/** One line of status, with its e2e id. */
export function StatusLine({id, text}: {id: string; text: string}) {
  return (
    <Text testID={id} style={styles.status}>
      {text}
    </Text>
  );
}

/** Opens a listing's link in the browser. A link that will not open is ignored. */
export function openListing(listing: SellwildListing): void {
  if (listing.url) {
    Linking.openURL(listing.url).catch(() => undefined);
  }
}

const styles = StyleSheet.create({
  header: {paddingHorizontal: 16, paddingTop: 12, paddingBottom: 4},
  title: {fontSize: 22, fontWeight: '700', color: colors.text},
  detail: {fontSize: 13, color: colors.muted, marginTop: 2},
  status: {
    fontSize: 12,
    color: colors.muted,
    paddingHorizontal: 16,
    paddingBottom: 8,
  },
});
