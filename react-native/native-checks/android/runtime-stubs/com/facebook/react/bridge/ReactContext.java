// Runtime stand-in, for native-checks/run.sh: a ReactContext that needs no
// Android Context, so the JVM checks can construct SellwildModule. The bridge
// is compiled against the Context-based API stub; the JVM links by name, so
// this class takes its place at run time.
package com.facebook.react.bridge;

public class ReactContext {
  /**
   * What getJSModule returns. Null stands for a React instance that is gone
   * (a reload or teardown): getJSModule then throws, as React Native does.
   */
  public static Object jsModule;

  public ReactContext() {}

  public <T extends JavaScriptModule> T getJSModule(Class<T> jsInterface) {
    if (jsModule == null) throw new IllegalStateException("the React instance is gone");
    return jsInterface.cast(jsModule);
  }
}
