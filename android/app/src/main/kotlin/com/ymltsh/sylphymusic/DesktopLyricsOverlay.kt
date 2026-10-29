package com.ymltsh.sylphymusic

import android.app.Application
import android.animation.ValueAnimator
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.roundToInt

/** Lightweight overlay in the audio_service-owned app process. Not a second engine. */
class DesktopLyricsOverlay(private val app: Application) {
    private val manager by lazy { app.getSystemService(WindowManager::class.java) }
    private var window: LinearLayout? = null
    private var line: TextView? = null
    private var params: WindowManager.LayoutParams? = null
    private var closeButton: TextView? = null
    private val handler = Handler(Looper.getMainLooper())
    private var chromeFade: ValueAnimator? = null
    private var lastColor: Int? = null
    private var lastFontSize: Float? = null
    private val hideChrome = Runnable {
        val panel = window?.background ?: return@Runnable
        val close = closeButton ?: return@Runnable
        chromeFade?.cancel()
        chromeFade = ValueAnimator.ofInt(panel.alpha, 0).apply {
            duration = 350
            addUpdateListener {
                val opacity = it.animatedValue as Int
                panel.alpha = opacity
                close.alpha = opacity / 255f
                if (opacity == 0) close.visibility = View.INVISIBLE
            }
            start()
        }
    }

    private fun revealControls(scheduleHide: Boolean = true) {
        handler.removeCallbacks(hideChrome)
        chromeFade?.cancel()
        chromeFade = null
        window?.background?.alpha = 255
        closeButton?.apply {
            visibility = View.VISIBLE
            alpha = 1f
        }
        if (scheduleHide) handler.postDelayed(hideChrome, 2500)
    }

    fun hasPermission(): Boolean =
        Build.VERSION.SDK_INT < 23 || Settings.canDrawOverlays(app)

    fun requestPermission() {
        if (hasPermission()) return
        val intent = Intent(
            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            Uri.parse("package:${app.packageName}")
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        app.startActivity(intent)
    }

    fun show(text: String, color: Int, fontSize: Float, onClose: () -> Unit) {
        if (!hasPermission()) throw SecurityException("悬浮窗权限未授予")
        val size = fontSize.coerceIn(12f, 40f)
        val reveal = window == null || lastColor != color || lastFontSize != size
        if (window == null) {
            val density = app.resources.displayMetrics.density
            fun px(dp: Float) = (dp * density).roundToInt()
            val container = LinearLayout(app).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(px(12f), px(6f), px(6f), px(6f))
                background = GradientDrawable().apply {
                    cornerRadius = px(18f).toFloat()
                    setColor(Color.argb(180, 20, 24, 30))
                }
            }
            val lyric = TextView(app).apply {
                textSize = 20f
                gravity = Gravity.CENTER
                maxLines = 2
                maxWidth = (app.resources.displayMetrics.widthPixels * 0.78f).toInt()
                setShadowLayer(px(2f).toFloat(), 0f, px(1f).toFloat(), Color.BLACK)
                setPadding(px(8f), px(5f), px(8f), px(5f))
            }
            val close = TextView(app).apply {
                this.text = "×"
                textSize = 22f
                setTextColor(Color.WHITE)
                gravity = Gravity.CENTER
                contentDescription = "关闭桌面歌词"
                setPadding(px(8f), px(5f), px(8f), px(5f))
                setOnClickListener {
                    hide()
                    onClose()
                }
            }
            container.addView(lyric, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ))
            container.addView(close)
            val flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
            val layout = WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                else WindowManager.LayoutParams.TYPE_PHONE,
                flags,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                y = px(110f)
            }
            lyric.setOnTouchListener(object : View.OnTouchListener {
                private var downX = 0f
                private var downY = 0f
                private var startX = 0
                private var startY = 0
                override fun onTouch(v: View, event: MotionEvent): Boolean {
                    when (event.actionMasked) {
                        MotionEvent.ACTION_DOWN -> {
                            revealControls(scheduleHide = false)
                            downX = event.rawX
                            downY = event.rawY
                            startX = layout.x
                            startY = layout.y
                            return true
                        }
                        MotionEvent.ACTION_MOVE -> {
                            layout.x = startX + (event.rawX - downX).roundToInt()
                            layout.y = (startY + (event.rawY - downY).roundToInt())
                                .coerceAtLeast(0)
                            manager.updateViewLayout(container, layout)
                            return true
                        }
                        MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                            revealControls()
                            return true
                        }
                    }
                    return false
                }
            })
            manager.addView(container, layout)
            window = container
            line = lyric
            params = layout
            closeButton = close
        }
        line?.apply {
            this.text = text
            setTextColor(color)
            textSize = size
        }
        // Use a pale panel for dark text and a charcoal panel for light text.
        val brightness = (Color.red(color) * 0.2126f +
            Color.green(color) * 0.7152f + Color.blue(color) * 0.0722f) / 255f
        val contrast = brightness < 0.4f
        val panel = window?.background as? GradientDrawable
        val opacity = panel?.alpha ?: 255
        panel?.setColor(
            if (contrast) Color.argb(215, 232, 239, 238)
            else Color.argb(180, 20, 24, 30)
        )
        panel?.alpha = opacity
        closeButton?.setTextColor(if (contrast) Color.BLACK else Color.WHITE)
        lastColor = color
        lastFontSize = size
        if (reveal) revealControls()
    }

    fun hide() {
        handler.removeCallbacks(hideChrome)
        chromeFade?.cancel()
        chromeFade = null
        val old = window ?: return
        window = null
        line = null
        params = null
        closeButton = null
        lastColor = null
        lastFontSize = null
        try { manager.removeView(old) } catch (_: IllegalArgumentException) { }
    }
}
