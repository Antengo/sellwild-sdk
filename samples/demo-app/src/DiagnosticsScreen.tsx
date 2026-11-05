import React, {useEffect, useState} from 'react';
import {Platform, ScrollView, StyleSheet, Text, View} from 'react-native';
import {resolveListingsUrl, SDK_VERSION} from '@sellwild/sdk-core';
import {failureCodesText} from './sampleModel';
import type {FailureLog, SampleBoot} from './sampleModel';
import {SampleId} from './sampleIds';
import {colors, ScreenHeader} from './widgets';

/** The failure log's codes, updated as the SDK reports. */
function useFailureCodes(log: FailureLog): readonly string[] {
  const [codes, setCodes] = useState(log.current);
  useEffect(() => {
    setCodes(log.current);
    return log.subscribe(setCodes);
  }, [log]);
  return codes;
}

/**
 * Diagnostics: what configure returned at launch, where it came from, and
 * the failure codes the SDK sent this launch (the failure sink).
 */
export function DiagnosticsScreen({
  boot,
  failures,
}: {
  boot: SampleBoot;
  failures: FailureLog;
}) {
  const codes = useFailureCodes(failures);
  const {config} = boot;
  return (
    <ScrollView contentContainerStyle={styles.content}>
      <ScreenHeader
        title="Diagnostics"
        detail="What configure returned at launch."
      />
      <Section title="SDK" />
      <Row
        label="SDK version (SDK_VERSION)"
        value={SDK_VERSION}
        id={SampleId.diagSdkVersion}
      />
      <Row label="Platform" value={Platform.OS} />
      <Section title="Config" />
      <Row
        label="Partner code / slug"
        value={`${config.partnerCode} / ${config.slug}`}
        id={SampleId.diagPartner}
      />
      <Row
        label="Config source"
        value={boot.source}
        id={SampleId.diagConfigSource}
      />
      <Row
        label="Listings URL"
        value={resolveListingsUrl(config)}
        id={SampleId.diagListingsUrl}
      />
      <Section title="Failures" />
      <Row
        label="Failure codes sent this launch (failure sink)"
        value={failureCodesText(codes)}
        id={SampleId.diagFailures}
      />
    </ScrollView>
  );
}

function Section({title}: {title: string}) {
  return <Text style={styles.section}>{title}</Text>;
}

/** A label with its value under it. The value carries the e2e id. */
function Row({label, value, id}: {label: string; value: string; id?: string}) {
  return (
    <View style={styles.row}>
      <Text style={styles.label}>{label}</Text>
      <Text testID={id} style={styles.value}>
        {value}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  content: {paddingBottom: 24},
  section: {
    fontSize: 14,
    fontWeight: '700',
    color: colors.text,
    paddingHorizontal: 16,
    paddingTop: 16,
    paddingBottom: 4,
  },
  row: {paddingHorizontal: 16, paddingVertical: 6},
  label: {fontSize: 11, color: colors.muted},
  value: {
    fontSize: 14,
    color: colors.text,
    fontFamily: Platform.select({ios: 'Menlo', default: 'monospace'}),
  },
});
