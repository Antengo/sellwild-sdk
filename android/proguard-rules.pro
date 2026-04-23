# Sellwild SDK ProGuard rules
# These apply only when the SDK is compiled as part of an app that enables minification.

# Keep the public SDK surface
-keep public class com.sellwild.sdk.SellwildConfig { *; }
-keep public class com.sellwild.sdk.SellwildListing { *; }
-keep public class com.sellwild.sdk.SellwildPhoto { *; }
-keep public class com.sellwild.sdk.SellwildListingsResponse { *; }
-keep public class com.sellwild.sdk.SellwildWidgetView { *; }
-keep public class com.sellwild.sdk.SellwildAdView { *; }
-keep public interface com.sellwild.sdk.SellwildWidgetView$Listener { *; }
-keep public interface com.sellwild.sdk.SellwildAdView$Listener { *; }
-keep public enum com.sellwild.sdk.AdSize { *; }

# Keep the JS bridge — methods annotated with @JavascriptInterface must not be renamed
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Keep JSON serialisation fields for SellwildListing (parsed from API responses)
-keepclassmembers class com.sellwild.sdk.SellwildListing {
    <fields>;
}
-keepclassmembers class com.sellwild.sdk.SellwildPhoto {
    <fields>;
}
