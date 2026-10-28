package com.ymltsh.sylphymusic

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.os.Build

/** Only user-initiated index/tag work may start this dataSync FGS.
 * The service leases the audio_service engine and renders progress;
 * network/SQLite work stays in Dart. Never auto-restart after process death.
 */
class SyncForegroundService : LeasedDataSyncService() {
    override val owner = "sync"
    override val notificationId = 43
    override fun registerInstance() { instance = this }
    override fun clearInstance() { if (instance === this) instance = null }
    override fun notification(): Notification {
        notifications = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) notifications.createNotificationChannel(NotificationChannel(CHANNEL, "音乐库同步", NotificationManager.IMPORTANCE_LOW))
        return buildNotification("风灵音乐 · 正在同步", "正在读取音乐库", 0, 0)
    }
    companion object {
        @Volatile var instance: SyncForegroundService? = null
        private const val CHANNEL = "sylphy_library_sync"
        private const val ID = 43
    }

    private lateinit var notifications: NotificationManager
    private fun buildNotification(title: String, detail: String, done: Int, total: Int): Notification {
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val pause = PendingIntent.getService(
            this, 43, Intent(this, SyncForegroundService::class.java).setAction("pause"),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, CHANNEL)
        } else {
            Notification.Builder(this)
        }
        builder.setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(title.take(80))
            .setContentText(detail.take(120))
            .setContentIntent(open)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .addAction(Notification.Action.Builder(null, "暂停同步", pause).build())
        if (total > 0) builder.setProgress(total, done.coerceIn(0, total), false)
        else builder.setProgress(0, 0, true)
        return builder.build()
    }

    fun updateNotification(title: String, detail: String, done: Int, total: Int) {
        if (instance !== this || !ready()) return
        android.util.Log.d("SylphyLifecycle", "sync_progress done=$done total=$total")
        notifications.notify(ID, buildNotification(title, detail, done, total))
    }

}
