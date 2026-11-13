package com.ymltsh.sylphymusic

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

class MainActivity : FlutterActivity() {
    private var letterImages: LetterImageStore? = null
    private val notificationRequests = mutableListOf<MethodChannel.Result>()
    private val lanRequests = mutableListOf<MethodChannel.Result>()
    private val lanPermission = "android.permission.ACCESS_LOCAL_NETWORK"
    // Correlate the observed foreground recovery with the Dart watchdog gap.
    override fun onStart() {
        super.onStart()
        (application as SylphyApplication).playbackUiVisible(true)
        Log.i("SylphyLifecycle", "activity_visible pid=${android.os.Process.myPid()}")
    }

    override fun onStop() {
        (application as SylphyApplication).playbackUiVisible(false)
        Log.i("SylphyLifecycle", "activity_hidden pid=${android.os.Process.myPid()}")
        super.onStop()
    }

    // The application owns the shared source/catalog and dataSync engine.
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "music.sylphy/local_network")
            .setMethodCallHandler { call, result ->
                if (call.method != "request") {
                    result.notImplemented()
                } else if (Build.VERSION.SDK_INT < 37 ||
                    checkSelfPermission(lanPermission) ==
                    android.content.pm.PackageManager.PERMISSION_GRANTED) {
                    result.success(true)
                } else {
                    val requesting = lanRequests.isNotEmpty()
                    lanRequests.add(result)
                    if (!requesting) requestPermissions(arrayOf(lanPermission), 44)
                }
            }
        letterImages = LetterImageStore(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "music.sylphy/letter_images")
            .setMethodCallHandler { call, result -> letterImages?.handle(call, result) ?: result.error("unavailable", "图片服务不可用", null) }
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
        if (requestCode == 43) letterImages?.permissionResult()
        if (requestCode == 44) completeLanRequests(
            grantResults.isNotEmpty() &&
            grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED)
    }

    private fun completeLanRequests(granted: Boolean) {
        val pending = lanRequests.toList()
        lanRequests.clear()
        pending.forEach { it.success(granted) }
    }

    private fun completeNotificationRequests() {
        val pending = notificationRequests.toList()
        notificationRequests.clear()
        pending.forEach { it.success(null) }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        letterImages?.detach()
        letterImages = null
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "music.sylphy/letter_images").setMethodCallHandler(null)
        // Activity detach must not leave Dart awaiting a permission result.
        completeNotificationRequests()
        completeLanRequests(false)
        // The engine survives this Activity; do not retain a dead Activity in
        // icon/permission channel handlers after swiping it from Recents.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "music.sylphy/launcher_icons")
            .setMethodCallHandler(null)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "music.sylphy/notification_permission")
            .setMethodCallHandler(null)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "music.sylphy/local_network")
            .setMethodCallHandler(null)
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
