package com.axialforge.cardkeep

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * A .vcf opened or shared from another app (S13.4) is read here and handed to
 * Flutter, which shows the Import screen. Only the file the user chose is read;
 * it is capped at 1 MB like every other vCard source.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pending: ByteArray? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cardkeep/incoming").apply {
            setMethodCallHandler { call, result ->
                if (call.method == "takeVcf") {
                    result.success(pending)
                    pending = null
                } else {
                    result.notImplemented()
                }
            }
        }
        pending = readVcf(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val bytes = readVcf(intent) ?: return
        channel?.invokeMethod("vcf", bytes) ?: run { pending = bytes }
    }

    private fun readVcf(intent: Intent?): ByteArray? {
        if (intent == null) return null
        val uri: Uri = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> @Suppress("DEPRECATION") intent.getParcelableExtra(Intent.EXTRA_STREAM)
            else -> null
        } ?: return null
        return try {
            contentResolver.openInputStream(uri)?.use { input ->
                val out = java.io.ByteArrayOutputStream()
                val buf = ByteArray(8192)
                var total = 0
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    total += n
                    if (total > 1024 * 1024) return null
                    out.write(buf, 0, n)
                }
                out.toByteArray()
            }
        } catch (e: Exception) {
            null
        }
    }
}
