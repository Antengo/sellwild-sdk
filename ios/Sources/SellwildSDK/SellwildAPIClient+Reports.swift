import Foundation

// SellwildAPIClient's failure reports and CloudFront geo seeding, apart so the
// client's own file stays within its size budget.
extension SellwildAPIClient {

    /// A per-state cache that does not exist answers 403 (S3 AccessDenied) or
    /// 404. That is a normal skip, not a failure.
    static func isMissingStateCache(status: Int) -> Bool {
        status == 403 || status == 404
    }

    /// Reports a transport error of a listings or localized fetch. A
    /// cancelled load is the caller's choice, not a failure.
    static func reportTransportError(_ error: Error, component: SellwildFailureComponent, url: String) {
        let localized = component == .localized
        switch SellwildLoadFailure.transport(error) {
        case .cancelled:
            SellwildLog.debug("[SellwildAPIClient] \(component.rawValue) fetch cancelled")
        case .timeout:
            SellwildFailures.log(code: localized ? .localizedFetchTimeout : .listingsFetchTimeout,
                                 component: component, error: error, url: url,
                                 context: ["file": SellwildFailures.urlFileName(url)])
        case .network:
            SellwildFailures.log(code: localized ? .localizedFetchNetwork : .listingsFetchNetwork,
                                 component: component, error: error, url: url,
                                 context: ["file": SellwildFailures.urlFileName(url)])
        }
    }

    /// Reports what was wrong inside a body that parsed: no `result.rs` list,
    /// and items that could not be decoded (one report per body).
    static func reportParseProblems(_ parsed: SellwildListingsCore.Parsed, component: SellwildFailureComponent,
                                    url: String) {
        if let problem = parsed.rsProblem {
            SellwildFailures.log(code: .listingsParseInvalid, component: component, message: problem, url: url)
        }
        if parsed.dropped > 0 {
            SellwildFailures.log(code: .listingsItemParse, component: component, error: parsed.firstDropError,
                                 message: "\(parsed.dropped) listing(s) could not be decoded and were dropped",
                                 url: url)
        }
    }

    /// Seed `SellwildGeoStore` region + country from the CloudFront viewer
    /// headers when not already set, then re-emit so `device.geo` reaches the
    /// auction. `applyGlobalORTB()` runs only at bootstrap + `setGeo(_:)` (not
    /// per-auction), so a bare store write would never make it into a request —
    /// `setGeo` persists the store AND re-emits. Never overwrites a
    /// partner-supplied or previously-seeded value. Country is restricted to a
    /// North America alpha-2 → alpha-3 map (oRTB wants alpha-3); anything outside
    /// NA is skipped rather than sent unmapped.
    static func seedGeoFromCloudFrontIfEmpty(from response: HTTPURLResponse) {
        var geo = SellwildGeoStore.current ?? SellwildGeo()
        var changed = false

        if (geo.state ?? "").isEmpty,
           let region = response.value(forHTTPHeaderField: "CloudFront-Viewer-Country-Region")?
               .trimmingCharacters(in: .whitespacesAndNewlines), !region.isEmpty {
            geo.state = region
            changed = true
        }

        if (geo.country ?? "").isEmpty,
           let alpha2 = response.value(forHTTPHeaderField: "CloudFront-Viewer-Country")?
               .trimmingCharacters(in: .whitespacesAndNewlines), !alpha2.isEmpty,
           let alpha3 = SellwildGeo.northAmericaAlpha3(alpha2: alpha2) {
            geo.country = alpha3
            changed = true
        }

        guard changed else { return }
        SellwildPrebidMobile.setGeo(geo)
    }

    /// One listings request in flight: its URL, cache key and fetch timer.
    struct ListingsRequest {
        var url: String
        var cacheKey: NSString
        var fetchTimer: () -> Double
    }

    /// What URLSession handed back for it.
    struct ListingsAnswer {
        var data: Data?
        var response: URLResponse?
        var error: Error?
    }

    /// What one listings answer means: reports each failure once and hands
    /// `finish` the result. `client` is nil when the client went away
    /// mid-request.
    static func deliverListings(
        client: SellwildAPIClient?, request: ListingsRequest,
        answer: ListingsAnswer,
        finish: (Result<SellwildListingsResponse, Error>) -> Void
    ) {
        let urlString = request.url
        let data = answer.data, response = answer.response, error = answer.error
        if let error = error {
            reportTransportError(error, component: .listings, url: urlString)
            finish(.failure(error))
            return
        }
        guard let data = data else {
            SellwildFailures.log(code: .listingsFetchMissing, component: .listings,
                                 message: "listings response has no body", url: urlString)
            finish(.failure(SellwildError.noData))
            return
        }
        // Seed the geo state from CloudFront's viewer-country-region header
        // when the partner hasn't supplied one, so the localized-listings
        // path can key a per-state cache. Mirrors the web widget's
        // appendViewerHeaders seeding userLocation.state.
        if let http = response as? HTTPURLResponse {
            seedGeoFromCloudFrontIfEmpty(from: http)
        }
        if let status = SellwildLoadFailure.httpFailureStatus(response) {
            SellwildFailures.log(code: .listingsFetchHttp, component: .listings,
                                 message: "HTTP \(status)", httpStatus: status, url: urlString,
                                 context: ["file": SellwildFailures.urlFileName(urlString)])
            finish(.failure(SellwildError.invalidResponse))
            return
        }
        _ = request.fetchTimer()
        guard let client else {
            // The client went away mid-request: nothing can cache or use
            // the answer, so an empty feed is delivered, as before.
            SellwildFailures.log(code: .listingsClientMissing, component: .listings, severity: .warn,
                                 message: "listings client released while a request was in flight", url: urlString)
            finish(.success(SellwildListingsCore.empty))
            return
        }
        let decodeTimer = SellwildTiming.start("listings.decode")
        let parsed = SellwildListingsCore.parse(data)
        if case .success = parsed { _ = decodeTimer() }
        switch parsed {
        case .failure(.notJSON(let parseError)):
            SellwildFailures.log(code: .listingsFetchParse, component: .listings, error: parseError, url: urlString,
                                 context: ["file": SellwildFailures.urlFileName(urlString)])
            finish(.failure(parseError))
        case .failure(.notAnObject):
            SellwildFailures.log(code: .listingsParseInvalid, component: .listings,
                                 message: "listings JSON is not an object", url: urlString)
            finish(.failure(SellwildError.invalidResponse))
        case .success(let parsed):
            reportParseProblems(parsed, component: .listings, url: urlString)
            client.listingCache.setObject(ListingsCacheEntry(response: parsed.response), forKey: request.cacheKey)
            finish(.success(parsed.response))
        }
    }
}
