import SwiftUI
import UIKit
import SellwildSDK

/// Legacy: the deprecated WebView widget. It runs Prebid.js in a WebView and
/// cannot earn the CPMs native ads do, so it is only on this screen.
struct LegacyScreen: View {
    let config: SellwildConfig
    @State private var status = "Loading the widget"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Legacy WebView widget (deprecated)")
                    .font(.title3.bold())
                    .accessibilityIdentifier(SampleID.legacyTitle)
                Text("SellwildWidgetView. Use the Feed and Ads screens instead.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Text(status)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityIdentifier(SampleID.legacyStatus)
            }
            .padding(16)
            LegacyWidget(config: config) { status = $0 }
        }
    }
}

/// `SellwildWidgetView` (UIKit) in SwiftUI, with its delegate.
struct LegacyWidget: UIViewRepresentable {
    let config: SellwildConfig
    let onStatus: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onStatus: onStatus) }

    func makeUIView(context: Context) -> SellwildWidgetView {
        let widget = SellwildWidgetView(config: config)
        widget.delegate = context.coordinator
        widget.accessibilityIdentifier = SampleID.legacyWebView
        widget.load()
        return widget
    }

    func updateUIView(_ widget: SellwildWidgetView, context: Context) {}

    final class Coordinator: SellwildWidgetViewDelegate {
        private let onStatus: (String) -> Void

        init(onStatus: @escaping (String) -> Void) {
            self.onStatus = onStatus
        }

        func sellwildWidgetViewDidLoad(_ widgetView: SellwildWidgetView) {
            onStatus("Widget loaded")
        }

        func sellwildWidgetView(_ widgetView: SellwildWidgetView, didTapListing listing: SellwildListing) {
            guard let link = listing.url, let url = URL(string: link) else { return }
            UIApplication.shared.open(url)
        }

        func sellwildWidgetView(_ widgetView: SellwildWidgetView, didFailWithError error: Error) {
            onStatus("Widget error: \(error.localizedDescription)")
        }
    }
}
