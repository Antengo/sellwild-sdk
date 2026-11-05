package com.sellwild.sdk;

import static org.junit.Assert.assertEquals;

import android.content.Context;
import androidx.test.core.app.ApplicationProvider;
import com.google.android.gms.ads.admanager.AdManagerAdView;
import com.sellwild.prebid.ResultCode;
import com.sellwild.sdk.failures.FailuresRule;
import com.sellwild.sdk.support.NetworkBlockRule;
import java.util.Collections;
import org.junit.Rule;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;

/**
 * Java callers keep the runBannerAuction overload with no completion (@JvmOverloads). Kotlin
 * callers go through the default-argument bridge instead, so only a Java caller reaches it.
 */
@RunWith(RobolectricTestRunner.class)
public class JavaAuctionCallerTest {

    @Rule
    public final NetworkBlockRule network = new NetworkBlockRule();

    @Rule
    public final FailuresRule failures = new FailuresRule();

    @Rule
    public final AdNetworkRule ads = new AdNetworkRule();

    @Test
    public void theAuctionWithoutACompletionStillExistsAndLoadsGam() {
        Context context = ApplicationProvider.getApplicationContext();

        SellwildPrebidMobile.runBannerAuction(
            new AdManagerAdView(context), "43", 300, 250, Collections.emptyMap(), false, Collections.emptyList(), "/1/feed");
        AdNetworkAccess.finishBannerAuction(ads, ResultCode.SUCCESS);

        assertEquals(1, AdNetworkAccess.bannerAuctions(ads));
        assertEquals(1, AdNetworkAccess.gamLoads(ads));
    }
}
