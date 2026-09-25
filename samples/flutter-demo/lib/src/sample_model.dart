import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sellwild_sdk/sellwild_sdk.dart';

import 'sample_config.dart';

/// What configure gave at launch.
class SampleBoot {
  const SampleBoot(this.config, this.configSource);

  final SellwildConfig config;
  final ConfigSource configSource;
}

/// Runs SellwildSDK.configure once and keeps the failure codes the SDK sends
/// this launch (Diagnostics shows them).
class SampleModel {
  /// [send] passes each failure event on. The default sends it the way the
  /// SDK does without a sink: through SellwildAPIClient.instance.
  SampleModel({SellwildFailureSink? send}) : _send = send ?? sendThroughClient;

  final SellwildFailureSink _send;
  final List<String> _codes = [];

  /// The failure codes sent this launch, oldest first.
  final ValueNotifier<List<String>> failureCodes =
      ValueNotifier<List<String>>(const []);

  /// Installs the failure sink first, so configure's own failures are seen
  /// too, then runs configure with the sample's values.
  Future<SampleBoot> boot() async {
    installFailureSink();
    final config = await SellwildSDK.configure(
      partnerCode: SampleSettings.partnerCode,
      slug: SampleSettings.slug,
      overrides: withSampleValues,
    );
    return SampleBoot(config, configSourceOf(config));
  }

  /// Makes this model the SDK's failure sink (SellwildFailures.setContext).
  void installFailureSink() =>
      SellwildFailures.setContext(sink: _recordAndSend);

  /// The sink. The SDK calls it for each failure its gate lets through (after
  /// sampling and dedupe), so this is what reaches the events queue. The SDK
  /// can call it while Flutter builds a frame (a card reporting a bad photo),
  /// so listeners hear of a new code in a microtask, after the frame.
  Future<void> _recordAndSend(ClientFailureEvent event, bool flushNow) {
    _codes.add(event.action);
    scheduleMicrotask(() => failureCodes.value = List.unmodifiable(_codes));
    return _send(event, flushNow);
  }

  /// Sends [event] through SellwildAPIClient.instance, as the SDK does when
  /// no sink is set.
  static Future<void> sendThroughClient(ClientFailureEvent event, bool _) =>
      SellwildAPIClient.instance.sendEvent(
        event: event.event,
        action: event.action,
        label: event.label,
        uid: event.uid,
        attributes: event.attributes,
        createdTime: event.createdTime,
      );
}

/// The failure codes line: each code once, in the order first seen, with a
/// count when it was sent more than once.
String failureCodesText(List<String> codes) {
  if (codes.isEmpty) return 'none yet';
  final counts = <String, int>{};
  for (final code in codes) {
    counts[code] = (counts[code] ?? 0) + 1;
  }
  return counts.entries
      .map((e) => e.value == 1 ? e.key : '${e.key} x${e.value}')
      .join(', ');
}
