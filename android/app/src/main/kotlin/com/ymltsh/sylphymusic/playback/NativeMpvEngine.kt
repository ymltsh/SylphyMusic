package com.ymltsh.sylphymusic.playback

import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** All JNI access, including destruction, is serialized off the session Looper. */
@androidx.annotation.Keep
class NativeMpvEngine(private val observed: (Long, DoubleArray) -> Unit,
                      private val failed: (Long) -> Unit,
                      private val diagnostic: (String) -> Unit) {
    companion object {
        init { System.loadLibrary("sylphy_mpv") }
        // A recreated service cannot create its context before the old one's
        // queued terminate/destroy has completed.
        private val worker = Executors.newSingleThreadScheduledExecutor()
    }
    private val main = Handler(Looper.getMainLooper())
    private var handle = 0L
    private var epoch = 0L
    @Volatile private var closed = false
    @Volatile private var pauseRequested = true
    fun setPauseIntent(paused: Boolean) { pauseRequested = paused }
    private val polling: java.util.concurrent.ScheduledFuture<*>
    init {
        worker.execute {
            try { handle = create() } catch (_: Throwable) { main.post { failed(epoch) } }
        }
        polling = worker.scheduleWithFixedDelay({
            if (handle != 0L) {
                val generation = epoch
                try {
                    val value = sample(handle)
                    val records = diagnostics(handle)
                    if (records != "[]") main.post { if (!closed) diagnostic(records) }
                    main.post { if (!closed) observed(generation, value) }
                } catch (_: Exception) { main.post { if (!closed) failed(generation) } }
            }
        }, 0, 200, TimeUnit.MILLISECONDS)
    }
    fun execute(generation: Long, block: NativeMpvEngine.() -> Unit) {
        if (closed) return
        worker.execute {
            epoch = generation
            if (handle == 0L) { main.post { if (!closed) failed(generation) }; return@execute }
            try { block() } catch (_: Exception) { main.post { if (!closed) failed(generation) } }
        }
    }
    fun property(name: String, value: String) = set(handle, name, value)
    fun command(vararg args: String) = command(handle, arrayOf(*args))
    fun stopAndDrain() = stop(handle)
    fun close(done: () -> Unit) {
        closed = true
        polling.cancel(false)
        worker.execute {
            if (handle != 0L) { destroy(handle); handle = 0L }
            main.post(done)
        }
    }
    private external fun create(): Long
    private external fun set(handle: Long, name: String, value: String)
    private external fun command(handle: Long, args: Array<String>)
    private external fun sample(handle: Long): DoubleArray
    private external fun stop(handle: Long)
    private external fun diagnostics(handle: Long): String
    private external fun destroy(handle: Long)
}
