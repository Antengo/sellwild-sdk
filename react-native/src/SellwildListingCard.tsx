import React from 'react'
import {
  View,
  Text,
  Image,
  TouchableOpacity,
  StyleSheet,
  ViewStyle,
} from 'react-native'
import type { SellwildListing, SellwildConfig } from '@sellwild/sdk-core'
import { currencyToSymbol } from '@sellwild/sdk-core'

export interface SellwildListingCardProps {
  listing: SellwildListing
  config: SellwildConfig
  onPress?: (listing: SellwildListing) => void
  style?: ViewStyle
}

export function SellwildListingCard({
  listing,
  config,
  onPress,
  style,
}: SellwildListingCardProps) {
  const photo = listing.photos?.[0]
  const price = listing.price && !isNaN(Number(listing.price))
    ? Number(listing.price).toLocaleString(undefined, { maximumFractionDigits: 0 })
    : null
  const strikePrice = listing.strikePrice && !isNaN(Number(listing.strikePrice))
    ? Number(listing.strikePrice).toLocaleString(undefined, { maximumFractionDigits: 0 })
    : null
  const currencySymbol = currencyToSymbol(listing.currency)
  const title = listing.title?.length > 60
    ? listing.title.slice(0, 60) + '...'
    : listing.title

  return (
    <TouchableOpacity
      style={[styles.card, style]}
      onPress={() => onPress?.(listing)}
      activeOpacity={0.85}
      accessible
      accessibilityLabel={title}
      accessibilityRole="button"
    >
      {photo?.url ? (
        <Image
          source={{ uri: photo.url }}
          style={styles.image}
          resizeMode="cover"
          accessibilityLabel={title}
        />
      ) : (
        <View style={[styles.image, styles.imagePlaceholder]} />
      )}

      <View style={styles.overlay}>
        {price && price !== '0' && (
          <View style={[styles.priceBadge, { backgroundColor: config.priceColor || config.colors?.[0] || '#333' }]}>
            {strikePrice && strikePrice !== price && (
              <Text style={[styles.strikePrice, { color: config.priceFontColor || config.fontColor }]}>
                {currencySymbol}{strikePrice}
              </Text>
            )}
            <Text style={[styles.price, { color: config.priceFontColor || config.fontColor }]}>
              {currencySymbol}{price}
            </Text>
          </View>
        )}
      </View>

      <View style={styles.footer}>
        <Text style={[styles.title, { fontSize: config.fontSize, color: '#222' }]} numberOfLines={2}>
          {title}
        </Text>
      </View>
    </TouchableOpacity>
  )
}

const styles = StyleSheet.create({
  card: {
    width: 160,
    borderRadius: 8,
    overflow: 'hidden',
    backgroundColor: '#fff',
    elevation: 2,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.12,
    shadowRadius: 4,
    marginBottom: 10,
  },
  image: {
    width: '100%',
    height: 160,
  },
  imagePlaceholder: {
    backgroundColor: '#e0e0e0',
  },
  overlay: {
    position: 'absolute',
    bottom: 36,
    right: 0,
  },
  priceBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderTopLeftRadius: 4,
    borderBottomLeftRadius: 4,
  },
  price: {
    fontSize: 13,
    fontWeight: '600',
  },
  strikePrice: {
    fontSize: 11,
    textDecorationLine: 'line-through',
    marginRight: 4,
    opacity: 0.7,
  },
  footer: {
    padding: 8,
    minHeight: 36,
  },
  title: {
    fontWeight: '400',
    lineHeight: 18,
  },
})
