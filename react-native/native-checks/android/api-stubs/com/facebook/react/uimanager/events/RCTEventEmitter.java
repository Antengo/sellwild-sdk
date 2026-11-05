// Compile-time stand-in for the React Native API, for native-checks/run.sh:
// only the members the RN bridge uses. Never shipped (package.json files).
package com.facebook.react.uimanager.events;
import com.facebook.react.bridge.JavaScriptModule;
import com.facebook.react.bridge.WritableMap;
import org.jetbrains.annotations.Nullable;
public interface RCTEventEmitter extends JavaScriptModule {
  void receiveEvent(int targetTag, String eventName, @Nullable WritableMap event);
}
