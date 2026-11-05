package com.sellwild.sdk;

import static org.junit.Assert.assertEquals;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import kotlinx.coroutines.Dispatchers;
import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

/**
 * Java callers keep the signatures they had before new optional parameters were added
 * (@JvmOverloads): the 3-argument push/track of the events queue and the 3-argument merge
 * of localized listings. Kotlin callers go through the default-argument bridges instead, so
 * only a Java caller reaches these overloads.
 */
public class JavaCallersTest {

    @Test
    public void theThreeArgumentPushAndTrackStillExist() throws Exception {
        List<String> bodies = new ArrayList<>();
        SellwildEventQueue queue = new SellwildEventQueue(
            () -> "u-1",
            (url, body) -> {
                bodies.add(body);
                return 200;
            },
            () -> 1_790_000_000_000L,
            Dispatchers.getUnconfined());

        queue.track("adError", "No ad to show.", "43");
        queue.push("click", "listing", "280");
        queue.track("firstAdViewed");

        // push only queues; the next track sends it with its own event.
        assertEquals(2, bodies.size());
        JSONObject first = new JSONArray(bodies.get(0)).getJSONObject(0);
        assertEquals("adError", first.getString("event"));
        assertEquals("43", first.getString("label"));
        JSONArray second = new JSONArray(bodies.get(1));
        assertEquals("click", second.getJSONObject(0).getString("event"));
        assertEquals("280", second.getJSONObject(0).getString("label"));
        assertEquals("firstAdViewed", second.getJSONObject(1).getString("event"));
    }

    @Test
    public void theThreeArgumentMergeStillExists() {
        SellwildListing p1 = new SellwildListing("p1", "1", "one", null, null, null, null, null, null, false, new ArrayList<>(), null, null, null, null, null, null);
        SellwildListing p2 = new SellwildListing("p2", "1", "two", null, null, null, null, null, null, false, new ArrayList<>(), null, null, null, null, null, null);
        SellwildListing s1 = new SellwildListing("s1", "1", "local", null, null, null, null, null, null, false, new ArrayList<>(), null, null, null, null, null, null);

        List<SellwildListing> merged = SellwildLocalizedListings.INSTANCE.merge(Arrays.asList(p1, p2), Arrays.asList(s1), 2);

        assertEquals(Arrays.asList("p1", "s1"), Arrays.asList(merged.get(0).getId(), merged.get(1).getId()));
    }
}
