package com.ymltsh.sylphymusic.playback

import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.URI
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/** Native Range relay. Capabilities and credentials stay in memory, outside MediaItem.
 * Redirects are followed only on the exact original origin, with TLS verified by
 * the platform. The source resolver may return an already-authorized CDN URL.
 */
class NativeStreamAdapter : AutoCloseable {
    private val server = ServerSocket(0, 8, InetAddress.getByName("127.0.0.1"))
    private val workers = Executors.newCachedThreadPool()
    private val sockets = ConcurrentHashMap.newKeySet<Socket>()
    private val connections = ConcurrentHashMap.newKeySet<HttpURLConnection>()
    @Volatile private var closed = false
    @Volatile private var source: Pair<URI, Map<String, String>>? = null
    @Volatile private var token = UUID.randomUUID().toString()
    init {
        workers.execute {
            while (!closed) {
                try {
                    val socket = server.accept()
                    sockets.add(socket)
                    workers.execute { relay(socket) }
                } catch (_: Exception) { if (!closed) close() }
            }
        }
    }
    fun open(uri: String, headers: Map<String, String>): String {
        cancel()
        val parsed = URI(uri)
        require(parsed.scheme in listOf("http", "https") && parsed.host != null && parsed.userInfo == null)
        require(headers.none { (key, value) -> key.contains('\r') || key.contains('\n') || value.contains('\r') || value.contains('\n') })
        source = parsed to headers
        token = UUID.randomUUID().toString()
        return "http://127.0.0.1:${server.localPort}/$token"
    }
    fun cancel() {
        source = null
        token = UUID.randomUUID().toString()
        connections.toList().forEach { it.disconnect() }
        sockets.toList().forEach { try { it.close() } catch (_: Exception) {} }
    }
    private fun relay(socket: Socket) {
        var upstream: HttpURLConnection? = null
        try {
            socket.soTimeout = 15000
            val reader = socket.getInputStream().bufferedReader(Charsets.US_ASCII)
            val request = reader.readLine()?.split(' ') ?: return
            val descriptor = source ?: return
            if (request.size != 3 || request[1] != "/$token" || request[0] !in listOf("GET", "HEAD")) return
            var range: String? = null
            var count = 0
            while (true) {
                val line = reader.readLine() ?: return
                if (line.isEmpty()) break
                if (++count > 64 || line.length > 8192) return
                if (line.startsWith("Range:", true)) range = line.substringAfter(':').trim()
            }
            if (range != null && !Regex("bytes=\\d*-\\d*").matches(range)) return
            var target = descriptor.first
            for (redirect in 0..5) {
                upstream = target.toURL().openConnection() as HttpURLConnection
                connections.add(upstream)
                upstream.instanceFollowRedirects = false
                upstream.connectTimeout = 15000
                upstream.readTimeout = 20000
                upstream.requestMethod = request[0]
                upstream.setRequestProperty("Accept-Encoding", "identity")
                descriptor.second.forEach { (key, value) -> upstream.setRequestProperty(key, value) }
                if (range != null) upstream.setRequestProperty("Range", range)
                val status = upstream.responseCode
                if (status in 300..399) {
                    val location = upstream.getHeaderField("Location") ?: return
                    val next = target.resolve(location)
                    fun port(uri: URI) = if (uri.port >= 0) uri.port else if (uri.scheme == "https") 443 else 80
                    if (next.scheme != descriptor.first.scheme || next.host != descriptor.first.host ||
                        port(next) != port(descriptor.first) || next.userInfo != null || redirect == 5) return
                    connections.remove(upstream); upstream.disconnect(); upstream = null
                    target = next
                    continue
                }
                // A revoked/replaced descriptor cannot complete a stale HTTP request.
                if (source !== descriptor) return
                val output = socket.getOutputStream()
                val headers = StringBuilder("HTTP/1.1 $status Media\r\nConnection: close\r\n")
                for (name in listOf("Content-Length", "Content-Range", "Content-Type", "Accept-Ranges", "ETag")) {
                    val value = upstream.getHeaderField(name)
                    if (value != null && !value.contains('\r') && !value.contains('\n')) headers.append("$name: $value\r\n")
                }
                output.write(headers.append("\r\n").toString().toByteArray(Charsets.US_ASCII))
                if (request[0] == "GET" && status in 200..299) upstream.inputStream.use { it.copyTo(output) }
                output.flush()
                break
            }
        } catch (_: Exception) {
            // Never log a URL, header, library title or platform exception text.
        } finally {
            upstream?.let { connections.remove(it); it.disconnect() }
            sockets.remove(socket)
            try { socket.close() } catch (_: Exception) {}
        }
    }
    override fun close() {
        closed = true; cancel()
        try { server.close() } catch (_: Exception) {}
        workers.shutdownNow()
    }
}
