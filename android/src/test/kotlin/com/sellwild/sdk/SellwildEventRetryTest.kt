package com.sellwild.sdk

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Event batches are re-queued on retryable statuses; permanent 4xx rejections
 * are dropped. (Network exceptions always retry — see SellwildEventQueue.flush.)
 */
class SellwildEventRetryTest {

    @Test
    fun `success is not retried`() {
        assertFalse(SellwildEventQueue.isRetryableStatus(200))
        assertFalse(SellwildEventQueue.isRetryableStatus(204))
    }

    @Test
    fun `server errors and transient 4xx are retried`() {
        listOf(500, 503, 408, 429).forEach { assertTrue("$it", SellwildEventQueue.isRetryableStatus(it)) }
    }

    @Test
    fun `permanent 4xx is dropped`() {
        listOf(400, 403, 413).forEach { assertFalse("$it", SellwildEventQueue.isRetryableStatus(it)) }
    }
}
