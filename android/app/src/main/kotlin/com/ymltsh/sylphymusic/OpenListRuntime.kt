package com.ymltsh.sylphymusic

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/** IPC client only: Go is loaded exclusively in the :openlist service process. */
internal object OpenListRuntime {
    const val BASE = "http://127.0.0.1:10486"
    const val CHANNEL = "music.sylphy/openlist_lite"
    private val main = Handler(Looper.getMainLooper())
    private var app: Context? = null
    private var remote: Messenger? = null
    private var bound = false
    private var nextId = 0
    private var disabled = false
    private var lastMode = "smart"
    private var restartAfter = 0L
    private data class Request(val method: String, val args: Map<String, Any?>, val callback: MethodChannel.Result)
    private val pending = mutableMapOf<Int, Request>()
    private val outgoing = mutableListOf<Int>()
    private val replies = Messenger(Handler(Looper.getMainLooper()) { message ->
        val request = pending.remove(message.arg1) ?: return@Handler true
        val data = message.data
        if (data.containsKey("enabled")) disabled = !data.getBoolean("enabled")
        val error = data.getString("error")
        if (error != null) {
            if (disabled) {
                restartAfter = android.os.SystemClock.uptimeMillis() + 300L
                fail("OpenList 服务已停止")
            }
            request.callback.error("openlist_error", error, null)
        } else {
            val result: Any? = if (data.containsKey("map")) {
                val json = JSONObject(data.getString("map")!!)
                json.keys().asSequence().associateWith { json.get(it) }
            } else data.getString("value")
            if (result is Map<*, *>) {
                if (result.containsKey("enabled")) disabled = result["enabled"] == false
                if (result["mode"] is String) lastMode = result["mode"] as String
            }
            if (request.method == "mode") lastMode = request.args["value"] as String
            if (request.method == "enabled") disabled = request.args["value"] == false
            if (request.method == "openUi") {
                app!!.startActivity(Intent(app, OpenListWebActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
            if (disabled || request.method == "shutdown") {
                restartAfter = android.os.SystemClock.uptimeMillis() + 300L
                fail("OpenList 服务已停止")
            }
            request.callback.success(result)
        }
        true
    })
    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, binder: IBinder) {
            remote = Messenger(binder)
            val ids = outgoing.toList()
            outgoing.clear()
            ids.forEach { send(it) }
        }
        override fun onServiceDisconnected(name: ComponentName) { fail("OpenList 服务已停止") }
        override fun onBindingDied(name: ComponentName) { fail("OpenList 服务进程已退出") }
        override fun onNullBinding(name: ComponentName) { fail("无法连接 OpenList 服务") }
    }
    fun bind(context: Context) { app = context.applicationContext }
    private fun disconnect() {
        remote = null
        if (bound) {
            bound = false
            runCatching { app!!.unbindService(connection) }
        }
    }
    private fun fail(message: String) {
        disconnect()
        val callbacks = pending.values.toList()
        pending.clear()
        outgoing.clear()
        callbacks.forEach { it.callback.error("openlist_error", message, null) }
    }
    private fun send(id: Int) {
        val request = pending[id] ?: return
        try {
            val data = Bundle().apply {
                putString("method", if (request.method == "openUi") "ensure" else request.method)
                request.args.forEach { (key, value) ->
                    when (value) {
                        is String -> putString(key, value)
                        is Boolean -> putBoolean(key, value)
                    }
                }
            }
            remote!!.send(Message.obtain(null, 1).apply { arg1 = id; this.data = data; replyTo = replies })
        } catch (_: Exception) { fail("无法连接 OpenList 服务，请重试") }
    }
    fun dispatch(method: String, args: Map<String, Any?>, callback: MethodChannel.Result) {
        main.post {
            if (disabled && method == "status") {
                callback.success(mapOf("enabled" to false, "running" to false, "mode" to lastMode, "url" to BASE, "leaseCount" to 0))
                return@post
            }
            val delay = restartAfter - android.os.SystemClock.uptimeMillis()
            if (remote == null && delay > 0 && method != "release") {
                main.postDelayed({ dispatch(method, args, callback) }, delay)
                return@post
            }
            if (disabled && method in setOf("ensure", "acquire", "openUi", "mode")) {
                callback.error("openlist_error", "OpenList 已关闭，请在网盘设置中启用", null)
                return@post
            }
            if (remote == null && method == "release") {
                callback.success(null)
                return@post
            }
            val id = ++nextId
            pending[id] = Request(method, args, callback)
            main.postDelayed({
                if (pending.remove(id) != null) {
                    outgoing.remove(id)
                    callback.error("openlist_error", "OpenList 请求超时，请重试", null)
                    if (pending.isEmpty()) disconnect()
                }
            }, 60_000L)
            if (remote != null) send(id) else {
                outgoing.add(id)
                if (!bound) {
                    bound = true
                    try {
                        check(app!!.bindService(Intent(app, OpenListProcessService::class.java), connection, Context.BIND_AUTO_CREATE))
                    } catch (_: Exception) { fail("无法启动 OpenList 服务") }
                }
            }
        }
    }
    private val ignored = object : MethodChannel.Result {
        override fun success(result: Any?) {}
        override fun error(code: String, message: String?, details: Any?) {}
        override fun notImplemented() {}
    }
    fun onAppForeground() { if (!disabled) dispatch("restore", emptyMap(), ignored) }
    fun retainUi() { dispatch("acquire", mapOf("key" to "webui"), ignored) }
    fun releaseUi() { dispatch("release", mapOf("key" to "webui"), ignored) }
}
