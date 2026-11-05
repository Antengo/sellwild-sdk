package com.sellwild.sdk.core

import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailureComponent
import com.sellwild.sdk.failures.SellwildFailureSeverity
import org.json.JSONArray
import org.json.JSONObject

/** Pure pieces of the Prebid Mobile bootstrap. */
internal object PrebidSetup {

    /**
     * The one global ORTB config (setGlobalOrtbConfig is last-write-wins): `app.publisher.id`,
     * `app.cat` and `device.geo`, each only when set. Null when there is nothing to send.
     */
    fun globalOrtb(publisherId: String?, cats: List<String>?, geo: JSONObject?): String? {
        val root = JSONObject()
        val app = JSONObject()
        if (!publisherId.isNullOrEmpty()) app.put("publisher", JSONObject().put("id", publisherId))
        if (!cats.isNullOrEmpty()) app.put("cat", JSONArray(cats))
        if (app.length() > 0) root.put("app", app)
        if (geo != null) root.put("device", JSONObject().put("geo", geo))
        return if (root.length() > 0) root.toString() else null
    }

    /**
     * The issue for how Prebid Mobile init finished: none for SUCCEEDED, else
     * ad.prebid_init.invalid with the status and the fork's description. [statusName] is the
     * fork's InitializationStatus name; null (a completion without a status) is not a success.
     * The SDK still counts init as finished either way: a failed init self-corrects, because
     * the auction runs, misses and GAM serves.
     */
    fun initStatus(statusName: String?, description: String?): Issue? {
        if (statusName == "SUCCEEDED") return null
        val detail = if (description.isNullOrEmpty()) "" else ": $description"
        return Issue(
            SellwildFailureCode.AD_PREBID_INIT_INVALID,
            SellwildFailureComponent.BANNER,
            SellwildFailureSeverity.WARN,
            message = "Prebid init finished with status $statusName$detail",
        )
    }

    /**
     * The issue for a Prebid auction result: ad.prebid_auction.invalid when it is a failure
     * other than no bids or a timeout without bids ([AdDecisions.isAuctionFailure]), else none.
     */
    fun auctionResult(resultName: String?, component: String, zoneId: String?): Issue? {
        if (!AdDecisions.isAuctionFailure(resultName)) return null
        return Issue(
            SellwildFailureCode.AD_PREBID_AUCTION_INVALID,
            component,
            SellwildFailureSeverity.WARN,
            message = "Prebid auction result $resultName",
            zoneId = zoneId,
        )
    }
}
