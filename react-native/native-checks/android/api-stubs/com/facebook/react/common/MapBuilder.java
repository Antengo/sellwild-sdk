// Compile-time stand-in for the React Native API, for native-checks/run.sh:
// only the members the RN bridge uses. Never shipped (package.json files).
package com.facebook.react.common;
import java.util.HashMap;
import java.util.Map;
public class MapBuilder {
  public static <K, V> Map<K, V> of(K k1, V v1) { Map<K, V> m = new HashMap<>(); m.put(k1, v1); return m; }
  public static <K, V> Builder<K, V> builder() { return new Builder<>(); }
  public static final class Builder<K, V> {
    private final Map<K, V> map = new HashMap<>();
    public Builder<K, V> put(K k, V v) { map.put(k, v); return this; }
    public Map<K, V> build() { return map; }
  }
}
