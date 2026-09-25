import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sellwild_sdk/sellwild_sdk.dart';

import 'sample_config.dart';
import 'sample_ids.dart';
import 'sample_model.dart';
import 'widgets.dart';

/// Diagnostics: what configure returned at launch, where it came from, and
/// the failure codes the SDK sent this launch (the public failure sink).
class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({
    super.key,
    required this.boot,
    required this.failureCodes,
  });

  final SampleBoot boot;
  final ValueListenable<List<String>> failureCodes;

  @override
  Widget build(BuildContext context) {
    final config = boot.config;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const ScreenHeader(
          title: 'Diagnostics',
          detail: 'What SellwildSDK.configure returned at launch.',
        ),
        const _Section('SDK'),
        const _Row(
          label: 'SDK version (sellwildSdkVersion)',
          value: sellwildSdkVersion,
          id: SampleId.diagSdkVersion,
        ),
        const _Section('Config'),
        _Row(
          label: 'Partner code / slug',
          value: '${config.partnerCode} / ${SampleSettings.slug}',
          id: SampleId.diagPartner,
        ),
        _Row(
          label: 'Config source',
          value: boot.configSource.name,
          id: SampleId.diagConfigSource,
        ),
        _Row(
          label: 'Listings URL',
          value: config.effectiveListingsUrl,
          id: SampleId.diagListingsUrl,
        ),
        const _Section('Failures'),
        ValueListenableBuilder<List<String>>(
          valueListenable: failureCodes,
          builder: (context, codes, _) => _Row(
            label: 'Failure codes sent this launch (failure sink)',
            value: failureCodesText(codes),
            id: SampleId.diagFailures,
          ),
        ),
        ValueListenableBuilder<List<String>>(
          valueListenable: failureCodes,
          // Rebuilt with the codes, so it shows the context now.
          builder: (context, _, __) => _Row(
            label: 'SellwildFailures.context',
            value: failureContextText(SellwildFailures.context),
            id: SampleId.diagFailureContext,
          ),
        ),
      ],
    );
  }
}

/// The public failure context in one line.
String failureContextText(SellwildFailureContext context) {
  String flag(Object? value) => value == null ? 'unset' : '$value';
  return 'partner ${context.partnerCode ?? 'none'}, '
      'events ${flag(context.eventsEnabled)}, '
      'failures ${flag(context.failuresEnabled)}, '
      'sample rate ${flag(context.failuresSampleRate)}, '
      'debug ${context.debug}, '
      'client ${SellwildFailureContext.client} ${context.clientVersion}';
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      );
}

/// A label with its value under it. The value carries the e2e id.
class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, required this.id});

  final String label;
  final String value;
  final String id;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          E2EId(
            id,
            child: Text(
              value,
              style:
                  theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}
