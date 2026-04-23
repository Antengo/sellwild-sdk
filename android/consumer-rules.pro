# Consumer ProGuard rules — these are bundled into the AAR and applied automatically
# to any app that depends on the Sellwild SDK.

# Keep the JS bridge interface so WebView can invoke it at runtime
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Keep the public model classes used in listener callbacks
-keep public class com.sellwild.sdk.SellwildListing { *; }
-keep public class com.sellwild.sdk.SellwildPhoto { *; }
-keep public class com.sellwild.sdk.SellwildConfig { *; }
-keep public enum com.sellwild.sdk.AdSize { *; }
