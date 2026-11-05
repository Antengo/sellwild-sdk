// Compile-time stand-in for the React Native API, for native-checks/run.sh:
// only the members the RN bridge uses. Never shipped (package.json files).
package com.facebook.react.bridge;
import java.util.HashMap;
import org.jetbrains.annotations.NotNull;
import org.jetbrains.annotations.Nullable;
public interface ReadableMap {
  boolean hasKey(@NotNull String name);
  boolean isNull(@NotNull String name);
  boolean getBoolean(@NotNull String name);
  double getDouble(@NotNull String name);
  int getInt(@NotNull String name);
  @Nullable String getString(@NotNull String name);
  @Nullable ReadableArray getArray(@NotNull String name);
  @Nullable ReadableMap getMap(@NotNull String name);
  @NotNull ReadableType getType(@NotNull String name);
  @NotNull HashMap<String, Object> toHashMap();
}
