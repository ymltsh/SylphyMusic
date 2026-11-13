package com.ymltsh.sylphymusic

import android.app.Application
import android.app.NotificationManager
import android.content.Intent
import android.os.Build
import android.util.Log
import io.flutter.embedding.engine.dart.DartExecutor
import com.ymltsh.sylphymusic.playback.FlutterMediaControllerBridge
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class SylphyApplication : Application() {
    companion object { const val ENGINE_ID = "sylphy_business_engine" }
    private val checkpointWriter = Executors.newSingleThreadExecutor()
    private var playbackResolver: MethodChannel? = null
    private var playbackBridge: FlutterMediaControllerBridge? = null
    private var sourceReady = false
    private val waitingResolvers = mutableListOf<Runnable>()
    fun playbackUiVisible(visible: Boolean) { playbackBridge?.setUiVisible(visible) }
    fun playbackStateChanged(playWhenReady: Boolean) { if (playWhenReady) playbackBridge?.observePlayback() }
    fun playbackDiagnostics(records: String) { if (sourceReady) playbackResolver?.invokeMethod("diagnostics",records) }
    fun playbackLeaseReleased(key: String) { playbackResolver?.invokeMethod("released", key) }
    fun savePlaybackCheckpoint(file: File, value: String) {
        checkpointWriter.execute {
            try {
                val temporary = File(file.parentFile, "${file.name}.tmp")
                temporary.writeText(value)
                if (!temporary.renameTo(file)) temporary.delete()
            } catch (_: Exception) {}
        }
    }
    fun resolvePlaybackSource(key: String, completed: (JSONObject?) -> Unit) {
        engine()
        val handler = android.os.Handler(mainLooper)
        var finished = false
        var invoke: Runnable? = null
        val timeout = Runnable {
            if (!finished) { finished = true; waitingResolvers.remove(invoke); completed(null) }
        }
        handler.postDelayed(timeout, 20000)
        invoke = Runnable { if (!finished) playbackResolver!!.invokeMethod("resolve", key, object : MethodChannel.Result {
            override fun success(result: Any?) {
                val value = (result as? Map<*, *>)?.let(::JSONObject)
                if (finished) {
                    value?.optString("lease")?.takeIf { it.isNotEmpty() }?.let { File(it).delete() }
                    return
                }
                finished = true; handler.removeCallbacks(timeout); completed(value)
            }
            override fun error(code: String, message: String?, details: Any?) { success(null) }
            override fun notImplemented() { success(null) }
        }) }
        if (sourceReady) invoke.run() else waitingResolvers.add(invoke)
    }
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
        val engine = installedEngine ?: FlutterEngine(this).also {
            FlutterEngineCache.getInstance().put(ENGINE_ID, it)
        }
        if (installedEngine === engine) return engine
        overlay.hide()
        SystemNotifications.register(this, engine)
        playbackResolver = MethodChannel(engine.dartExecutor.binaryMessenger, "music.sylphy/media3_sources")
        sourceReady = false
        playbackResolver!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "ready" -> {
                    sourceReady = true
                    val waiting = waitingResolvers.toList(); waitingResolvers.clear()
                    waiting.forEach { it.run() }
                    result.success(null)
                }
                "detach" -> { sourceReady = false; result.success(null) }
                else -> result.notImplemented()
            }
        }
        playbackBridge = FlutterMediaControllerBridge(this, engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "music.sylphy/playback_diagnostics")
            .setMethodCallHandler { call, result ->
                if (call.method != "snapshot") {
                    result.notImplemented()
                } else {
                    try {
                        result.success(mapOf("backend" to "native_mpv_media3", "engineRunning" to engine.dartExecutor.isExecutingDart))
                    } catch (error: Exception) {
                        Log.w("SylphyDiagnostics", "native_snapshot_failed type=${error.javaClass.simpleName}")
                        result.error("snapshot_unavailable", "Native status unavailable", null)
                    }
                }
            }
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
        if (!engine.dartExecutor.isExecutingDart) engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
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
