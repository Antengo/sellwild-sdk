package com.sellwild.sdk

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri

/**
 * Captures the application Context at app start (manifest-merged from the AAR,
 * the same auto-init pattern Firebase / WorkManager use) so [SellwildSDK.configure]
 * can pre-warm the native ad stack without taking a Context parameter. It does
 * no other work and never serves data.
 */
internal class SellwildInitProvider : ContentProvider() {
    override fun onCreate(): Boolean {
        context?.applicationContext?.let { SellwildSDK.appContext = it }
        return true
    }

    override fun query(uri: Uri, projection: Array<String>?, selection: String?, selectionArgs: Array<String>?, sortOrder: String?): Cursor? = null
    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<String>?): Int = 0
}
