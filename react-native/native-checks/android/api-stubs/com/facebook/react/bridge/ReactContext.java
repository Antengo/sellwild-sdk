// Compile-time stand-in for the React Native API, for native-checks/run.sh:
// only the members the RN bridge uses. Never shipped (package.json files).
package com.facebook.react.bridge;
import android.content.Context;
import android.content.ContextWrapper;
public class ReactContext extends ContextWrapper {
  public ReactContext(Context base) { super(base); }
  public <T extends JavaScriptModule> T getJSModule(Class<T> jsInterface) { throw new UnsupportedOperationException("stub"); }
}
