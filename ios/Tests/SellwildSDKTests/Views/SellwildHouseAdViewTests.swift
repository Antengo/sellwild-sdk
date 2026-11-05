import XCTest
import UIKit
@testable import SellwildSDK

/// The house-ad backdrop: image mode, listing card mode, the stale-image
/// guard and the tap. Images load through the injected house image loader.
final class SellwildHouseAdViewTests: ViewTestCase {

    private func listing(_ overrides: [String: Any] = [:]) throws -> SellwildListing {
        try ListingFactory.decoded(ListingFactory.make(overrides))
    }

    func testAnImageFillsTheSlotWithoutTheCardChrome() {
        let view = SellwildHouseAdView(frame: CGRect(x: 0, y: 0, width: 300, height: 250))
        view.showImage(SellwildHouseAdCreative(imageURL: "https://cache.sellwild.com/house/a.png", clickURL: nil))
        XCTAssertTrue(view.titleLabel.isHidden)
        XCTAssertTrue(view.priceLabel.isHidden)
        XCTAssertEqual(view.imageView.contentMode, .scaleAspectFit)
        spin { view.imageView.image != nil }
        XCTAssertNotNil(view.imageView.image)
        capture.none()
    }

    func testAListingRendersAsACard() throws {
        let view = SellwildHouseAdView(frame: CGRect(x: 0, y: 0, width: 300, height: 250))
        let card = try listing(["title": "Road bike", "price": "250", "currency": "EUR"])
        view.showListing(card, config: SellwildConfig(partnerCode: "p"))
        XCTAssertFalse(view.titleLabel.isHidden)
        XCTAssertEqual(view.titleLabel.text, "Road bike")
        XCTAssertEqual(view.priceLabel.text, "€250")
        XCTAssertEqual(view.backgroundColor, .white)
        spin { view.imageView.image != nil }
        XCTAssertNotNil(view.imageView.image, "the listing photo loads")

        view.showImage(SellwildHouseAdCreative(imageURL: "", clickURL: nil))
        XCTAssertNil(view.imageView.image, "the old photo never lingers under new content")
        XCTAssertTrue(view.titleLabel.isHidden)
    }

    func testAnImageThatArrivesAfterTheContentChangedIsIgnored() throws {
        var pending: [(URL, (Result<Data, Error>) -> Void)] = []
        SellwildHouseAd.imageLoader = SellwildHouseAd.ImageLoader(
            download: { url, completion in DispatchQueue.main.async { pending.append((url, completion)) } },
            directory: { nil }
        )
        let view = SellwildHouseAdView(frame: CGRect(x: 0, y: 0, width: 300, height: 250))
        view.showImage(SellwildHouseAdCreative(imageURL: "https://cache.sellwild.com/house/old.png", clickURL: nil))
        view.showImage(SellwildHouseAdCreative(imageURL: "https://cache.sellwild.com/house/new.png", clickURL: nil))
        spin { pending.count == 2 }
        let old = try XCTUnwrap(pending.first { $0.0.lastPathComponent == "old.png" })
        old.1(.success(testPNG()))
        drainMain()
        XCTAssertNil(view.imageView.image, "the stale image is dropped")
        let new = try XCTUnwrap(pending.first { $0.0.lastPathComponent == "new.png" })
        new.1(.success(testPNG(width: 8)))
        spin { view.imageView.image != nil }
        XCTAssertEqual(view.imageView.image?.size.width, UIImage(data: testPNG(width: 8))?.size.width, "the new image")
    }

    func testAnImageForAViewThatIsGoneIsDropped() throws {
        var pending: [(Result<Data, Error>) -> Void] = []
        SellwildHouseAd.imageLoader = SellwildHouseAd.ImageLoader(
            download: { _, completion in DispatchQueue.main.async { pending.append(completion) } },
            directory: { nil }
        )
        weak var gone: SellwildHouseAdView?
        autoreleasepool {
            let view = SellwildHouseAdView(frame: .zero)
            view.showImage(SellwildHouseAdCreative(imageURL: "https://cache.sellwild.com/house/gone.png", clickURL: nil))
            gone = view
        }
        spin { pending.count == 1 }
        XCTAssertNil(gone)
        pending.first?(.success(testPNG()))
        drainMain()
        capture.none()
    }

    func testATapCallsOnTap() {
        let view = SellwildHouseAdView(frame: .zero)
        var taps = 0
        view.onTap = { taps += 1 }
        view.perform(NSSelectorFromString("tapped"))
        XCTAssertEqual(taps, 1)
        view.onTap = nil
        view.perform(NSSelectorFromString("tapped"))
        XCTAssertEqual(taps, 1)
    }
}
