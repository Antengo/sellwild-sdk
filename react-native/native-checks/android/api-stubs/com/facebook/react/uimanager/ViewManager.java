// Compile-time stand-in for the React Native API, for native-checks/run.sh:
// only the members the RN bridge uses. Never shipped (package.json files).
package com.facebook.react.uimanager;
import android.view.View;
import java.util.Map;
import org.jetbrains.annotations.NotNull;
import org.jetbrains.annotations.Nullable;
public abstract class ViewManager<T extends View, C extends ReactShadowNode> {
  public abstract @NotNull String getName();
  protected abstract @NotNull T createViewInstance(@NotNull ThemedReactContext reactContext);
  protected void onAfterUpdateTransaction(@NotNull T view) {}
  public void onDropViewInstance(@NotNull T view) {}
  public @Nullable Map<String, Object> getExportedCustomDirectEventTypeConstants() { return null; }
}
