import SwiftUI
import SellwildSDK

/// Diagnostics: what the SDK was configured with, and where it came from.
struct DiagnosticsScreen: View {
    let config: SellwildConfig
    let configSource: ConfigSource

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Diagnostics", detail: "What SellwildSDK.configure returned at launch.")
            List {
                Section(header: Text("SDK")) {
                    DiagnosticRow(label: "SDK version", value: SellwildSDK.sdkVersion, id: SampleID.diagSdkVersion)
                }
                Section(header: Text("Config")) {
                    DiagnosticRow(label: "Partner code / slug", value: "\(config.partnerCode) / \(SampleSettings.slug)",
                                  id: SampleID.diagPartner)
                    DiagnosticRow(label: "Config source", value: configSource.rawValue, id: SampleID.diagConfigSource)
                    DiagnosticRow(label: "Listings URL", value: config.effectiveListingsUrl,
                                  id: SampleID.diagListingsUrl)
                }
                Section(header: Text("Failures")) {
                    // iOS has no public failure sink: an app cannot read the
                    // codes the SDK reports. The context is public.
                    DiagnosticRow(label: "Failure codes this launch", value: "not available on this platform",
                                  id: SampleID.diagFailures)
                    DiagnosticRow(label: "SellwildFailures.context", value: failureContext,
                                  id: SampleID.diagFailureContext)
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var failureContext: String {
        let context = SellwildFailures.context
        let partner = context.partnerCode ?? "none"
        let reporting = context.isEnabled ? "on" : "off"
        return "partner \(partner), reporting \(reporting), sample rate \(context.sampleRate), "
            + "client \(context.client) \(context.clientVersion)"
    }
}

/// A label with its value under it. The value carries the e2e id.
struct DiagnosticRow: View {
    let label: String
    let value: String
    let id: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Text(value).font(.body.monospaced()).accessibilityIdentifier(id)
        }
    }
}
