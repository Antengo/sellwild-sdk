import SwiftUI
import UIKit
import SellwildSDK

/// Loads listings with `SellwildAPIClient` for an app that draws its own
/// cards. Refresh clears the client's cache and fetches again.
@MainActor
final class ListingsModel: ObservableObject {
    @Published private(set) var listings: [SellwildListing] = []
    @Published private(set) var photos: [String: UIImage] = [:]
    @Published private(set) var status = "Loading listings"
    private var loads = 0

    func load(config: SellwildConfig, clearCache: Bool) async {
        if clearCache { SellwildAPIClient.shared.clearCache() }
        loads += 1
        let load = loads
        status = "Loading listings (load \(load))"
        do {
            let response = try await SellwildAPIClient.shared.fetchListings(config: config)
            listings = response.listings
            photos = Self.inlinePhotos(response.listings)
            status = "\(response.listings.count) listings, load \(load)"
        } catch {
            // The SDK has already reported this failure; the app only shows it.
            status = "Listings failed (load \(load)): \(error.localizedDescription)"
        }
    }

    /// The feed's photos are data: URIs. Decode them once, not on every render.
    private static func inlinePhotos(_ listings: [SellwildListing]) -> [String: UIImage] {
        var photos: [String: UIImage] = [:]
        for listing in listings {
            guard let url = listing.primaryPhoto?.url, url.hasPrefix("data:"),
                  let comma = url.firstIndex(of: ","),
                  let data = Data(base64Encoded: String(url[url.index(after: comma)...])),
                  let image = UIImage(data: data) else { continue }
            photos[listing.id] = image
        }
        return photos
    }
}

/// Listings: the listings API client and the app's own list of cards.
struct ListingsScreen: View {
    let config: SellwildConfig
    @StateObject private var model = ListingsModel()
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                ScreenHeader(title: "Listings", detail: "SellwildAPIClient.fetchListings, drawn by the app.")
                Button("Refresh") {
                    Task { await model.load(config: config, clearCache: true) }
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 12)
                .padding(.trailing, 16)
                .accessibilityIdentifier(SampleID.listingsRefresh)
            }
            Text(model.status)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .accessibilityIdentifier(SampleID.listingsStatus)
            List(model.listings) { listing in
                Button {
                    if let link = listing.tapURL(partnerCode: config.partnerCode), let url = URL(string: link) {
                        openURL(url)
                    }
                } label: {
                    ListingCard(listing: listing, photo: model.photos[listing.id])
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(SampleID.listingCard)
            }
            .listStyle(.plain)
            .refreshable { await model.load(config: config, clearCache: true) }
            .accessibilityIdentifier(SampleID.listingsList)
        }
        .task {
            if model.listings.isEmpty { await model.load(config: config, clearCache: false) }
        }
    }
}

/// One listing: photo, title, price and seller.
struct ListingCard: View {
    let listing: SellwildListing
    let photo: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                } else if let link = listing.primaryPhoto?.url, link.hasPrefix("http"), let url = URL(string: link) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.gray.opacity(0.2)
                    }
                } else {
                    Color.gray.opacity(0.2)
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(listing.title).font(.subheadline).lineLimit(2)
                if let price = listing.displayPrice {
                    Text("$\(price)").font(.footnote.weight(.semibold))
                }
                if let seller {
                    Text("by \(seller)").font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    /// "Nick P.", from the seller's first name and last initial.
    private var seller: String? {
        let first = listing.user?.firstName?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !first.isEmpty else { return nil }
        guard let initial = listing.user?.lastName?.first else { return first }
        return "\(first) \(initial)."
    }
}
