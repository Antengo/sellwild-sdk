import Foundation

extension SellwildListing {

    /// The URL a listing card should open when tapped. Mirrors the web widget's
    /// `getListingUrl()` so native feeds route to the same destination as
    /// `widget.sellwild.com/partner.js`:
    ///   1. `listing.url`               (legacy direct URL, optionally rewritten with `bhTag`)
    ///   2. `dataSourceId == "31"` + `remote_url` (off-platform partner deep link)
    ///   3. `https://sellwild.com/product/{id}?p={partner}&utm_source={partner}` (canonical fallback)
    ///
    /// A sellwild.com result also carries `readerId` as `sw_wuid`, so
    /// sellwild.com can match this reader to their visit
    /// (`SellwildReaderLink`). It defaults to the SDK's stored reader id,
    /// `SellwildSession.shared.uid`; an empty id adds nothing.
    public func tapURL(
        partnerCode: String?,
        bhTag: String? = nil,
        readerId: String? = SellwildSession.shared.uid
    ) -> String? {
        destinationURL(partnerCode: partnerCode, bhTag: bhTag)
            .map { SellwildReaderLink.withReaderId($0, readerId: readerId) }
    }

    private func destinationURL(partnerCode: String?, bhTag: String?) -> String? {
        // 1. Direct URL on the listing.
        if let s = url, !s.isEmpty {
            if let tag = bhTag, !tag.isEmpty,
               var comps = URLComponents(string: s) {
                var items = comps.queryItems ?? []
                items.removeAll { $0.name == "tag" }
                items.append(URLQueryItem(name: "tag", value: tag))
                comps.queryItems = items
                if let out = comps.string { return out }
            }
            return s
        }
        // 2. Off-platform remote_url (only when dataSourceId == "31", matching web widget).
        if dataSourceId == "31", let s = remoteUrl, !s.isEmpty {
            return s
        }
        // 3. Canonical Sellwild product URL.
        guard !id.isEmpty else { return nil }
        let partner = (partnerCode?.isEmpty == false) ? partnerCode! : "sellwild"
        let encoded = partner.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? partner
        return "https://sellwild.com/product/\(id)?p=\(encoded)&utm_source=\(encoded)"
    }
}
