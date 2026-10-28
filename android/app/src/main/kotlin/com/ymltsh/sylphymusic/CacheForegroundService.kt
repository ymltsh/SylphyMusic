package com.ymltsh.sylphymusic

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.os.Build

/** User-started, bounded dataSync service. It never impersonates audio playback. */
class CacheForegroundService : LeasedDataSyncService() {
    companion object { var instance: CacheForegroundService? = null }
    override val owner = "cache"
    override val notificationId = 42
    override fun registerInstance() { instance = this }
    override fun clearInstance() { if (instance === this) instance = null }
    override fun notification(): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel("sylphy_cache", "歌单缓存任务", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val pause = PendingIntent.getService(this, 1, Intent(this, CacheForegroundService::class.java).setAction("pause"), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "sylphy_cache") else Notification.Builder(this)
        return builder.setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("风灵音乐 · 正在缓存歌单")
            .setContentText("完整歌曲保存在应用缓存中；可随时暂停")
            .setContentIntent(open).setOngoing(true)
            .addAction(Notification.Action.Builder(null, "暂停", pause).build()).build()
    }
}
