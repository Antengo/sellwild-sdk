// Runtime stand-in, for native-checks/run.sh: keeps what the bridge queues
// for the UI thread instead of running it, so a check can see it was queued.
package com.facebook.react.bridge;

import java.util.ArrayList;
import java.util.List;

public class UiThreadUtil {
  public static final List<Runnable> queued = new ArrayList<>();

  public static void runOnUiThread(Runnable runnable) { queued.add(runnable); }
}
