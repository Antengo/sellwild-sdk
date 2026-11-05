package com.sellwild.sample

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.sellwild.sdk.SellwildConfig
import com.sellwild.sdk.SellwildSDK
import com.sellwild.sdk.failures.SellwildFailures

/** Diagnostics: what the SDK was configured with, and where it came from. */
@Composable
fun DiagnosticsScreen(config: SellwildConfig) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        ScreenHeader("Diagnostics", "What SellwildSDK.configure returned at launch.")
        Section("SDK") {
            DiagnosticRow("SDK version", SellwildSDK.SDK_VERSION, SampleIds.DIAG_SDK_VERSION)
        }
        Section("Config") {
            DiagnosticRow(
                "Partner code / slug",
                "${config.partnerCode} / ${SampleSettings.SLUG}",
                SampleIds.DIAG_PARTNER,
            )
            DiagnosticRow("Config source", config.source.label, SampleIds.DIAG_CONFIG_SOURCE)
            DiagnosticRow("Listings URL", config.effectiveListingsUrl, SampleIds.DIAG_LISTINGS_URL)
        }
        Section("Failures") {
            // Android has no public failure sink: an app cannot read the codes the SDK
            // reports (SellwildFailures sends them to the events queue). The context is public.
            DiagnosticRow("Failure codes this launch", "not available on this platform", SampleIds.DIAG_FAILURES)
            DiagnosticRow("SellwildFailures.context", failureContext(), SampleIds.DIAG_FAILURE_CONTEXT)
        }
    }
}

/** The public failure context, in one line. Null remote flags mean on (FAILURES.md 3.2). */
private fun failureContext(): String {
    val context = SellwildFailures.context
    val reporting = context.failuresEnabledOverride ?: context.failuresEnabled ?: "on (default)"
    return "partner ${context.partnerCode ?: "none"}, reporting $reporting, " +
        "sample rate ${context.failuresSampleRate ?: "1 (default)"}, " +
        "client ${context.client} ${context.clientVersion}, debug ${context.debug}"
}

@Composable
private fun Section(title: String, rows: @Composable () -> Unit) {
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(title, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
        rows()
    }
}

/** A label with its value under it. The value carries the e2e id. */
@Composable
private fun DiagnosticRow(label: String, value: String, id: String) {
    Column {
        Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(
            value,
            Modifier.testTag(id),
            style = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
        )
    }
}
