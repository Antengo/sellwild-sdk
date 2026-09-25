import 'package:flutter/material.dart';
import 'package:sellwild_sdk/sellwild_sdk.dart';

import 'sample_ids.dart';
import 'widgets.dart';

/// Ads: every ad surface the Flutter SDK has. On Flutter each one is a
/// WebView: SellwildBanner loads Google Publisher Tag (or the Sellwild zone
/// script) in a page. There is no native ad view and no house ad view.
class AdsScreen extends StatelessWidget {
  const AdsScreen({super.key, required this.config});

  final SellwildConfig config;

  @override
  Widget build(BuildContext context) {
    final zones = config.mobileZids;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const ScreenHeader(
          title: 'Ads',
          detail: 'On Flutter, banners are WebView-rendered: SellwildBanner '
              'runs Google Publisher Tag in a WebView. The Flutter SDK has no '
              'native ad path (no Prebid Mobile, no GAM SDK).',
        ),
        AdSlot(
          title: 'Banner 320x50',
          detail: 'SellwildBanner(adSize: banner320x50), a WebView',
          id: SampleId.adBanner,
          sizeId: SampleId.adBannerSize,
          label: 'Banner 320x50 slot',
          width: 320,
          height: 50,
          child: SellwildBanner(
            config: config,
            adSize: SellwildAdSize.banner320x50,
            zoneId: config.mobileBannerZid,
          ),
        ),
        AdSlot(
          title: 'MREC 300x250',
          detail: 'SellwildBanner(adSize: mrec300x250), a WebView',
          id: SampleId.adMrec,
          sizeId: SampleId.adMrecSize,
          label: 'MREC 300x250 slot',
          width: 300,
          height: 250,
          child: SellwildBanner(
            config: config,
            adSize: SellwildAdSize.mrec300x250,
            zoneId: zones.isEmpty ? null : zones.first,
          ),
        ),
        const MissingSurface(
          title: 'Native ad',
          detail: 'Not in the Flutter SDK. iOS and Android have '
              'SellwildNativeAdView.',
        ),
        const MissingSurface(
          title: 'House ad',
          detail: 'Not in the Flutter SDK.',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'GAM ad unit: ${config.gamTag ?? 'none'}. The sample sets '
            "Google's GPT test unit when the CDN config has none. Fill is "
            'not checked: a test ad may not fill.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
