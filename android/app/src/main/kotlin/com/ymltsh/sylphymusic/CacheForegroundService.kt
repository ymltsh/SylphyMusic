package music.sylphy.sylphy_music

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.Handler
import android.os.Looper

/** User-started, bounded dataSync service. It never impersonates audio playback. */
class CacheForegroundService : Service() {
    companion object { var onPause: (() -> Unit)? = null; var running = false }
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "pause") {
            Handler(Looper.getMainLooper()).post { onPause?.invoke() }
            stopForeground(STOP_FOREGROUND_REMOVE); stopSelf()
            return START_NOT_STICKY
        }
        val manager = getSystemService(NotificationManager::class.java)
        running = true
        manager.createNotificationChannel(NotificationChannel("sylphy_cache", "歌单缓存任务", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val pause = PendingIntent.getService(this, 1, Intent(this, CacheForegroundService::class.java).setAction("pause"), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = Notification.Builder(this, "sylphy_cache")
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("风灵音乐 · 正在缓存歌单")
            .setContentText("完整歌曲保存在应用缓存中；可随时暂停")
            .setContentIntent(open).setOngoing(true)
            .addAction(Notification.Action.Builder(null, "暂停", pause).build()).build()
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(42, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else { startForeground(42, notification) }
        return START_NOT_STICKY
    }
    override fun onTimeout(startId: Int, fgsType: Int) {
        Handler(Looper.getMainLooper()).post { onPause?.invoke() }
        stopForeground(STOP_FOREGROUND_REMOVE); stopSelf()
    }
    override fun onDestroy() { running = false; super.onDestroy() }
}
