import SwiftUI
import UIKit
import SellwildSDK

/// Ads: each native ad surface on its own. Test ads may not fill; each slot
/// keeps its size either way, and the label under it shows the measured size.
struct AdsScreen: View {
    let config: SellwildConfig

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ScreenHeader(title: "Ads", detail: "Native Prebid Mobile + GAM. No WebView in the ad path.")
                AdSlot(title: "Banner 320x50", detail: "SellwildAdBanner(adSize: .banner320x50)",
                       width: 320, height: 50, id: SampleID.adBanner, sizeID: SampleID.adBannerSize) {
                    SellwildAdBanner(config: config, adSize: .banner320x50, zoneId: SampleSettings.bannerZone)
                }
                AdSlot(title: "MREC 300x250", detail: "SellwildAdBanner(adSize: .mrec300x250)",
                       width: 300, height: 250, id: SampleID.adMrec, sizeID: SampleID.adMrecSize) {
                    SellwildAdBanner(config: config, adSize: .mrec300x250, zoneId: SampleSettings.mrecZone)
                }
                AdSlot(title: "Native ad", detail: "SellwildNativeAdView: Prebid native assets in a native template",
                       width: 300, height: 250, id: SampleID.adNative, sizeID: SampleID.adNativeSize) {
                    NativeAdSlot(config: config, zoneId: SampleSettings.nativeZone, maxHeight: 250)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("House ad").font(.headline)
                    Text("Not public on iOS. House backfill runs inside SellwildAdView when a slot does not fill.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 24)
        }
    }
}

/// One ad slot: a title, the ad at a fixed size, and its measured size.
struct AdSlot<Ad: View>: View {
    let title: String
    let detail: String
    let width: CGFloat
    let height: CGFloat
    let id: String
    let sizeID: String
    @ViewBuilder let ad: () -> Ad
    @State private var measured = CGSize.zero

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(detail).font(.footnote).foregroundColor(.secondary)
            ad()
                .frame(width: width, height: height)
                .background(Color(UIColor.secondarySystemBackground))
                .background(GeometryReader { proxy in
                    Color.clear
                        .onAppear { measured = proxy.size }
                        .onChange(of: proxy.size) { measured = $0 }
                })
                .accessibilityIdentifier(id)
                .frame(maxWidth: .infinity)
            Text("\(Int(measured.width.rounded()))x\(Int(measured.height.rounded()))")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .accessibilityIdentifier(sizeID)
        }
        .padding(.horizontal, 16)
    }
}

/// `SellwildNativeAdView` in SwiftUI. It has no public callbacks, so the
/// slot cannot tell a fill from a no-fill; it only keeps its size.
struct NativeAdSlot: UIViewRepresentable {
    let config: SellwildConfig
    let zoneId: String
    let maxHeight: CGFloat

    func makeUIView(context: Context) -> SellwildNativeAdView {
        let view = SellwildNativeAdView(config: config, zoneId: zoneId, maxHeight: maxHeight)
        view.load()
        return view
    }

    func updateUIView(_ view: SellwildNativeAdView, context: Context) {}
}
