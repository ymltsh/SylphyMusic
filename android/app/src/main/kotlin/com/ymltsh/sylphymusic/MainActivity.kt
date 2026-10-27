package com.ymltsh.sylphymusic

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.os.Build

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "music.sylphy/cache_lifecycle")
        CacheForegroundService.onPause = { channel.invokeMethod("pause", null) }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(CacheForegroundService.running)
                "start" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 42)
                        }
                        val intent = Intent(this, CacheForegroundService::class.java)
                        if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
                        result.success(null)
                    } catch (error: Exception) { result.error("background_restricted", "系统暂不允许启动后台缓存，请回到应用后重试", null) }
                }
                "stop" -> { stopService(Intent(this, CacheForegroundService::class.java)); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }
}
