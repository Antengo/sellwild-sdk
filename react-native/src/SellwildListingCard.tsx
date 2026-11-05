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
import { logFailure } from './failures'
import { listingCardView } from './listingCard'

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
  const view = listingCardView(listing)
  const { photoUrl, price, strikePrice, currencySymbol, title } = view

  // A field the card cannot show is hidden, as before, and reported once per
  // value (listings.item.invalid). Only the field and its kind are sent.
  const issues = view.issues.join('\n')
  React.useEffect(() => {
    if (!issues) return
    for (const issue of issues.split('\n')) {
      logFailure({ code: 'listings.item.invalid', component: 'listings', severity: 'warn', message: issue })
    }
  }, [issues])

  return (
    <TouchableOpacity
      style={[styles.card, style]}
      onPress={() => onPress?.(listing)}
      activeOpacity={0.85}
      accessible
      accessibilityLabel={title}
      accessibilityRole="button"
    >
      {photoUrl ? (
        <Image
          source={{ uri: photoUrl }}
          style={styles.image}
          resizeMode="cover"
          accessibilityLabel={title}
        />
      ) : (
        <View style={[styles.image, styles.imagePlaceholder]} />
      )}

      <View style={styles.overlay}>
        {view.showPrice && (
          <View style={[styles.priceBadge, { backgroundColor: config.priceColor || config.colors?.[0] || '#333' }]}>
            {view.showStrike && (
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
