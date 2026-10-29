package com.ymltsh.sylphymusic

import android.app.Application
import android.app.NotificationManager
import android.content.Intent
import android.os.Build
import android.util.Log
import com.ryanheise.audioservice.AudioServicePlugin
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class SylphyApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        Log.i("SylphyLifecycle", "application_created pid=${android.os.Process.myPid()}")
    }

    val leases by lazy { EngineLeaseManager(this) }
    private var installedEngine: FlutterEngine? = null
    private val overlay by lazy { DesktopLyricsOverlay(this) }
    private val channels = mutableMapOf<String, MethodChannel>()
    private var dartStarts = 0

    @Synchronized
    fun engine(): FlutterEngine {
        val engine = AudioServicePlugin.getFlutterEngine(this)
        check(FlutterEngineCache.getInstance().get(AudioServicePlugin.getFlutterEngineId()) === engine)
        if (installedEngine === engine) return engine
        overlay.hide()
        installedEngine = engine
        dartStarts = 0
        Log.i("SylphyLifecycle", "engine_attached engine=${System.identityHashCode(engine)} pid=${android.os.Process.myPid()}")
        for (owner in listOf("sync", "cache")) {
            val name = if (owner == "sync") "sync_lifecycle" else "cache_lifecycle"
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "music.sylphy/$name")
            channels[owner] = channel
            channel.setMethodCallHandler { call, result ->
                try {
                    val service = if (owner == "sync") SyncForegroundService.instance else CacheForegroundService.instance
                    when (call.method) {
                        "start" -> {
                            val type = if (owner == "sync") SyncForegroundService::class.java else CacheForegroundService::class.java
                            val intent = Intent(this, type)
                            if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
                            result.success(null)
                        }
                        "status" -> result.success(service?.ready() == true)
                        "stop" -> { service?.stopFromDart(); result.success(null) }
                        "pause" -> { service?.requestPause(); result.success(null) }
                        "heartbeat" -> { leases.heartbeat(owner); result.success(null) }
                        "diagnostics" -> result.success(leases.snapshot(installedEngine) + notificationState(owner) + mapOf("dartStarts" to dartStarts))
                        "update" -> {
                            (service as? SyncForegroundService)?.updateNotification(
                                call.argument<String>("title") ?: "正在同步音乐库",
                                call.argument<String>("detail") ?: "读取远程索引",
                                call.argument<Int>("done") ?: 0,
                                call.argument<Int>("total") ?: 0)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) { result.error("foreground_unavailable", "无法启动或更新前台任务，请回到应用后重试", null) }
            }
        }
        val desktopChannel = MethodChannel(
            engine.dartExecutor.binaryMessenger, "music.sylphy/desktop_lyrics"
        )
        desktopChannel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "permission" -> result.success(overlay.hasPermission())
                    "requestPermission" -> {
                        overlay.requestPermission()
                        result.success(null)
                    }
                    "show" -> {
                        overlay.show(
                            call.argument<String>("text") ?: "",
                            call.argument<Int>("color") ?: android.graphics.Color.WHITE,
                            call.argument<Number>("fontSize")?.toFloat() ?: 20f,
                            onClose = { desktopChannel.invokeMethod("dismissed", null) }
                        )
                        result.success(null)
                    }
                    "hide" -> { overlay.hide(); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("desktop_lyrics_error", e.message, null)
            }
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, "music.sylphy/engine_lifecycle").setMethodCallHandler { call, result ->
            if (call.method == "dart_started") {
                dartStarts++
                Log.i("SylphyLifecycle", "dart_started engine=${System.identityHashCode(engine)} count=$dartStarts")
                result.success(null)
            } else result.notImplemented()
        }
        return engine
    }
    private fun notificationState(owner: String): Map<String, Any> {
        val manager = getSystemService(NotificationManager::class.java)
        val id = if (owner == "sync") 43 else 42
        val channel = if (owner == "sync") "sylphy_library_sync" else "sylphy_cache"
        val note = manager.activeNotifications.firstOrNull { it.id == id }?.notification
        return mapOf(
            "notificationsEnabled" to manager.areNotificationsEnabled(),
            "notificationChannelEnabled" to (Build.VERSION.SDK_INT < 26 ||
                (manager.getNotificationChannel(channel)?.importance ?: NotificationManager.IMPORTANCE_NONE) != NotificationManager.IMPORTANCE_NONE),
            "notificationPosted" to (note != null)
        )
    }
    fun event(owner: String, event: String, acknowledged: () -> Unit) {
        val channel = channels[owner]
        if (channel == null) { acknowledged(); return }
        channel.invokeMethod(event, null, object : MethodChannel.Result {
            override fun success(result: Any?) { acknowledged() }
            override fun error(code: String, message: String?, details: Any?) { acknowledged() }
            override fun notImplemented() { acknowledged() }
        })
    }
}
