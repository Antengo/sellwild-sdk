// Compile-time stand-in for the React Native API, for native-checks/run.sh:
// only the members the RN bridge uses. Never shipped (package.json files).
package com.facebook.react.bridge;
import org.jetbrains.annotations.NotNull;
public abstract class ReactContextBaseJavaModule implements NativeModule {
  private final ReactApplicationContext context;
  public ReactContextBaseJavaModule(@NotNull ReactApplicationContext reactContext) { this.context = reactContext; }
  protected final @NotNull ReactApplicationContext getReactApplicationContext() { return context; }
}
