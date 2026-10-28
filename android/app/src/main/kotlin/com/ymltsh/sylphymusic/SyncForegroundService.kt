package com.ymltsh.sylphymusic

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/** Only user-initiated index/tag work may start this dataSync FGS.
 * The service protects the app-owned FlutterEngine process and renders progress;
 * network/SQLite work stays in Dart. Never auto-restart after process death.
 */
class SyncForegroundService : Service() {
    companion object {
        @Volatile var instance: SyncForegroundService? = null
        var onEvent: ((String) -> Unit)? = null
        private const val CHANNEL = "sylphy_library_sync"
        private const val ID = 43
    }

    private lateinit var notifications: NotificationManager
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "pause") {
            onEvent?.invoke("pause")
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        if (instance != null) return START_NOT_STICKY
        notifications = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            notifications.createNotificationChannel(
                NotificationChannel(CHANNEL, "音乐库同步", NotificationManager.IMPORTANCE_LOW)
            )
        }
        try {
            val notification = buildNotification("风灵音乐 · 正在同步", "正在读取音乐库", 0, 0)
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                startForeground(ID, notification)
            }
            instance = this
        } catch (_: RuntimeException) {
            onEvent?.invoke("unavailable")
            stopSelf()
        }
        return START_NOT_STICKY
    }

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
        if (instance !== this) return
        notifications.notify(ID, buildNotification(title, detail, done, total))
    }

    /** Android 15+: stop immediately or the OS throws RemoteServiceException. */
    override fun onTimeout(startId: Int, fgsType: Int) {
        onEvent?.invoke("timeout")
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }
}
