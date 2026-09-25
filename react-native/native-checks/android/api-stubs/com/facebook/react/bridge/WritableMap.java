// Compile-time stand-in for the React Native API, for native-checks/run.sh:
// only the members the RN bridge uses. Never shipped (package.json files).
package com.facebook.react.bridge;
import org.jetbrains.annotations.NotNull;
import org.jetbrains.annotations.Nullable;
public interface WritableMap extends ReadableMap {
  void putString(@NotNull String key, @Nullable String value);
  void putInt(@NotNull String key, int value);
  void putMap(@NotNull String key, @Nullable ReadableMap value);
}
