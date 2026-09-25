import React, {useEffect, useRef, useState} from 'react';
import {FlatList, StyleSheet, Text, TouchableOpacity, View} from 'react-native';
import {
  SellwildListingCard,
  useSellwildListings,
} from '@sellwild/react-native-sdk';
import type {SellwildConfig} from '@sellwild/react-native-sdk';
import {listingsStatus} from './sampleModel';
import {SampleId} from './sampleIds';
import {colors, openListing, ScreenHeader, StatusLine} from './widgets';

/** How many loads finished this launch: counts each loading -> done. */
function useFinishedLoads(loading: boolean): number {
  const [finished, setFinished] = useState(0);
  const wasLoading = useRef(loading);
  useEffect(() => {
    if (wasLoading.current && !loading) {
      setFinished(n => n + 1);
    }
    wasLoading.current = loading;
  }, [loading]);
  return finished;
}

/**
 * Listings: useSellwildListings, drawn by the app as its own list of
 * SellwildListingCard. Refresh clears the listings cache and fetches again
 * (the hook's refresh).
 */
export function ListingsScreen({config}: {config: SellwildConfig}) {
  const {listings, loading, error, refresh} = useSellwildListings(config);
  const loads = useFinishedLoads(loading);

  return (
    <View style={styles.fill}>
      <View style={styles.headerRow}>
        <View style={styles.fill}>
          <ScreenHeader
            title="Listings"
            detail="useSellwildListings, drawn with SellwildListingCard."
          />
        </View>
        <TouchableOpacity
          testID={SampleId.listingsRefresh}
          accessibilityRole="button"
          style={styles.refresh}
          onPress={refresh}>
          <Text style={styles.refreshText}>Refresh</Text>
        </TouchableOpacity>
      </View>
      <StatusLine
        id={SampleId.listingsStatus}
        text={listingsStatus(listings.length, loads, loading, error)}
      />
      <FlatList
        testID={SampleId.listingsList}
        data={listings}
        numColumns={2}
        keyExtractor={item => item.id}
        contentContainerStyle={styles.list}
        renderItem={({item}) => (
          <View testID={SampleId.listingCard} style={styles.cell}>
            <SellwildListingCard
              listing={item}
              config={config}
              onPress={openListing}
            />
          </View>
        )}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  fill: {flex: 1},
  headerRow: {flexDirection: 'row', alignItems: 'flex-start'},
  refresh: {
    marginTop: 14,
    marginRight: 16,
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 8,
    backgroundColor: colors.accent,
  },
  refreshText: {color: colors.surface, fontWeight: '700'},
  list: {paddingHorizontal: 8, paddingBottom: 16},
  cell: {flex: 1, alignItems: 'center'},
});
