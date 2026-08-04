#import <React/RCTViewManager.h>
#import <React/RCTUIManager.h>
#import <React/RCTBridgeModule.h>

// Register the view manager class with React Native. We export it under
// the JS name "SellwildBannerView" to match the Android side
// (com.sellwild.rnsdk.SellwildBannerViewManager.REACT_CLASS).
@interface RCT_EXTERN_REMAP_MODULE(SellwildBannerView,
                                   SellwildBannerViewManager,
                                   RCTViewManager)

// Props set from JS — these forward to @objc properties on
// SellwildBannerHostView.
RCT_EXPORT_VIEW_PROPERTY(config, NSDictionary)
RCT_EXPORT_VIEW_PROPERTY(size, NSString)
RCT_EXPORT_VIEW_PROPERTY(zoneId, NSString)
RCT_EXPORT_VIEW_PROPERTY(adStack, NSString)

// Direct events emitted to JS callbacks.
RCT_EXPORT_VIEW_PROPERTY(onAdLoaded, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onAdImpression, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onHouseAdImpression, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onAdClicked, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onAdFailed, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onAdResize, RCTDirectEventBlock)

@end
