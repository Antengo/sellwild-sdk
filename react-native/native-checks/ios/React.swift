// A stand-in for the React Native iOS API the Sellwild RN bridge uses, so
// native-checks/run.mjs can type-check react-native/ios against the built
// SellwildSDK module without an RN host app. Never shipped.
import Foundation
import UIKit

public typealias RCTDirectEventBlock = ([AnyHashable: Any]?) -> Void

open class RCTViewManager: NSObject {
    public override init() { super.init() }
    open class func requiresMainQueueSetup() -> Bool { false }
    open func view() -> UIView! { nil }
}

extension UIView {
    @objc open func didSetProps(_ changedProps: [String]) {}
}
