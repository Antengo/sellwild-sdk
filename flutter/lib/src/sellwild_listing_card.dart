import 'package:flutter/material.dart';

import 'failures/sellwild_failure_code.dart';
import 'failures/sellwild_failures.dart';
import 'listing_card_view.dart';
import 'sellwild_config.dart';
import 'sellwild_models.dart';

/// Native Flutter card for rendering a single Sellwild listing.
///
/// What it shows is decided by buildListingCardView (listing_card_view.dart).
/// A listing value it has to replace (an unknown currency, a price that is
/// not a number) and a photo that fails to load are each reported once per
/// card through logFailure. A config color that is not hex is reported once
/// per config, not once for every card in a feed.
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
    final view = buildListingCardView(listing, config);
    final photoUrl = view.photoUrl;
    final priceText = view.priceText;

    return _CardIssueReporter(
      listing: listing,
      config: config,
      issues: view.issues,
      child: GestureDetector(
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
                    if (photoUrl != null)
                      Image.network(
                        photoUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, error, __) => _PhotoFailure(
                          error: error,
                          url: photoUrl,
                          child: _placeholder(),
                        ),
                      )
                    else
                      _placeholder(),
                    if (priceText != null)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: _PriceBadge(
                          price: priceText,
                          color: view.priceColor,
                          textColor: view.priceFontColor,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  view.title,
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
      ),
    );
  }

  Widget _placeholder() => Container(color: const Color(0xFFE0E0E0));
}

/// The config.color.invalid messages already reported for each config.
final Expando<Set<String>> _colorIssuesReported =
    Expando<Set<String>>('color issues reported');

/// Reports the card's [issues] when it is first built, and again only when
/// it shows another listing or config, so rebuilds do not repeat them. A
/// color issue belongs to the config, so each config reports it once.
class _CardIssueReporter extends StatefulWidget {
  const _CardIssueReporter({
    required this.listing,
    required this.config,
    required this.issues,
    required this.child,
  });

  final SellwildListing listing;
  final SellwildConfig config;
  final List<CardIssue> issues;
  final Widget child;

  @override
  State<_CardIssueReporter> createState() => _CardIssueReporterState();
}

class _CardIssueReporterState extends State<_CardIssueReporter> {
  @override
  void initState() {
    super.initState();
    _report();
  }

  @override
  void didUpdateWidget(_CardIssueReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.listing, widget.listing) ||
        !identical(oldWidget.config, widget.config)) {
      _report();
    }
  }

  void _report() {
    final colorsReported = _colorIssuesReported[widget.config] ??= <String>{};
    for (final issue in widget.issues) {
      if (issue.code == SellwildFailureCode.configColorInvalid &&
          !colorsReported.add(issue.message)) {
        continue;
      }
      SellwildFailures.log(
        code: issue.code,
        component: SellwildFailureComponent.feed,
        severity: issue.severity,
        message: issue.message,
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The placeholder for a photo that failed to load. Reports each failure
/// once (feed.image.network): when it first appears, and when the card is
/// reused for a photo that fails too. Image keeps its last error while the
/// next photo loads, so a new URL alone is not a new failure; a new error
/// is.
class _PhotoFailure extends StatefulWidget {
  const _PhotoFailure({
    required this.error,
    required this.url,
    required this.child,
  });

  final Object error;
  final String url;
  final Widget child;

  @override
  State<_PhotoFailure> createState() => _PhotoFailureState();
}

class _PhotoFailureState extends State<_PhotoFailure> {
  @override
  void initState() {
    super.initState();
    _report();
  }

  @override
  void didUpdateWidget(_PhotoFailure oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.error, widget.error)) _report();
  }

  void _report() {
    SellwildFailures.log(
      code: SellwildFailureCode.feedImageNetwork,
      component: SellwildFailureComponent.feed,
      severity: SellwildFailureSeverity.warn,
      error: widget.error,
      url: widget.url,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
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
