@testable import SellwildSDK

/// The SDK's `AdSize`, named apart from GoogleMobileAds' `AdSize` for test
/// files that import both. (The module also has an enum named `SellwildSDK`,
/// so `SellwildSDK.AdSize` does not resolve.)
typealias SellwildAdSize = AdSize
