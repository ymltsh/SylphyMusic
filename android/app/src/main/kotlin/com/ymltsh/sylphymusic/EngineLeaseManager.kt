package com.ymltsh.sylphymusic

import android.content.Context
import android.os.SystemClock
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache

/** Main-thread leases for the application-owned business engine; no playback binding. */
class EngineLeaseManager(private val context: Context) {
    private data class Lease(val owner: String, val ready: () -> Unit, val lost: () -> Unit)
    private val leases = linkedMapOf<Any, Lease>()
    private var connected = false
    private var expected: FlutterEngine? = null
    private val heartbeats = mutableMapOf<String, Long>()
    private val heartbeatCounts = mutableMapOf<String, Int>()
    private fun cached() = FlutterEngineCache.getInstance().get(SylphyApplication.ENGINE_ID)
    private fun engineId() = expected?.let { System.identityHashCode(it) } ?: 0
    private fun identityValid() = expected != null && cached() === expected && expected!!.dartExecutor.isExecutingDart
    fun acquire(token: Any, owner: String, ready: () -> Unit, lost: () -> Unit) {
        if (leases.containsKey(token)) return
        if (leases.isEmpty()) expected = cached()
        leases[token] = Lease(owner, ready, lost)
        if (!identityValid()) { fail(); return }
        connected = true
        ready()
    }
    private fun fail() {
        connected = false
        Log.e("SylphyLifecycle", "business_engine_unavailable leases=${leases.size}")
        leases.values.toList().forEach { it.lost() }
    }
    fun release(token: Any) {
        val removed = leases.remove(token) ?: return
        heartbeats.remove(removed.owner)
        Log.i("SylphyLifecycle", "lease_released owner=${removed.owner} remaining=${leases.size}")
        if (leases.isEmpty()) {
            connected = false
            expected = null
        }
    }
    fun heartbeat(owner: String) {
        heartbeats[owner] = SystemClock.elapsedRealtime()
        heartbeatCounts[owner] = (heartbeatCounts[owner] ?: 0) + 1
    }
    fun ready(token: Any) = leases.containsKey(token) && connected && identityValid()
    fun snapshot(engine: FlutterEngine?): Map<String, Any> = mapOf(
        "engineId" to (engine?.let { System.identityHashCode(it) } ?: 0),
        "engineCached" to (engine != null && cached() === engine && engine.dartExecutor.isExecutingDart),
        "businessEngineLeased" to connected,
        "leaseCount" to leases.size,
        "sync" to leases.values.any { it.owner == "sync" },
        "cache" to leases.values.any { it.owner == "cache" },
        "syncHeartbeats" to (heartbeatCounts["sync"] ?: 0),
        "cacheHeartbeats" to (heartbeatCounts["cache"] ?: 0),
        "syncDartAgeMs" to (heartbeats["sync"]?.let { SystemClock.elapsedRealtime() - it } ?: -1L),
        "cacheDartAgeMs" to (heartbeats["cache"]?.let { SystemClock.elapsedRealtime() - it } ?: -1L)
    )
    fun logHeartbeat(owner: String) {
        val last = heartbeats[owner]
        val age = if (last == null) -1 else SystemClock.elapsedRealtime() - last
        Log.d("SylphyLifecycle", "heartbeat owner=$owner engine=${engineId()} engineCached=${identityValid()} audioBound=$connected leases=${leases.size} dartAgeMs=$age")
    }
}
