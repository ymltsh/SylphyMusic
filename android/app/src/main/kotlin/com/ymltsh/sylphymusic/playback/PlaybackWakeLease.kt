package com.ymltsh.sylphymusic.playback

import android.content.Context
import android.os.PowerManager
import android.os.SystemClock
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Playback CPU lease: renewal must not depend on the same executor that polls JNI.
 * Timeout bounds a hung service; temporary focus loss is held for at most 30s.
 * The callback is invoked on the lease thread. Its caller must marshal to main.
 */
internal class PlaybackWakeLease(
    context: Context,
    private val onEvent: (String) -> Unit,
) {
    enum class Mode { OFF, STARTING, PLAYING, TRANSIENT }
    private val lock = context.getSystemService(PowerManager::class.java)
        .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Sylphy:NativePlayback")
        .apply { setReferenceCounted(false) }
    private val worker = Executors.newSingleThreadScheduledExecutor { job ->
        Thread(job, "sylphy-wake-lease").apply { isDaemon = true }
    }
    private var mode = Mode.OFF
    private var enteredAt = SystemClock.elapsedRealtime()
    private var lastPoll = enteredAt
    private var warnedPollGap = false
    private var closed = false

    init { worker.scheduleAtFixedRate({ renew() }, 10, 10, TimeUnit.SECONDS) }

    @Synchronized fun polled() { lastPoll = SystemClock.elapsedRealtime(); warnedPollGap = false }
    @Synchronized fun isHeld(): Boolean = lock.isHeld

    @Synchronized fun update(next: Mode) {
        if (closed || next == mode) return
        val previous = mode
        mode = next
        enteredAt = SystemClock.elapsedRealtime()
        if (previous == Mode.OFF && next != Mode.OFF) {
            lastPoll = enteredAt
            warnedPollGap = false
        }
        if (next == Mode.OFF) {
            if (lock.isHeld) lock.release()
        } else {
            // acquire(timeout) resets the previous timeout for a non-refcounted lock.
            lock.acquire(35_000L)
        }
    }

    private fun renew() {
        val report = mutableListOf<String>()
        synchronized(this) {
            if (closed || mode == Mode.OFF) return
            val now = SystemClock.elapsedRealtime()
            when {
                mode == Mode.TRANSIENT && now - enteredAt >= 30_000 -> {
                    mode = Mode.OFF
                    if (lock.isHeld) lock.release()
                    report.add("wake_transient_expired")
                }
                mode == Mode.STARTING && now - enteredAt >= 60_000 -> {
                    mode = Mode.OFF
                    if (lock.isHeld) lock.release()
                    report.add("wake_start_timeout")
                }
                mode == Mode.PLAYING && now - lastPoll >= 90_000 -> {
                    mode = Mode.OFF
                    if (lock.isHeld) lock.release()
                    report.add("native_poll_timeout")
                }
                else -> {
                    if (mode == Mode.PLAYING && now - lastPoll >= 15_000 && !warnedPollGap) {
                        warnedPollGap = true
                        report.add("native_poll_gap")
                    }
                    if (!lock.isHeld) report.add("wake_lease_reacquired")
                    lock.acquire(35_000L)
                }
            }
        }
        // Never cross into Media3 or the Flutter engine while holding the lease mutex.
        report.forEach(onEvent)
    }

    @Synchronized fun close() {
        if (closed) return
        closed = true
        mode = Mode.OFF
        worker.shutdownNow()
        if (lock.isHeld) lock.release()
    }
}
