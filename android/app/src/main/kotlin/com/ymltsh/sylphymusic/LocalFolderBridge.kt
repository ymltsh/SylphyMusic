package com.ymltsh.sylphymusic

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.io.InterruptedIOException
import java.security.MessageDigest
import java.util.ArrayDeque
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * SAF folder access for user-selected audio directories.
 *
 * Playback currently requires ordinary file paths, so each SAF document is
 * streamed into a stable, app-private copy. Neither original files nor the
 * provider's document tree are modified. No broad media permission is needed.
 */
class LocalFolderBridge(
    private val activity: MainActivity,
    messenger: BinaryMessenger,
) {
    companion object {
        private const val PICK_REQUEST = 49216
        private val AUDIO_EXTENSIONS = setOf(
            "mp3", "flac", "ogg", "opus", "wav", "m4a", "aac", "ape", "aiff"
        )
    }

    private val channel = MethodChannel(messenger, "music.sylphy/local_folders")
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val scanning = AtomicBoolean(false)
    private var pendingPicker: MethodChannel.Result? = null
    private var detached = false

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "pick" -> pick(result)
                "scan" -> {
                    val tree = call.argument<String>("uri")
                    val sourceId = call.argument<String>("sourceId")
                    val root = call.argument<String>("root")
                    if (tree.isNullOrEmpty() || sourceId.isNullOrEmpty() || root.isNullOrEmpty()) {
                        result.error("invalid_request", "缺少目录扫描参数", null)
                    } else if (!scanning.compareAndSet(false, true)) {
                        result.error("scan_busy", "已有文件夹扫描任务", null)
                    } else {
                        worker.execute {
                            try {
                                val data = scanTree(Uri.parse(tree), sourceId, root)
                                main.post { if (!detached) result.success(data) }
                            } catch (error: Exception) {
                                val code = when (error) {
                                    is SecurityException -> "permission_denied"
                                    is FileNotFoundException -> "file_missing"
                                    is IOException -> "io_error"
                                    else -> "scan_failed"
                                }
                                main.post { if (!detached) result.error(code, error.javaClass.simpleName, null) }
                            } finally {
                                scanning.set(false)
                            }
                        }
                    }
                }
                "release" -> {
                    val uri = call.argument<String>("uri")
                    if (uri.isNullOrEmpty()) {
                        result.error("invalid_request", "缺少目录 URI", null)
                    } else {
                        try {
                            activity.contentResolver.releasePersistableUriPermission(
                                Uri.parse(uri), Intent.FLAG_GRANT_READ_URI_PERMISSION
                            )
                            result.success(null)
                        } catch (_: SecurityException) {
                            // Can occur after the permission was revoked in Settings.
                            result.success(null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun pick(result: MethodChannel.Result) {
        if (pendingPicker != null) {
            result.error("picker_busy", "文件夹选择器已打开", null)
            return
        }
        pendingPicker = result
        try {
            @Suppress("DEPRECATION")
            activity.startActivityForResult(
                Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                }, PICK_REQUEST
            )
        } catch (error: Exception) {
            pendingPicker = null
            result.error("picker_failed", error.javaClass.simpleName, null)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_REQUEST) return false
        val result = pendingPicker ?: return true
        pendingPicker = null
        val tree = if (resultCode == Activity.RESULT_OK) data?.data else null
        if (tree == null) {
            result.success(null)
            return true
        }
        try {
            activity.contentResolver.takePersistableUriPermission(
                tree, Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
            result.success(mapOf("uri" to tree.toString(), "name" to titleOf(tree)))
        } catch (error: Exception) {
            result.error("permission_denied", error.javaClass.simpleName, null)
        }
        return true
    }

    private fun titleOf(tree: Uri): String {
        return try {
            val document = DocumentsContract.buildDocumentUriUsingTree(
                tree, DocumentsContract.getTreeDocumentId(tree)
            )
            activity.contentResolver.query(
                document, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                null, null, null
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }?.takeIf { it.isNotBlank() } ?: "本地音乐文件夹"
        } catch (_: Exception) {
            "本地音乐文件夹"
        }
    }

    private fun sha256(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8))
        .joinToString("") { "%02x".format(it.toInt() and 0xff) }

    private fun scanTree(tree: Uri, sourceId: String, rootPath: String): Map<String, Any> {
        require(tree.scheme == "content") { "不是 SAF 文档 URI" }
        require(sourceId.matches(Regex("[A-Za-z0-9_-]{1,64}"))) { "音乐源 ID 无效" }
        val root = File(rootPath).canonicalFile
        val appFiles = activity.filesDir.canonicalFile
        require(root.path.startsWith(appFiles.path + File.separator)) { "存储位置无效" }
        val grant = activity.contentResolver.persistedUriPermissions.any {
            it.uri == tree && it.isReadPermission
        }
        if (!grant) throw SecurityException("目录授权已失效")

        val destRoot = File(root, "saf/$sourceId")
        check(destRoot.isDirectory || destRoot.mkdirs()) { "无法创建缓存目录" }

        data class PendingDir(val id: String, val relativePath: String)
        val documents = ArrayDeque<PendingDir>()
        val seen = HashSet<String>()
        documents.add(PendingDir(DocumentsContract.getTreeDocumentId(tree), ""))
        val files = ArrayList<Map<String, Any>>()
        var visited = 0
        var copied = 0
        var reused = 0
        while (!documents.isEmpty()) {
            if (Thread.currentThread().isInterrupted) throw InterruptedIOException("扫描已取消")
            val folder = documents.removeFirst()
            val parentId = folder.id
            if (!seen.add(parentId)) continue
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentId)
            val columns = arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_SIZE,
                DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            )
            val cursor = activity.contentResolver.query(children, columns, null, null, null)
                ?: throw IOException("目录提供方未返回文件列表")
            // Finish provider queries before copying gigabytes of content. Holding
            // a provider Cursor while streaming files can keep Binder resources
            // busy and cause some vendors' DocumentsProviders to time out.
            data class Child(
                val id: String, val name: String, val mime: String?,
                val size: Long, val changedAt: Long,
            )
            val snapshot = ArrayList<Child>()
            cursor.use { rows ->
                val idCol = rows.getColumnIndexOrThrow(columns[0])
                val nameCol = rows.getColumnIndexOrThrow(columns[1])
                val mimeCol = rows.getColumnIndexOrThrow(columns[2])
                val sizeCol = rows.getColumnIndex(columns[3])
                val timeCol = rows.getColumnIndex(columns[4])
                while (rows.moveToNext()) {
                    val id = rows.getString(idCol) ?: throw IOException("文件缺少 documentId")
                    val name = rows.getString(nameCol) ?: continue
                    val size = if (sizeCol >= 0 && !rows.isNull(sizeCol))
                        rows.getLong(sizeCol) else -1L
                    val changedAt = if (timeCol >= 0 && !rows.isNull(timeCol))
                        rows.getLong(timeCol) else 0L
                    snapshot.add(Child(id, name, rows.getString(mimeCol), size, changedAt))
                }
            }
            for (child in snapshot) {
                if (Thread.currentThread().isInterrupted) throw InterruptedIOException("扫描已取消")
                visited++
                if (child.mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                    val nested = if (folder.relativePath.isEmpty()) child.name
                        else "${folder.relativePath}/${child.name}"
                    documents.add(PendingDir(child.id, nested))
                    continue
                }
                val extension = child.name.substringAfterLast('.', "").lowercase()
                if (extension !in AUDIO_EXTENSIONS && extension != "lrc") continue
                val parent = File(destRoot, sha256(parentId).take(24))
                check(parent.isDirectory || parent.mkdirs()) { "无法创建目录" }
                // Audio and matching .lrc share the same basename/hash.
                val stem = child.name.substringBeforeLast('.', child.name)
                val basename = sha256("$parentId\u0000$stem").take(32)
                val target = File(parent, "$basename.$extension")
                val document = DocumentsContract.buildDocumentUriUsingTree(tree, child.id)
                val reusedFile = copyIfChanged(document, target, child.size, child.changedAt)
                if (reusedFile) reused++ else copied++
                if (extension in AUDIO_EXTENSIONS) {
                    files.add(mapOf(
                        "path" to target.absolutePath,
                        "name" to child.name,
                        "relativePath" to (if (folder.relativePath.isEmpty()) child.name
                            else "${folder.relativePath}/${child.name}"),
                        "reused" to reusedFile,
                    ))
                }
            }
        }
        return mapOf(
            "files" to files,
            "visited_count" to visited,
            "copied_count" to copied,
            "reused_count" to reused,
        )
    }

    private fun copyIfChanged(document: Uri, target: File, size: Long, changedAt: Long): Boolean {
        if (size >= 0L && changedAt > 0L && target.isFile &&
            target.length() == size && target.lastModified() == changedAt) return true

        val temp = File.createTempFile(".saf-", ".part", target.parentFile)
        try {
            val input = activity.contentResolver.openInputStream(document)
                ?: throw FileNotFoundException("无法读取 SAF 文件")
            input.use { source ->
                temp.outputStream().buffered().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        if (Thread.currentThread().isInterrupted) {
                            throw InterruptedIOException("文件复制已取消")
                        }
                        val count = source.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                    }
                }
            }
            if (changedAt > 0L) temp.setLastModified(changedAt)
            if (Build.VERSION.SDK_INT >= 26) {
                try {
                    java.nio.file.Files.move(
                        temp.toPath(), target.toPath(),
                        java.nio.file.StandardCopyOption.ATOMIC_MOVE,
                        java.nio.file.StandardCopyOption.REPLACE_EXISTING,
                    )
                } catch (_: java.nio.file.AtomicMoveNotSupportedException) {
                    java.nio.file.Files.move(
                        temp.toPath(), target.toPath(),
                        java.nio.file.StandardCopyOption.REPLACE_EXISTING,
                    )
                }
            } else {
                val backup = File(target.parentFile, "${target.name}.old")
                if (target.exists() && !target.renameTo(backup)) {
                    throw IOException("无法备份现有文件")
                }
                if (!temp.renameTo(target)) {
                    if (backup.exists()) backup.renameTo(target)
                    throw IOException("无法完成文件导入")
                }
                backup.delete()
            }
        } finally {
            temp.delete()
        }
        return false
    }

    fun detach() {
        detached = true
        pendingPicker?.error("picker_detached", "文件夹选择器已关闭", null)
        pendingPicker = null
        channel.setMethodCallHandler(null)
        worker.shutdownNow()
    }
}
