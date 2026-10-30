package com.ymltsh.sylphymusic

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.URL
import java.security.KeyStore
import java.security.SecureRandom
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import openlistlib.Openlistlib

/** Single process owner. All calls into Go are serialized on one worker. */
internal object OpenListRuntime {
    const val PORT = 5244
    const val BASE = "http://127.0.0.1:5244"
    const val CHANNEL = "music.sylphy/openlist_lite"
    private const val IDLE_MS = 180_000L
    private val worker = Executors.newSingleThreadExecutor { r ->
        Thread(r, "openlist-lite").apply { isDaemon = true }
    }
    private val main = Handler(Looper.getMainLooper())
    private val leases = mutableSetOf<String>()
    private var generation = 0L
    private var initialized = false
    private var started = false
    private var app: Context? = null

    fun bind(application: Context) { app = application.applicationContext }
    private fun context(): Context = checkNotNull(app) { "OpenList not bound" }
    private fun preferences() = context().getSharedPreferences("openlist_lite", Context.MODE_PRIVATE)
    private fun mode(): String = preferences().getString("mode", "smart") ?: "smart"

    private fun password(): String {
        val prefs = preferences()
        val alias = "sylphy-openlist-admin"
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (!ks.containsAlias(alias)) {
            val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            generator.init(KeyGenParameterSpec.Builder(alias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true).build())
            generator.generateKey()
        }
        val key = ks.getKey(alias, null) as SecretKey
        val cipherText = prefs.getString("admin_cipher", null)
        val ivText = prefs.getString("admin_iv", null)
        if (cipherText != null && ivText != null) {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key,
                GCMParameterSpec(128, Base64.decode(ivText, Base64.NO_WRAP)))
            return String(cipher.doFinal(Base64.decode(cipherText, Base64.NO_WRAP)), Charsets.UTF_8)
        }
        val bytes = ByteArray(32).also { SecureRandom().nextBytes(it) }
        val secret = Base64.encodeToString(bytes, Base64.NO_WRAP or Base64.URL_SAFE)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key)
        val encrypted = cipher.doFinal(secret.toByteArray(Charsets.UTF_8))
        check(prefs.edit().putString("admin_cipher", Base64.encodeToString(encrypted, Base64.NO_WRAP))
            .putString("admin_iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP)).commit())
        return secret
    }

    private fun ensure(): String {
        val directory = File(context().filesDir, "openlist-lite")
        if (!initialized) {
            Openlistlib.init(directory.absolutePath, password())
            initialized = true
        }
        if (!started) {
            // Do not attach to an unrelated server on the fixed loopback port.
            ServerSocket().use { socket ->
                socket.reuseAddress = false
                socket.bind(InetSocketAddress("127.0.0.1", PORT))
            }
            Openlistlib.start()
            val deadline = System.currentTimeMillis() + 15_000L
            var ready = false
            while (System.currentTimeMillis() < deadline) {
                try {
                    val connection = URL("$BASE/ping").openConnection() as HttpURLConnection
                    connection.connectTimeout = 500
                    connection.readTimeout = 500
                    ready = try { connection.responseCode == 200 && connection.inputStream.bufferedReader()
                        .use { it.readText() == "pong" } } finally { connection.disconnect() }
                    if (ready) break
                } catch (_: Exception) { }
                Thread.sleep(150)
            }
            if (!ready || !Openlistlib.running()) {
                runCatching { Openlistlib.stop() }
                error("OpenList did not bind loopback port $PORT")
            }
            started = true
        }
        scheduleIdle()
        return BASE
    }

    private fun scheduleIdle() {
        val stamp = ++generation
        if (mode() == "continuous" || leases.isNotEmpty() || !started) return
        main.postDelayed({
            worker.execute {
                if (stamp == generation && mode() == "smart" && leases.isEmpty()) stopIdle()
            }
        }, IDLE_MS)
    }

    private fun stopIdle() {
        if (!started) return
        Openlistlib.stop()
        started = false
        ++generation
    }

    /** When the user opens the app after process death, restore opt-in persistent mode. */
    fun onAppForeground() {
        if (mode() != "continuous") return
        val intent = Intent(context(), OpenListKeepAliveService::class.java)
        if (Build.VERSION.SDK_INT >= 26) context().startForegroundService(intent)
        else context().startService(intent)
    }

    fun ensureAsync() { worker.execute { runCatching { ensure() } } }
    fun active(): Boolean = started

    fun dispatch(method: String, args: Map<String, Any?>, callback: MethodChannel.Result) {
        worker.execute {
            try {
                val result: Any? = when (method) {
                    "ensure" -> ensure()
                    "acquire" -> {
                        val key = args["key"] as? String ?: error("missing key")
                        require(key.isNotBlank() && key.length <= 128)
                        ensure()
                        leases.add(key)
                        ++generation
                        BASE
                    }
                    "release" -> {
                        val key = args["key"] as? String ?: error("missing key")
                        leases.remove(key)
                        scheduleIdle()
                        null
                    }
                    "shutdown" -> {
                        context().stopService(Intent(context(), OpenListKeepAliveService::class.java))
                        leases.clear()
                        stopIdle()
                        null
                    }
                    "status" -> mapOf("running" to started, "mode" to mode(), "url" to BASE,
                        "leaseCount" to leases.size)
                    "mode" -> {
                        val desired = args["value"] as? String ?: error("missing mode")
                        require(desired == "smart" || desired == "continuous")
                        val previous = mode()
                        check(preferences().edit().putString("mode", desired).commit())
                        try {
                            if (desired == "continuous") {
                                val intent = Intent(context(), OpenListKeepAliveService::class.java)
                                if (Build.VERSION.SDK_INT >= 26) context().startForegroundService(intent)
                                else context().startService(intent)
                                ensure()
                            } else {
                                context().stopService(Intent(context(), OpenListKeepAliveService::class.java))
                                scheduleIdle()
                            }
                        } catch (e: Exception) {
                            preferences().edit().putString("mode", previous).commit()
                            if (desired == "continuous") {
                                context().stopService(Intent(context(), OpenListKeepAliveService::class.java))
                            }
                            throw e
                        }
                        desired
                    }
                    "adminPassword" -> password() // Explicitly requested in settings UI only.
                    "openUi" -> {
                        ensure()
                        val intent = Intent(context(), OpenListWebActivity::class.java)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        main.post { context().startActivity(intent) }
                        null
                    }
                    else -> error("unsupported method: $method")
                }
                main.post { callback.success(result) }
            } catch (error: Throwable) {
                main.post { callback.error("openlist_error", error.message ?: "OpenList failed", null) }
            }
        }
    }

    fun retainUi() { worker.execute { ensure(); leases.add("webui"); ++generation } }
    fun releaseUi() { worker.execute { leases.remove("webui"); scheduleIdle() } }
    fun disableContinuousFromNotification() {
        worker.execute {
            preferences().edit().putString("mode", "smart").commit()
            leases.remove("webui")
            scheduleIdle()
            main.post { context().stopService(Intent(context(), OpenListKeepAliveService::class.java)) }
        }
    }
    fun isContinuous(): Boolean = mode() == "continuous"
}
