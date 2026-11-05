import SwiftUI
import SellwildSDK

/// Feed: `SellwildFeed`, the all-in-one native feed. Listing cards with
/// native ads between them, laid out by the config's COL1 schedule.
struct FeedScreen: View {
    let config: SellwildConfig
    @State private var status = "Loading the feed"
    @State private var impressions = 0

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Feed", detail: "SellwildFeed: native listings with native ads between them.")
            Text(status)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .accessibilityIdentifier(SampleID.feedStatus)
            SellwildFeed(
                config: config,
                // false: the SDK opens the listing in Safari.
                onListingTap: { _ in false },
                onAdImpression: { _ in
                    impressions += 1
                    status = "Feed loaded, \(impressions) ad impression(s)"
                },
                onLoad: { status = "Feed loaded" },
                onError: { message in status = "Feed error: \(message)" }
            )
            .accessibilityIdentifier(SampleID.feedList)
        }
    }
}
