// Runtime stand-in for the Prebid fork's TargetingParams, for
// native-checks/run.sh: records what SellwildPrebidMobile hands it, so a JVM
// check can see the geo and eids that reached the auction.
package com.sellwild.prebid;

import java.util.List;

public class TargetingParams {
  public static String lastGlobalOrtb;
  public static List<ExternalUserId> lastExternalUserIds;
  public static int externalUserIdCalls;

  public static void setGlobalOrtbConfig(String ortb) { lastGlobalOrtb = ortb; }

  public static void setExternalUserIds(List<ExternalUserId> ids) {
    lastExternalUserIds = ids;
    externalUserIdCalls++;
  }
}
