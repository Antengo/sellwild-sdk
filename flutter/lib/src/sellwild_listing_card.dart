import 'package:flutter/material.dart';
import 'sellwild_config.dart';
import 'sellwild_models.dart';

/// Native Flutter card for rendering a single Sellwild listing.
class SellwildListingCard extends StatelessWidget {
  final SellwildListing listing;
  final SellwildConfig config;
  final void Function(SellwildListing)? onTap;

  const SellwildListingCard({
    super.key,
    required this.listing,
    required this.config,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final photo = listing.primaryPhoto;
    final price = listing.displayPrice;
    final title = listing.title.length > 60
        ? '${listing.title.substring(0, 60)}...'
        : listing.title;
    final currency = _currencySymbol(listing.currency ?? '');
    final priceColor = _hexColor(config.priceColor);
    final priceFontColor = _hexColor(config.priceFontColor);

    return GestureDetector(
      onTap: () => onTap?.call(listing),
      child: Container(
        width: 160,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F000000),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Image + price badge overlaid in a Stack
            SizedBox(
              width: double.infinity,
              height: 160,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (photo != null && photo.url.isNotEmpty)
                    Image.network(
                      photo.url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder(),
                    )
                  else
                    _placeholder(),
                  if (price != null)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: _PriceBadge(
                        price: '$currency$price',
                        color: priceColor,
                        textColor: priceFontColor,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: config.fontSize.toDouble(),
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(color: const Color(0xFFE0E0E0));

  Color _hexColor(String hex) {
    final clean = hex.replaceAll('#', '');
    final value = int.tryParse(clean, radix: 16);
    if (value == null) return Colors.grey;
    return Color(0xFF000000 | value);
  }

  String _currencySymbol(String currency) {
    const map = {
      'USD': '\$',
      'EUR': '€',
      'GBP': '£',
      'CAD': 'CA\$',
      'AUD': 'A\$',
    };
    return map[currency] ?? '\$';
  }
}

class _PriceBadge extends StatelessWidget {
  final String price;
  final Color color;
  final Color textColor;

  const _PriceBadge({
    required this.price,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          bottomLeft: Radius.circular(4),
        ),
      ),
      child: Text(
        price,
        style: TextStyle(
          color: textColor,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
