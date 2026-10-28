package com.ymltsh.sylphymusic

import android.app.Application
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import com.ryanheise.audioservice.AudioServicePlugin
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/** Owns the one UI + sync FlutterEngine independently of the Activity lifecycle.
 * A foreground Service can then keep the Dart HTTP/SQLite work alive when the
 * user leaves Recents. It does not survive a process kill / force-stop.
 */
class SylphyApplication : Application() {
    private var storedEngine: FlutterEngine? = null

    @Synchronized
    fun engine(): FlutterEngine {
        storedEngine?.let {
            FlutterEngineCache.getInstance().put(AudioServicePlugin.getFlutterEngineId(), it)
            return it
        }
        // audio_service normally destroys its cached engine when playback's
        // Service stops without an Activity. Sync/cache still need this engine.
        val engine = object : FlutterEngine(this) {
            override fun destroy() {
                // audio_service removes the cache entry after this callback.
                // Restore it on the next main-loop turn; keep sync/cache alive.
                val retained = this
                Handler(Looper.getMainLooper()).post {
                    FlutterEngineCache.getInstance().put(AudioServicePlugin.getFlutterEngineId(), retained)
                }
            }
        }
        FlutterEngineCache.getInstance().put(AudioServicePlugin.getFlutterEngineId(), engine)
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "music.sylphy/sync_lifecycle")
        SyncForegroundService.onEvent = { event ->
            Handler(Looper.getMainLooper()).post { channel.invokeMethod(event, null) }
        }
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "start" -> {
                        val intent = Intent(this, SyncForegroundService::class.java)
                        if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent)
                        else startService(intent)
                        result.success(null)
                    }
                    "update" -> {
                        SyncForegroundService.instance?.updateNotification(
                            call.argument<String>("title") ?: "正在同步音乐库",
                            call.argument<String>("detail") ?: "读取远程索引",
                            call.argument<Int>("done") ?: 0,
                            call.argument<Int>("total") ?: 0
                        )
                        result.success(null)
                    }
                    "stop" -> {
                        stopService(Intent(this, SyncForegroundService::class.java))
                        result.success(null)
                    }
                    "status" -> result.success(SyncForegroundService.instance != null)
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("sync_foreground_unavailable", error.message ?: "无法启动前台同步服务", null)
            }
        }
        // The cache worker also needs an Activity-independent channel: its
        // notification pause button must keep working after Recents dismissal.
        val cacheChannel = MethodChannel(engine.dartExecutor.binaryMessenger, "music.sylphy/cache_lifecycle")
        CacheForegroundService.onPause = {
            Handler(Looper.getMainLooper()).post { cacheChannel.invokeMethod("pause", null) }
        }
        cacheChannel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "status" -> result.success(CacheForegroundService.running)
                    "start" -> {
                        val intent = Intent(this, CacheForegroundService::class.java)
                        if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent)
                        else startService(intent)
                        result.success(null)
                    }
                    "stop" -> {
                        stopService(Intent(this, CacheForegroundService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("background_restricted", error.message ?: "无法启动后台缓存", null)
            }
        }
        storedEngine = engine
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        return engine
    }
}
