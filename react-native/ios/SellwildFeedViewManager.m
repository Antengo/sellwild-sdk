#import <React/RCTViewManager.h>
#import <React/RCTUIManager.h>
#import <React/RCTBridgeModule.h>

// Register the view manager class with React Native. We export it under
// the JS name "SellwildFeedView" to match the Android side
// (com.sellwild.rnsdk.SellwildFeedViewManager.REACT_CLASS).
@interface RCT_EXTERN_REMAP_MODULE(SellwildFeedView,
                                   SellwildFeedViewManager,
                                   RCTViewManager)

// Props set from JS — these forward to @objc properties on
// SellwildFeedHostView.
RCT_EXPORT_VIEW_PROPERTY(config, NSDictionary)
RCT_EXPORT_VIEW_PROPERTY(scrollEnabled, BOOL)

// Direct events emitted to JS callbacks.
RCT_EXPORT_VIEW_PROPERTY(onFeedLoaded, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onListingTap, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onAdImpression, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onHouseAdImpression, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onAdClicked, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onFeedError, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onContentSizeChange, RCTDirectEventBlock)

@end
