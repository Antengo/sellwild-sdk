// Compile-time stand-in for the React Native API, for native-checks/run.sh:
// only the members the RN bridge uses. Never shipped (package.json files).
package com.facebook.react.bridge;
public class Arguments {
  public static WritableMap createMap() { throw new UnsupportedOperationException("stub"); }
}
