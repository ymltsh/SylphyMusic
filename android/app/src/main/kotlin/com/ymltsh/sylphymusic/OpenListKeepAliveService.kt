package com.ymltsh.sylphymusic

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/** Explicit user opt-in. Android still reserves the right to terminate us. */
class OpenListKeepAliveService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onCreate() {
        super.onCreate()
        OpenListHost.bind(applicationContext)
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel("sylphy_openlist_lite",
                "OpenList 本地服务", NotificationManager.IMPORTANCE_LOW))
        }
        val launch = PendingIntent.getActivity(this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 1,
            Intent(this, OpenListKeepAliveService::class.java).setAction("switch_to_smart"),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, "sylphy_openlist_lite")
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(android.R.drawable.stat_sys_upload_done)
            .setContentTitle("SylphyMusic · OpenList 正在运行")
            .setContentText("持续运行模式 · 仅限本机访问")
            .setContentIntent(launch)
            .setOngoing(true)
            .addAction(Notification.Action.Builder(null, "切换智能运行", stop).build())
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(5244, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else startForeground(5244, notification)
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "switch_to_smart") {
            OpenListHost.disableContinuousFromNotification()
            return START_NOT_STICKY
        }
        if (!OpenListHost.isContinuous()) { stopSelf(); return START_NOT_STICKY }
        OpenListHost.ensureAsync()
        return START_STICKY
    }
}
