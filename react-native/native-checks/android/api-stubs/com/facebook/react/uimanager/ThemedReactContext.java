// Compile-time stand-in for the React Native API, for native-checks/run.sh:
// only the members the RN bridge uses. Never shipped (package.json files).
package com.facebook.react.uimanager;
import android.content.Context;
import com.facebook.react.bridge.ReactContext;
public class ThemedReactContext extends ReactContext {
  public ThemedReactContext(Context base) { super(base); }
}
