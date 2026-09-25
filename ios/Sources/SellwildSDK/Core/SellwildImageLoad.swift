import UIKit

/// How an image download ended, for the feed's listing photos and native ad
/// assets (pure). It reuses the house-ad rules: an HTTP status outside 2xx is
/// a failed download, and a body over the 8 MB cap or not an image is refused.
///
/// Behavior change (phase 3): before, these two paths ignored the response,
/// so a non-2xx answer whose body decoded as an image was shown (and the feed
/// cached it). Now that answer is not shown and is reported as a failed
/// download, as iOS house ads already did and as Android does (its feed and
/// native ad images read `URL.openStream()`, which throws on HTTP 400 and up).
/// The 8 MB cap is unchanged.
enum SellwildImageLoad {

    enum Outcome {
        case image(UIImage)
        /// The caller cancelled the download (a reused cell). Not a failure
        /// (FAILURES.md 4.3).
        case cancelled
        /// The download failed: a transport error, or an HTTP status
        /// (`SellwildHouseAd.HTTPStatusError`).
        case network(Error)
        /// The body is too large or not an image.
        case invalid(SellwildHouseAd.ImageProblem)
    }

    static func outcome(data: Data?, response: URLResponse?, error: Error?) -> Outcome {
        switch SellwildHouseAd.downloadResult(data: data, response: response, error: error) {
        case .failure(let error):
            return SellwildLoadFailure.transport(error) == .cancelled ? .cancelled : .network(error)
        case .success(let body):
            return decoded(body)
        }
    }

    /// Image bytes (a download body, or a decoded data: URI) as an outcome.
    static func decoded(_ data: Data?) -> Outcome {
        switch SellwildHouseAd.decodeImage(data) {
        case .success(let image): return .image(image)
        case .failure(let problem): return .invalid(problem)
        }
    }

    /// The HTTP status of a failed download, when it answered with one.
    static func httpStatus(_ error: Error) -> Int? {
        (error as? SellwildHouseAd.HTTPStatusError)?.status
    }
}
