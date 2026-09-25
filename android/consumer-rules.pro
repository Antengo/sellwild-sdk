# Consumer ProGuard rules — these are bundled into the AAR and applied automatically
# to any app that depends on the Sellwild SDK.

# Keep @JavascriptInterface methods app-wide. Not widget-only: the ad SDKs'
# creative WebViews (e.g. Prebid's MRAID bridge, com.sellwild.prebid...
# BaseJSInterface) are called only from JS, and R8 would strip them.
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Keep the public model classes used in listener callbacks
-keep public class com.sellwild.sdk.SellwildListing { *; }
-keep public class com.sellwild.sdk.SellwildPhoto { *; }
-keep public class com.sellwild.sdk.SellwildConfig { *; }
-keep public enum com.sellwild.sdk.AdSize { *; }
