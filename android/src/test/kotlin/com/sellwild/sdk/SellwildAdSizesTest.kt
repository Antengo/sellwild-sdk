package com.sellwild.sdk

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * [SellwildAdSizes.renderedSize]: the fork reports 0 when the winning bid has
 * no `w`/`h`; the host must get the primary size instead.
 */
class SellwildAdSizesTest {

    private val mrec = SellwildAdSizes.Size(300, 250)

    @Test fun keepsReportedSize() {
        assertEquals(SellwildAdSizes.Size(320, 50), SellwildAdSizes.renderedSize(SellwildAdSizes.Size(320, 50), mrec))
    }

    @Test fun zeroSizeFallsBackToPrimary() {
        assertEquals(mrec, SellwildAdSizes.renderedSize(SellwildAdSizes.Size(0, 0), mrec))
    }

    @Test fun halfZeroSizeFallsBackToPrimary() {
        assertEquals(mrec, SellwildAdSizes.renderedSize(SellwildAdSizes.Size(300, 0), mrec))
        assertEquals(mrec, SellwildAdSizes.renderedSize(SellwildAdSizes.Size(0, 250), mrec))
    }
}
