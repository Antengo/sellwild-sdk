// Compile-time stand-in for the React Native API, for native-checks/run.sh:
// only the members the RN bridge uses. Never shipped (package.json files).
package com.facebook.react.bridge;
import android.content.Context;
public class ReactApplicationContext extends ReactContext {
  public ReactApplicationContext(Context base) { super(base); }
}
