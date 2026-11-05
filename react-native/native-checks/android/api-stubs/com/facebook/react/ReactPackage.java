// Compile-time stand-in for the React Native API, for native-checks/run.sh:
// only the members the RN bridge uses. Never shipped (package.json files).
package com.facebook.react;
import com.facebook.react.bridge.NativeModule;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.uimanager.ViewManager;
import java.util.List;
import org.jetbrains.annotations.NotNull;
public interface ReactPackage {
  @NotNull List<NativeModule> createNativeModules(@NotNull ReactApplicationContext reactContext);
  @NotNull List<ViewManager> createViewManagers(@NotNull ReactApplicationContext reactContext);
}
