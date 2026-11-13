package com.ymltsh.sylphymusic.playback

import android.content.ComponentName
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.MediaController
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionResult
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.ListenableFuture
import com.ymltsh.sylphymusic.SylphyApplication
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/** UI controls connect to the same session used by SystemUI and headsets. */
@UnstableApi
class FlutterMediaControllerBridge(private val app: SylphyApplication, engine: FlutterEngine) {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "music.sylphy/media3")
    private val main = Handler(Looper.getMainLooper())
    private val executor = java.util.concurrent.Executor { main.post(it) }
    private var future: ListenableFuture<MediaController>? = null
    private var controller: MediaController? = null
    private var observing = false
    private var revision = -1L
    private var snapshotSessionId = ""
    private var uiVisible = false
    private var lastCommandAt = android.os.SystemClock.elapsedRealtime()
    fun observePlayback() { if (observing && controller == null && future == null) connect {} }
    fun setUiVisible(visible: Boolean) {
        uiVisible = visible
        if (visible && observing) connect { value ->
            value?.let { custom(it, "wake", JSONObject(), object : MethodChannel.Result {
                override fun success(result: Any?) { channel.invokeMethod("snapshot", result) }
                override fun error(code: String, message: String?, details: Any?) {}
                override fun notImplemented() {}
            }) }
        }
    }
    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "ackSnapshot") {
                val args = call.arguments as? Map<*, *>
                if (args?.get("sessionId") == snapshotSessionId) {
                    revision = maxOf(revision, (args["revision"] as? Number)?.toLong() ?: -1)
                }
                result.success(null); return@setMethodCallHandler
            }
            lastCommandAt = android.os.SystemClock.elapsedRealtime()
            if (call.method == "detach") {
                observing = false; controller?.release(); controller = null; future = null
                result.success(null); return@setMethodCallHandler
            }
            if (call.method == "connect") observing = true
            connect { value ->
                if (value == null) { result.error("media3_unavailable", "媒体服务不可用", null); return@connect }
                try {
                    val args = JSONObject(call.arguments as? Map<*, *> ?: emptyMap<String, Any>())
                    when (call.method) {
                        "connect" -> if (uiVisible) custom(value, "wake", JSONObject(), result) else snapshot(value, result)
                        "snapshot" -> snapshot(value, result)
                        "play" -> perform(value, result, Player.COMMAND_PLAY_PAUSE) { value.play() }
                        "pause" -> perform(value, result, Player.COMMAND_PLAY_PAUSE) { value.pause() }
                        "seek" -> {
                            if (!value.isCommandAvailable(Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM))
                                result.error("media3_command_unavailable", "媒体控制尚未就绪，请稍后重试", null)
                            else custom(value, "seek", args, result)
                        }
                        "jump" -> perform(value, result, Player.COMMAND_SEEK_TO_MEDIA_ITEM, Player.COMMAND_PLAY_PAUSE) { value.seekTo(args.getInt("index"), 0); value.play() }
                        "next" -> perform(value, result, Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM) { value.seekToNextMediaItem() }
                        "previous" -> perform(value, result, Player.COMMAND_SEEK_TO_PREVIOUS) { value.seekToPrevious() }
                        "stop" -> perform(value, result, Player.COMMAND_STOP) { value.stop() }
                        "rate" -> perform(value, result, Player.COMMAND_SET_SPEED_AND_PITCH) { value.playbackParameters = PlaybackParameters(args.getDouble("value").toFloat()) }
                        "volume" -> perform(value, result, Player.COMMAND_SET_VOLUME) { value.volume = args.getDouble("value").toFloat() / 100 }
                        "mode" -> perform(value, result, Player.COMMAND_SET_REPEAT_MODE, Player.COMMAND_SET_SHUFFLE_MODE) { value.repeatMode = args.getInt("repeat"); value.shuffleModeEnabled = args.getBoolean("shuffle") }
                        "shutdown" -> {
                            observing = false
                            custom(value, "shutdown", JSONObject(), object : MethodChannel.Result {
                                override fun success(response: Any?) {
                                    result.success(response); value.release(); controller = null; future = null
                                }
                                override fun error(code: String, message: String?, details: Any?) { result.error(code, message, details) }
                                override fun notImplemented() { result.notImplemented() }
                            })
                        }
                        "queue", "gain", "art", "invalidate", "retry", "declick", "audioDiagnostics" -> custom(value, call.method, args, result)
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) { result.error("media3_command", "媒体操作失败", null) }
            }
        }
        main.post(object : Runnable {
            override fun run() {
                // Only the Flutter view is sampled. Media3 owns notification scheduling.
                if (observing) controller?.let { value ->
                    custom(value, "snapshot", JSONObject().put("revision", revision), object : MethodChannel.Result {
                        override fun success(result: Any?) {
                            if (observing) channel.invokeMethod("snapshot", result)
                            if (!uiVisible && !value.playWhenReady && android.os.SystemClock.elapsedRealtime() - lastCommandAt > 5000) {
                                value.release(); controller = null; future = null
                            }
                        }
                        override fun error(code: String, message: String?, details: Any?) {}
                        override fun notImplemented() {}
                    })
                }
                main.postDelayed(this, 500)
            }
        })
    }
    private fun connect(done: (MediaController?) -> Unit) {
        controller?.let { if (it.isConnected) { done(it); return }; controller = null; future = null }
        val pending = future ?: MediaController.Builder(app, SessionToken(app, ComponentName(app, SylphyMediaLibraryService::class.java)))
            .setListener(object : MediaController.Listener {
                override fun onDisconnected(controller: MediaController) {
                    if (this@FlutterMediaControllerBridge.controller === controller) {
                        this@FlutterMediaControllerBridge.controller = null; future = null
                    }
                }
            }).buildAsync().also { future = it; revision = -1; snapshotSessionId = "" }
        pending.addListener({
            if (future !== pending) { done(null); return@addListener }
            try { controller = pending.get(); done(controller) } catch (_: Exception) { future = null; done(null) }
        }, executor)
    }
    private fun snapshot(controller: MediaController, result: MethodChannel.Result) = custom(controller, "snapshot", JSONObject(), result)
    private fun perform(controller: MediaController, result: MethodChannel.Result, vararg commands: Int, operation: () -> Unit) {
        if (commands.any { !controller.isCommandAvailable(it) }) {
            result.error("media3_command_unavailable", "媒体控制尚未就绪，请稍后重试", null)
            return
        }
        operation(); snapshot(controller, result)
    }
    private fun custom(controller: MediaController, action: String, data: JSONObject, result: MethodChannel.Result) {
        val pending = controller.sendCustomCommand(SessionCommand("sylphy.control", Bundle.EMPTY), Bundle().apply {
            putString("action", action); putString("data", data.toString())
        })
        pending.addListener({
            try {
                val response = pending.get()
                if (this.controller !== controller || !controller.isConnected) {
                    result.error("media3_disconnected", "媒体服务连接已断开", null)
                    return@addListener
                }
                if (response.resultCode == SessionResult.RESULT_SUCCESS) {
                    val json = response.extras.getString("snapshot")
                    // A response is not an acknowledgment from Flutter. It may
                    // be overtaken by a newer sample before Dart accepts it.
                    if (json != null) snapshotSessionId = JSONObject(json).optString("sessionId")
                    result.success(json)
                }
                else result.error("media3_rejected", "媒体操作未完成", null)
            } catch (_: Exception) { result.error("media3_disconnected", "媒体服务连接已断开", null) }
        }, executor)
    }
}
