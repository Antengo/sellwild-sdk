// Compile-time stand-in for the React Native API, for native-checks/run.sh:
// only the members the RN bridge uses. Never shipped (package.json files).
package com.facebook.react.bridge;
import org.jetbrains.annotations.NotNull;
import org.jetbrains.annotations.Nullable;
public interface ReadableArray {
  int size();
  boolean isNull(int index);
  int getInt(int index);
  @Nullable String getString(int index);
  @Nullable ReadableMap getMap(int index);
  @NotNull ReadableType getType(int index);
}
