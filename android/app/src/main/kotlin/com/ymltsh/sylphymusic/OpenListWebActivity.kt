package com.ymltsh.sylphymusic

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient

/** Web UI is bundled inside the Go server; no remote CDN or second Flutter UI. */
class OpenListWebActivity : Activity() {
    private lateinit var webView: WebView
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        OpenListRuntime.bind(applicationContext)
        OpenListRuntime.retainUi()
        webView = WebView(this)
        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        webView.settings.allowFileAccess = false
        webView.settings.allowContentAccess = false
        webView.settings.setSupportMultipleWindows(false)
        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val url = request.url
                if (url.scheme == "http" && url.host == "127.0.0.1" && url.port == 10486) return false
                if (url.scheme == "https") {
                    // OAuth/browser-based logins must leave the privileged local WebView.
                    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url.toString())))
                }
                return true
            }
        }
        setContentView(webView)
        webView.loadUrl(OpenListRuntime.BASE)
    }
    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (webView.canGoBack()) webView.goBack() else super.onBackPressed()
    }
    override fun onDestroy() {
        OpenListRuntime.releaseUi()
        webView.destroy()
        super.onDestroy()
    }
}
