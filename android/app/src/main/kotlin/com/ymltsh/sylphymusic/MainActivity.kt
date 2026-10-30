package com.ymltsh.sylphymusic

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

class MainActivity : AudioServiceActivity() {
    private val notificationRequests = mutableListOf<MethodChannel.Result>()
    // Correlate the observed foreground recovery with the Dart watchdog gap.
    override fun onStart() {
        super.onStart()
        Log.i("SylphyLifecycle", "activity_visible pid=${android.os.Process.myPid()}")
        OpenListRuntime.bind(applicationContext)
        OpenListRuntime.onAppForeground()
    }

    override fun onStop() {
        Log.i("SylphyLifecycle", "activity_hidden pid=${android.os.Process.myPid()}")
        super.onStop()
    }

    // audio_service owns the engine; active dataSync leases keep it bound.
    override fun provideFlutterEngine(context: Context): FlutterEngine =
        (application as SylphyApplication).engine()
    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "music.sylphy/notification_permission")
            .setMethodCallHandler { call, result ->
                if (call.method != "request") {
                    result.notImplemented()
                } else {
                    if (Build.VERSION.SDK_INT >= 33 &&
                        checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
                        android.content.pm.PackageManager.PERMISSION_GRANTED) {
                        val requesting = notificationRequests.isNotEmpty()
                        notificationRequests.add(result)
                        if (!requesting) requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 42)
                    } else {
                        result.success(null)
                    }
                }
            }
        val iconManager = LauncherIconManager(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "music.sylphy/launcher_icons")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "getOptions" -> result.success(iconManager.options())
                        "setIcon" -> {
                            val iconId = call.argument<String>("id")
                            if (iconId == null) {
                                result.error("invalid_icon", "未指定图标", null)
                            } else {
                                iconManager.select(iconId)
                                result.success(null)
                            }
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("launcher_icon_error", error.message ?: "图标切换失败", null)
                }
            }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 42) completeNotificationRequests()
    }

    private fun completeNotificationRequests() {
        val pending = notificationRequests.toList()
        notificationRequests.clear()
        pending.forEach { it.success(null) }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // Activity detach must not leave Dart awaiting a permission result.
        completeNotificationRequests()
        // The engine survives this Activity; do not retain a dead Activity in
        // icon/permission channel handlers after swiping it from Recents.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "music.sylphy/launcher_icons")
            .setMethodCallHandler(null)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "music.sylphy/notification_permission")
            .setMethodCallHandler(null)
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
