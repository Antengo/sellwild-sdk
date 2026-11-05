// Runtime stand-in for the Prebid fork's ExternalUserId, for
// native-checks/run.sh: the constructors SellwildPrebidMobile.applyEids calls.
package com.sellwild.prebid;

import java.util.List;
import java.util.Map;

public class ExternalUserId {
  public final String source;
  public final List<UniqueId> uniqueIds;

  public ExternalUserId(String source, List<UniqueId> uniqueIds) {
    this.source = source;
    this.uniqueIds = uniqueIds;
  }

  public static class UniqueId {
    public final String id;
    public final Integer atype;
    public Map<String, Object> ext;

    public UniqueId(String id, Integer atype) {
      this.id = id;
      this.atype = atype;
    }

    public void setExt(Map<String, Object> ext) { this.ext = ext; }
  }
}
