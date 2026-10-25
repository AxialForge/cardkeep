package com.axialforge.cardkeep

import android.content.ClipData
import android.content.ClipboardManager
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PersistableBundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * A .vcf opened or shared from another app (S13.4) is read here and handed to
 * Flutter, which shows the Import screen. Only the file the user chose is read;
 * it is capped at 1 MB like every other vCard source.
 *
 * A FragmentActivity so the phone's fingerprint / passcode prompt (App lock, S15.2) can show.
 */
class MainActivity : FlutterFragmentActivity() {
    private var channel: MethodChannel? = null
    private var pending: ByteArray? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cardkeep/incoming").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeVcf" -> {
                        result.success(pending)
                        pending = null
                    }
                    // NFC is off: open its settings page (S14.13).
                    "openNfcSettings" -> {
                        try {
                            startActivity(Intent(android.provider.Settings.ACTION_NFC_SETTINGS))
                        } catch (e: Exception) {
                            startActivity(Intent(android.provider.Settings.ACTION_WIRELESS_SETTINGS))
                        }
                        result.success(null)
                    }
                    // Contact details copied to the clipboard are hidden from the paste preview (MOB-SEC-0007).
                    "copySensitive" -> {
                        val clip = ClipData.newPlainText("CardKeep", call.argument<String>("text") ?: "")
                        clip.description.extras = PersistableBundle().apply {
                            // ClipDescription.EXTRA_IS_SENSITIVE (API 33); older versions ignore it.
                            putBoolean("android.content.extra.IS_SENSITIVE", true)
                        }
                        (getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(clip)
                        result.success(null)
                    }
                    // Dialer, mail, messages, maps and the browser open in their own task, so leaving
                    // CardKeep with Back goes home instead of into the dialer (phone test F3).
                    "openExternal" -> {
                        val uri = Uri.parse(call.arguments as String)
                        val action = when (uri.scheme) {
                            "tel" -> Intent.ACTION_DIAL
                            "mailto", "sms", "smsto" -> Intent.ACTION_SENDTO
                            else -> Intent.ACTION_VIEW
                        }
                        val i = Intent(action, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        result.success(
                            try {
                                startActivity(i)
                                true
                            } catch (e: Exception) {
                                false
                            }
                        )
                    }
                    // Settings > Privacy > Hide in recents (MOB-SEC-0004).
                    "setSecure" -> {
                        val on = call.arguments == true
                        if (on) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        // API 33+: no switcher snapshot at all while on (phone test F30).
                        if (android.os.Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(!on)
                        result.success(null)
                    }
                    else -> result.notImplemented()
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
        // Only a file another app hands over: never a file:// path, and never one of CardKeep's
        // own providers, which could expose private files (audit MOB-SEC-0006).
        if (uri.scheme != ContentResolver.SCHEME_CONTENT) return null
        val authority = uri.authority ?: return null
        if (authority == packageName || authority.startsWith("$packageName.")) return null
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
