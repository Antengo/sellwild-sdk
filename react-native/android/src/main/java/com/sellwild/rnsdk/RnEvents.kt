package com.sellwild.rnsdk

import com.facebook.react.bridge.ReactContext
import com.facebook.react.bridge.WritableMap
import com.facebook.react.uimanager.events.RCTEventEmitter
import com.sellwild.sdk.failures.SellwildFailureCode
import com.sellwild.sdk.failures.SellwildFailureComponent
import com.sellwild.sdk.failures.SellwildFailureSeverity
import com.sellwild.sdk.failures.SellwildFailures

/** Sends the view managers' events to JS. */
internal object RnEvents {
    /**
     * Sends [name] with [payload] to the JS view [viewId]. When the React
     * instance is gone (a reload or teardown) the event has nowhere to go: it
     * is dropped and reported (`bridge.event_emit.exception`). It used to
     * crash the host app.
     */
    fun emit(context: ReactContext, viewId: Int, name: String, payload: WritableMap?) {
        try {
            context.getJSModule(RCTEventEmitter::class.java).receiveEvent(viewId, name, payload)
        } catch (e: Exception) {
            SellwildFailures.log(
                code = SellwildFailureCode.BRIDGE_EVENT_EMIT_EXCEPTION,
                component = SellwildFailureComponent.BRIDGE,
                severity = SellwildFailureSeverity.WARN,
                error = e,
                message = "$name could not reach JS",
            )
        }
    }
}
