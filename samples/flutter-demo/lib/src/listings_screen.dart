import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:sellwild_sdk/sellwild_sdk.dart';

import 'sample_ids.dart';
import 'widgets.dart';

/// The listings status after a good load (contracts/e2e/ids.json,
/// sw.listings.status): '<count> listings, load <n>'.
String listingsStatus(int count, int load) => '$count listings, load $load';

/// The bytes of a `data:` photo URL, or null when [url] is no data URL or
/// does not decode. The feed's photos are data URLs.
Uint8List? dataUrlBytes(String? url) {
  if (url == null || !url.startsWith('data:')) return null;
  try {
    return UriData.parse(url).contentAsBytes();
  } on FormatException {
    return null;
  }
}

/// Listings: SellwildAPIClient.fetchListings, drawn by the app as its own
/// list of cards. Refresh clears the client's cache and fetches again.
class ListingsScreen extends StatefulWidget {
  const ListingsScreen({super.key, required this.config});

  final SellwildConfig config;

  @override
  State<ListingsScreen> createState() => _ListingsScreenState();
}

class _ListingsScreenState extends State<ListingsScreen> {
  List<SellwildListing> _listings = const [];
  Map<String, Uint8List> _photos = const {};
  String _status = 'Loading listings';
  int _loads = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load(clearCache: false));
  }

  Future<void> _load({required bool clearCache}) async {
    final client = SellwildAPIClient.instance;
    if (clearCache) client.clearCache();
    final load = ++_loads;
    setState(() => _status = 'Loading listings (load $load)');
    try {
      final response = await client.fetchListings(widget.config);
      if (!mounted) return;
      // Decode the data URL photos once, not on every build.
      final photos = <String, Uint8List>{
        for (final listing in response.listings)
          if (dataUrlBytes(listing.primaryPhoto?.url) case final bytes?)
            listing.id: bytes,
      };
      setState(() {
        _listings = response.listings;
        _photos = photos;
        _status = listingsStatus(response.listings.length, load);
      });
    } catch (e) {
      // The SDK has already reported this failure; the app only shows it.
      if (!mounted) return;
      setState(() => _status = 'Listings failed (load $load): $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: ScreenHeader(
                title: 'Listings',
                detail: 'SellwildAPIClient.fetchListings, drawn by the app.',
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12, right: 16),
              child: E2EId(
                SampleId.listingsRefresh,
                child: FilledButton(
                  onPressed: () => unawaited(_load(clearCache: true)),
                  child: const Text('Refresh'),
                ),
              ),
            ),
          ],
        ),
        StatusLine(SampleId.listingsStatus, _status),
        Expanded(
          child: E2EId(
            SampleId.listingsList,
            label: 'Listings',
            child: RefreshIndicator(
              onRefresh: () => _load(clearCache: true),
              child: ListView.separated(
                itemCount: _listings.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final listing = _listings[i];
                  return E2EId(
                    SampleId.listingCard,
                    child: _ListingRow(
                      listing: listing,
                      photo: _photos[listing.id],
                      onTap: () => unawaited(openLink(context, listing.url)),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One listing: photo, title, price and seller.
class _ListingRow extends StatelessWidget {
  const _ListingRow({
    required this.listing,
    required this.photo,
    required this.onTap,
  });

  final SellwildListing listing;
  final Uint8List? photo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final price = listing.displayPrice;
    final seller = sellerName(listing.user);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(width: 72, height: 72, child: _photo(theme)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    listing.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (price != null)
                    Text('\$$price', style: theme.textTheme.labelLarge),
                  if (seller != null)
                    Text('by $seller', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photo(ThemeData theme) {
    final placeholder =
        ColoredBox(color: theme.colorScheme.surfaceContainerHighest);
    final bytes = photo;
    if (bytes != null) {
      // A format the platform cannot decode (AVIF on some) shows the
      // placeholder.
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      );
    }
    final link = listing.primaryPhoto?.url;
    if (link != null && link.startsWith('http')) {
      return Image.network(
        link,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      );
    }
    return placeholder;
  }
}

/// "Nick P.": the seller's first name and last initial, or null.
String? sellerName(SellwildUser? user) {
  final first = user?.firstName.trim() ?? '';
  if (first.isEmpty) return null;
  final last = user?.lastName.trim() ?? '';
  return last.isEmpty ? first : '$first ${last[0]}.';
}
