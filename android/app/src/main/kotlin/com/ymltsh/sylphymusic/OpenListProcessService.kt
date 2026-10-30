package com.ymltsh.sylphymusic

import android.app.Service
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.os.Process
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/** Non-exported process boundary lets disable release all Go threads and drivers. */
class OpenListProcessService : Service() {
    private val main = Handler(Looper.getMainLooper())
    private var terminating = false
    private val inbox = Messenger(Handler(Looper.getMainLooper()) { message ->
        if (terminating) {
            reply(message, null, "OpenList 正在停止，请重试")
            return@Handler true
        }
        // Android recycles the incoming Message when this handler returns.
        val request = Message.obtain(message)
        val data = request.data
        val method = data.getString("method") ?: return@Handler true
        val args = data.keySet().filter { it != "method" }.associateWith { data.get(it) }
        OpenListHost.dispatch(method, args, object : MethodChannel.Result {
            override fun success(result: Any?) {
                val terminate = !OpenListHost.isEnabled() || method == "shutdown"
                if (terminate) terminating = true
                reply(request, result, null)
                if (terminate) {
                    stopSelf()
                    main.postDelayed({ Process.killProcess(Process.myPid()) }, 200L)
                }
            }
            override fun error(code: String, error: String?, details: Any?) {
                reply(request, null, error ?: "OpenList 操作失败")
                if (!OpenListHost.isEnabled()) {
                    terminating = true
                    stopSelf()
                    main.postDelayed({ Process.killProcess(Process.myPid()) }, 200L)
                }
            }
            override fun notImplemented() { reply(request, null, "不支持的操作") }
        })
        true
    })
    override fun onCreate() { super.onCreate(); OpenListHost.bind(applicationContext) }
    override fun onBind(intent: Intent?): IBinder = inbox.binder
    private fun reply(request: Message, result: Any?, error: String?) {
        val data = Bundle().apply { putBoolean("enabled", OpenListHost.isEnabled()) }
        if (error != null) data.putString("error", error)
        else if (result is Map<*, *>) data.putString("map", JSONObject(result).toString())
        else if (result != null) data.putString("value", result.toString())
        runCatching { request.replyTo.send(Message.obtain(null, 1).apply { arg1 = request.arg1; this.data = data }) }
    }
}
