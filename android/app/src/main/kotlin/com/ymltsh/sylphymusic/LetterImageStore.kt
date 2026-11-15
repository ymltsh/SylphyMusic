package com.ymltsh.sylphymusic

import android.Manifest
import android.app.Activity
import android.content.ContentValues
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Writes only explicitly exported PNGs to the public Pictures collection. */
class LetterImageStore(private val activity: Activity) {
    private data class Pending(val bytes: ByteArray, val name: String, val result: MethodChannel.Result)
    private var pending: Pending? = null

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "save") { result.notImplemented(); return }
        val bytes = call.argument<ByteArray>("bytes")
        val name = call.argument<String>("name")
        if (bytes == null || bytes.isEmpty() || bytes.size > 20 * 1024 * 1024 || name == null || !name.matches(Regex("SylphyMusic-letter-[0-9-]+\\.png"))) {
            result.error("invalid_image", "图片数据无效", null); return
        }
        val item = Pending(bytes, name, result)
        if (Build.VERSION.SDK_INT < 29 && activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
            if (pending != null) { result.error("busy", "正在请求存储权限", null); return }
            pending = item
            activity.requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 43)
        } else write(item)
    }

    fun permissionResult() {
        val item = pending ?: return
        pending = null
        if (activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED) write(item)
        else item.result.error("permission_denied", "未授予图片保存权限", null)
    }

    fun detach() {
        pending?.result?.error("activity_detached", "图片保存已取消，请重试", null)
        pending = null
    }

    private fun write(item: Pending) {
        val context = activity.applicationContext
        Thread {
            try {
                val location: String
                if (Build.VERSION.SDK_INT >= 29) {
                    val resolver = context.contentResolver
                    val values = ContentValues().apply {
                        put(MediaStore.Images.Media.DISPLAY_NAME, item.name)
                        put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                        put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/SylphyMusic")
                        put(MediaStore.Images.Media.IS_PENDING, 1)
                    }
                    val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: error("无法创建图片")
                    try {
                        val stream = resolver.openOutputStream(uri) ?: error("无法写入图片")
                        stream.use { it.write(item.bytes) }
                        val ready = ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }
                        check(resolver.update(uri, ready, null, null) == 1)
                    } catch (error: Exception) {
                        resolver.delete(uri, null, null)
                        throw error
                    }
                    location = "Pictures/SylphyMusic/${item.name}"
                } else {
                    val directory = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "SylphyMusic")
                    check(directory.isDirectory || directory.mkdirs())
                    val file = File(directory, item.name)
                    try { file.outputStream().use { it.write(item.bytes) } }
                    catch (error: Exception) { file.delete(); throw error }
                    MediaScannerConnection.scanFile(context, arrayOf(file.absolutePath), arrayOf("image/png"), null)
                    location = file.absolutePath
                }
                activity.runOnUiThread { item.result.success(location) }
            } catch (error: Exception) {
                activity.runOnUiThread { item.result.error("image_save_failed", "无法保存到 Pictures 目录", null) }
            }
        }.start()
    }
}
