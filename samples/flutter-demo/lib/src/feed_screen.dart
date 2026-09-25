import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sellwild_sdk/sellwild_sdk.dart';

import 'sample_config.dart';
import 'sample_ids.dart';
import 'widgets.dart';

/// One row of the feed.
sealed class FeedRow {
  const FeedRow();
}

/// Listing cards [start] (inclusive) to [end] (exclusive), side by side.
class FeedCards extends FeedRow {
  const FeedCards(this.start, this.end);

  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      other is FeedCards && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'FeedCards($start, $end)';
}

/// The [index]th ad row.
class FeedAd extends FeedRow {
  const FeedAd(this.index);

  final int index;

  @override
  bool operator ==(Object other) => other is FeedAd && other.index == index;

  @override
  int get hashCode => index.hashCode;

  @override
  String toString() => 'FeedAd($index)';
}

/// The feed's rows for [listings] cards: [perRow] cards a row, and an ad row
/// after every [cardsPerAd] cards (none after the last card).
List<FeedRow> feedRows(
  int listings, {
  int perRow = 2,
  int cardsPerAd = SampleSettings.cardsPerAd,
}) {
  final rows = <FeedRow>[];
  var ads = 0;
  for (var start = 0; start < listings; start += perRow) {
    final end = min(start + perRow, listings);
    rows.add(FeedCards(start, end));
    if (end < listings && end % cardsPerAd == 0) rows.add(FeedAd(ads++));
  }
  return rows;
}

/// Feed: the Flutter SDK has no feed component, so the app builds one from
/// fetchListings: SellwildListingCard (native Flutter cards), with a
/// SellwildBanner ad row between them. On Flutter that banner is a WebView.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key, required this.config});

  final SellwildConfig config;

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  List<SellwildListing> _listings = const [];
  String _status = 'Loading the feed';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final response =
          await SellwildAPIClient.instance.fetchListings(widget.config);
      if (!mounted) return;
      setState(() {
        _listings = response.listings;
        _status = '${response.listings.length} listings, an ad after every '
            '${SampleSettings.cardsPerAd}';
      });
    } catch (e) {
      // The SDK has already reported this failure; the app only shows it.
      if (!mounted) return;
      setState(() => _status = 'Feed error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = feedRows(_listings.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ScreenHeader(
          title: 'Feed',
          detail: 'fetchListings drawn with SellwildListingCard (native '
              'Flutter cards). The Flutter SDK has no feed component and no '
              'native ad view: the ad rows are SellwildBanner, a WebView.',
        ),
        StatusLine(SampleId.feedStatus, _status),
        Expanded(
          child: E2EId(
            SampleId.feedList,
            label: 'Feed',
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: rows.length,
              itemBuilder: (context, i) => switch (rows[i]) {
                FeedCards(:final start, :final end) => _cards(start, end),
                FeedAd() => _ad(),
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _cards(int start, int end) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final listing in _listings.sublist(start, end))
              E2EId(
                SampleId.listingCard,
                child: SellwildListingCard(
                  listing: listing,
                  config: widget.config,
                  onTap: (l) => unawaited(openLink(context, l.url)),
                ),
              ),
          ],
        ),
      );

  Widget _ad() {
    final zones = widget.config.mobileZids;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: E2EId(
        SampleId.feedAd,
        child: Column(
          children: [
            Text(
              'Ad: SellwildBanner 300x250 (WebView)',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 4),
            SellwildBanner(
              config: widget.config,
              adSize: SellwildAdSize.mrec300x250,
              zoneId: zones.isEmpty ? null : zones.first,
            ),
          ],
        ),
      ),
    );
  }
}
