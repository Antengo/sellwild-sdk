import SwiftUI

#if canImport(UIKit)
import UIKit

// MARK: - SwiftUI Widget View

/// SwiftUI wrapper for SellwildWidgetView.
@available(iOS 14, *)
public struct SellwildWidget: UIViewRepresentable {
    public let config: SellwildConfig
    public var onListingTap: ((SellwildListing) -> Void)?
    public var onLoad: (() -> Void)?
    public var onError: ((Error) -> Void)?

    public init(
        config: SellwildConfig,
        onListingTap: ((SellwildListing) -> Void)? = nil,
        onLoad: (() -> Void)? = nil,
        onError: ((Error) -> Void)? = nil
    ) {
        self.config = config
        self.onListingTap = onListingTap
        self.onLoad = onLoad
        self.onError = onError
    }

    public func makeUIView(context: Context) -> SellwildWidgetView {
        let view = SellwildWidgetView(config: config)
        view.delegate = context.coordinator
        view.onListingTap = onListingTap
        view.load()
        return view
    }

    public func updateUIView(_ uiView: SellwildWidgetView, context: Context) {}

    public func makeCoordinator() -> Coordinator {
        Coordinator(onLoad: onLoad, onError: onError)
    }

    public final class Coordinator: NSObject, SellwildWidgetViewDelegate {
        let onLoad: (() -> Void)?
        let onError: ((Error) -> Void)?

        init(onLoad: (() -> Void)?, onError: ((Error) -> Void)?) {
            self.onLoad = onLoad
            self.onError = onError
        }

        public func sellwildWidgetViewDidLoad(_ widgetView: SellwildWidgetView) {
            onLoad?()
        }

        public func sellwildWidgetView(_ widgetView: SellwildWidgetView, didFailWithError error: Error) {
            onError?(error)
        }
    }
}

// MARK: - SwiftUI Banner View

/// SwiftUI wrapper for SellwildAdView.
@available(iOS 14, *)
public struct SellwildAdBanner: UIViewRepresentable {
    public let config: SellwildConfig
    public let adSize: AdSize
    public let zoneId: String?
    public var onImpression: (() -> Void)?
    public var onError: ((Error) -> Void)?

    public init(
        config: SellwildConfig,
        adSize: AdSize,
        zoneId: String? = nil,
        onImpression: (() -> Void)? = nil,
        onError: ((Error) -> Void)? = nil
    ) {
        self.config = config
        self.adSize = adSize
        self.zoneId = zoneId
        self.onImpression = onImpression
        self.onError = onError
    }

    public func makeUIView(context: Context) -> SellwildAdView {
        let view = SellwildAdView(config: config, adSize: adSize, zoneId: zoneId)
        view.delegate = context.coordinator
        view.load()
        return view
    }

    public func updateUIView(_ uiView: SellwildAdView, context: Context) {}

    public func makeCoordinator() -> Coordinator {
        Coordinator(onImpression: onImpression, onError: onError)
    }

    public final class Coordinator: NSObject, SellwildAdViewDelegate {
        let onImpression: (() -> Void)?
        let onError: ((Error) -> Void)?

        init(onImpression: (() -> Void)?, onError: ((Error) -> Void)?) {
            self.onImpression = onImpression
            self.onError = onError
        }

        public func sellwildAdView(_ adView: SellwildAdView, didReceiveImpressionForZoneId zoneId: String) {
            onImpression?()
        }

        public func sellwildAdView(_ adView: SellwildAdView, didFailWithError error: Error) {
            onError?(error)
        }
    }
}

// MARK: - Preview

@available(iOS 14, *)
struct SellwildWidget_Previews: PreviewProvider {
    static var previews: some View {
        let config = SellwildConfig(
            partnerCode: "demo",
            listingsUrl: "https://api.sellwild.com/widget/listings?partner=demo"
        )
        SellwildWidget(config: config)
            .frame(height: 400)
            .previewLayout(.sizeThatFits)
    }
}

#endif
