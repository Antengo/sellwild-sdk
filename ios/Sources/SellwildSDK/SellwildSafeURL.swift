import Foundation

/// Scheme allow-list for every externally-opened URL in the SDK.
///
/// House-ad click URLs (`MOBILE_HOUSE_AD_URL` and friends) come from remote CMS
/// config, and listing tap URLs come from remote listings data — both untrusted
/// inputs. Handing an arbitrary scheme to `UIApplication.open`
/// (`tel:`/`mailto:`/`itms://`/custom deep links) or to `SFSafariViewController`
/// (which throws on a non-http URL and crashes the app) is an injection / crash
/// vector. Only `http`/`https` are ever opened.
enum SellwildSafeURL {
    static func external(_ string: String?) -> URL? {
        guard let string, let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    /// Max bytes accepted for a remotely-fetched (or base64 `data:`) image, a
    /// guard against a hostile oversized creative causing an OOM. 8 MB is
    /// generous for any banner/MREC/native creative.
    static let maxImageBytes = 8 * 1024 * 1024

    /// A network image URL: `http`/`https` only. Reuses `external` so a `file://`
    /// value from remote config/listing data can't turn an image fetch into a
    /// local-file read. (`data:` is decoded inline by callers, size-capped.)
    static func imageURL(_ string: String?) -> URL? { external(string) }
}
