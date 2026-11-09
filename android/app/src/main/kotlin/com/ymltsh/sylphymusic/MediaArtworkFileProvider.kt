package com.ymltsh.sylphymusic

import android.content.Intent
import android.net.Uri
import android.os.ParcelFileDescriptor
import androidx.core.content.FileProvider
import java.io.FileNotFoundException

/**
 * Serves only the materialized media-session artwork cache. SystemUI, Bluetooth
 * and Android Auto are separate processes and cannot read app-private file://.
 * The provider itself stays non-exported; grant read access to exact URIs.
 * Same approach as Linthra's MediaArtworkFileProvider.
 */
class MediaArtworkFileProvider : FileProvider() {
    @Throws(FileNotFoundException::class)
    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor? {
        if (mode != "r") throw FileNotFoundException("Read-only media artwork")
        val fd = super.openFile(uri, mode)
        // audio_service loads this URI in our own process before publishing the
        // metadata, granting cross-process consumers the same narrow URI.
        for (consumer in MEDIA_CONSUMERS) {
            try {
                context?.grantUriPermission(
                    consumer, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            } catch (_: Exception) {
                // Optional consumer may not be installed. Never affect audio.
            }
        }
        return fd
    }

    companion object {
        private val MEDIA_CONSUMERS = listOf(
            "com.android.systemui",
            "com.miui.systemui",
            "com.android.bluetooth",
            "com.google.android.projection.gearhead"
        )
    }
}
