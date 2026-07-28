#import <React/RCTBridgeModule.h>

// Exposes the Swift SellwildRNModule to React Native. Method signatures must
// match the @objc selectors in SellwildRNModule.swift.
@interface RCT_EXTERN_MODULE(SellwildRNModule, NSObject)

RCT_EXTERN_METHOD(setGeo:(NSDictionary *)geo)
RCT_EXTERN_METHOD(setExternalUserIds:(NSArray *)eids)

@end
