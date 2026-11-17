package org.chadracklonde.andika

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Pont unique entre Dart et Android. Chaque fonction est décrite dans
 * lib/platform/platform_bridge.dart. Les réponses sont toujours renvoyées sur le
 * fil principal, même quand le travail se fait dans un fil de fond.
 */
class PlatformBridge(
    private val activity: MainActivity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "org.chadracklonde.andika/platform"
        const val REQ_PICK = 4201
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingPick: MethodChannel.Result? = null
    private var decoder: AudioDecoder? = null
    private var shareConsumed = false

    init {
        channel.setMethodCallHandler(this)
    }

    // --- Utilitaires -----------------------------------------------------------

    private fun postToMain(block: () -> Unit) {
        mainHandler.post(block)
    }

    /** Envoie un événement à Dart. */
    fun emit(method: String, arguments: Any?) {
        postToMain { channel.invokeMethod(method, arguments) }
    }

    private fun describe(uri: Uri): Map<String, Any?> {
        var name: String? = null
        var size = -1L
        try {
            activity.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (nameIndex >= 0) name = cursor.getString(nameIndex)
                    val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) size = cursor.getLong(sizeIndex)
                }
            }
        } catch (_: Exception) {
        }
        return mapOf(
            "uri" to uri.toString(),
            "name" to (name ?: uri.lastPathSegment ?: "audio"),
            "size" to size,
        )
    }

    private fun sharedUri(intent: Intent?): Uri? {
        if (intent == null) return null
        return when (intent.action) {
            Intent.ACTION_SEND ->
                if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                }
            Intent.ACTION_VIEW -> intent.data
            else -> null
        }
    }

    // --- Appels depuis Dart ----------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickAudio" -> pickAudio(result)
            "getInitialShare" -> {
                val uri = if (shareConsumed) null else sharedUri(activity.intent)
                shareConsumed = true
                result.success(if (uri != null) describe(uri) else null)
            }
            "getDeviceInfo" -> result.success(deviceInfo())
            "getPaths" -> result.success(
                mapOf(
                    "files" to activity.filesDir.absolutePath,
                    "cache" to activity.cacheDir.absolutePath,
                ),
            )
            "decodeToWav" -> decodeToWav(call, result)
            "cancelDecode" -> {
                decoder?.cancelled = true
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun pickAudio(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("busy", "Une sélection est déjà en cours", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("audio/*", "video/*", "application/ogg"))
        }
        pendingPick = result
        try {
            activity.startActivityForResult(intent, REQ_PICK)
        } catch (e: Exception) {
            pendingPick = null
            result.error("no_picker", "Aucun sélecteur de fichiers disponible", null)
        }
    }

    /** Retourne vrai si le résultat concernait ce pont. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_PICK) return false
        val result = pendingPick ?: return true
        pendingPick = null
        val uri = data?.data
        if (resultCode != android.app.Activity.RESULT_OK || uri == null) {
            result.success(null)
        } else {
            result.success(describe(uri))
        }
        return true
    }

    fun onNewIntent(intent: Intent) {
        val uri = sharedUri(intent) ?: return
        emit("shared", describe(uri))
    }

    private fun deviceInfo(): Map<String, Any?> {
        val am = activity.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val mem = ActivityManager.MemoryInfo()
        am.getMemoryInfo(mem)
        val stat = StatFs(activity.filesDir.absolutePath)
        return mapOf(
            "totalRamBytes" to mem.totalMem,
            "availableRamBytes" to mem.availMem,
            "freeStorageBytes" to stat.availableBytes,
            "sdkInt" to Build.VERSION.SDK_INT,
            "abi" to (Build.SUPPORTED_ABIS.firstOrNull() ?: ""),
            "model" to "${Build.MANUFACTURER} ${Build.MODEL}",
        )
    }

    private fun decodeToWav(call: MethodCall, result: MethodChannel.Result) {
        val uriText = call.argument<String>("uri")
        val outPath = call.argument<String>("outPath")
        if (uriText == null || outPath == null) {
            result.error("bad_args", "uri ou outPath manquant", null)
            return
        }
        if (decoder != null) {
            result.error("busy", "Un décodage est déjà en cours", null)
            return
        }
        val dec = AudioDecoder(activity.applicationContext)
        decoder = dec
        Thread {
            try {
                val out = File(outPath)
                out.parentFile?.mkdirs()
                val r = dec.decode(Uri.parse(uriText), out) { percent ->
                    emit("decodeProgress", percent)
                }
                postToMain {
                    decoder = null
                    result.success(mapOf("durationMs" to r.durationMs, "sampleCount" to r.sampleCount))
                }
            } catch (e: DecodeException) {
                postToMain {
                    decoder = null
                    result.error(e.code, e.message, null)
                }
            } catch (e: Throwable) {
                postToMain {
                    decoder = null
                    result.error("decode_error", e.message, null)
                }
            }
        }.start()
    }
}
