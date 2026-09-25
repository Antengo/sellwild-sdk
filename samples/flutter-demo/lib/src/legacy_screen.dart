import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sellwild_sdk/sellwild_sdk.dart';

import 'sample_ids.dart';
import 'widgets.dart';

/// Legacy: the deprecated WebView widget. It runs Prebid.js in a WebView and
/// cannot earn the CPMs native ads do, so it is only on this screen.
class LegacyScreen extends StatefulWidget {
  const LegacyScreen({super.key, required this.config});

  final SellwildConfig config;

  @override
  State<LegacyScreen> createState() => _LegacyScreenState();
}

class _LegacyScreenState extends State<LegacyScreen> {
  String _status = 'Loading the widget';

  void _show(String status) {
    if (mounted) setState(() => _status = status);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              E2EId(
                SampleId.legacyTitle,
                child: Text(
                  'Legacy WebView widget (deprecated)',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'SellwildWidget. Use the Feed and Listings screens instead.',
                style: theme.textTheme.bodySmall,
              ),
              E2EId(
                SampleId.legacyStatus,
                child: Text(_status, style: theme.textTheme.labelSmall),
              ),
            ],
          ),
        ),
        Expanded(
          child: E2EId(
            SampleId.legacyWebView,
            label: 'Legacy widget',
            child: SellwildWidget(
              config: widget.config,
              onLoad: () => _show('Widget loaded'),
              onError: (error) => _show('Widget error: $error'),
              onListingTap: (listing) =>
                  unawaited(openLink(context, listing.url)),
            ),
          ),
        ),
      ],
    );
  }
}
