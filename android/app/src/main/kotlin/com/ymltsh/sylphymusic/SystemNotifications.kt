package com.ymltsh.sylphymusic

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

object SystemNotifications {
    fun register(context: Context, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "music.sylphy/system_notifications")
            .setMethodCallHandler { call, result ->
                if (call.method != "syncCompleted") {
                    result.notImplemented()
                } else {
                    try {
                        val manager = context.getSystemService(NotificationManager::class.java)
                        if (Build.VERSION.SDK_INT >= 26) {
                            manager.createNotificationChannel(NotificationChannel(
                                "sylphy_sync_results", "同步结果", NotificationManager.IMPORTANCE_DEFAULT))
                        }
                        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
                            ?: Intent(context, MainActivity::class.java)
                        val open = PendingIntent.getActivity(context, 44, launch,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                        @Suppress("DEPRECATION")
                        val builder = if (Build.VERSION.SDK_INT >= 26) {
                            Notification.Builder(context, "sylphy_sync_results")
                        } else Notification.Builder(context)
                        manager.notify(44, builder
                            .setSmallIcon(android.R.drawable.stat_sys_download_done)
                            .setContentTitle("风灵音乐 · 同步结果")
                            .setContentText(call.argument<String>("message") ?: "自动同步完成")
                            .setContentIntent(open)
                            .setAutoCancel(true)
                            .build())
                        result.success(null)
                    } catch (_: Exception) {
                        result.error("notification_unavailable", "系统通知不可用", null)
                    }
                }
            }
    }
}
