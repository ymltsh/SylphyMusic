package com.ymltsh.sylphymusic

import android.app.Notification
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log

/** Ordinary pause keeps its lease until Dart acknowledges full cleanup. */
abstract class LeasedDataSyncService : Service() {
    protected abstract val owner: String
    protected abstract val notificationId: Int
    protected abstract fun notification(): Notification
    protected abstract fun registerInstance()
    protected abstract fun clearInstance()
    private val token = Any()
    private val handler = Handler(Looper.getMainLooper())
    private var started = false
    private var stopping = false
    private var finishing = false
    private val app get() = application as SylphyApplication
    private val fallback = Runnable { finishStop() }
    private val heartbeat = object : Runnable {
        override fun run() {
            if (!started || finishing) return
            app.leases.logHeartbeat(owner)
            handler.postDelayed(this, 3000)
        }
    }
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "pause") { requestPause(); return START_NOT_STICKY }
        if (started) return START_NOT_STICKY
        registerInstance()
        try {
            val note = notification()
            if (Build.VERSION.SDK_INT >= 29) startForeground(notificationId, note, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            else startForeground(notificationId, note)
            started = true
            app.leases.acquire(token, owner, {
                Log.i("SylphyLifecycle", "task_ready owner=$owner")
            }, {
                app.event(owner, "unavailable") { finishStop() }
                handler.postDelayed(fallback, 3000)
            })
            handler.post(heartbeat)
        } catch (_: RuntimeException) {
            app.event(owner, "unavailable") { }
            finishStop()
        }
        return START_NOT_STICKY
    }
    fun ready() = started && !stopping && !finishing && app.leases.ready(token)
    fun requestPause() {
        if (!started || stopping || finishing) return
        stopping = true
        Log.i("SylphyLifecycle", "task_pause owner=$owner")
        handler.postDelayed(fallback, 60000)
        app.event(owner, "pause") { finishStop() }
    }
    fun stopFromDart() {
        // The pause callback may itself await Dart stop(). Do not block it, and
        // do not release the binding until that callback acknowledges cleanup.
        if (!stopping) finishStop()
    }
    private fun finishStop() {
        if (finishing) return
        finishing = true
        handler.removeCallbacksAndMessages(null)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }
    override fun onTimeout(startId: Int, fgsType: Int) {
        Log.i("SylphyLifecycle", "task_timeout owner=$owner")
        app.event(owner, "timeout") { }
        finishStop() // OS deadline: never wait for Dart acknowledgement here.
    }
    override fun onDestroy() {
        finishing = true
        handler.removeCallbacksAndMessages(null)
        clearInstance()
        app.leases.release(token)
        Log.i("SylphyLifecycle", "task_destroyed owner=$owner")
        super.onDestroy()
    }
}
