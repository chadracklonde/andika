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
        const val REQ_NOTIF = 4202
        const val REQ_MIC = 4203
        const val REQ_SAVE = 4204
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingPick: MethodChannel.Result? = null
    private var pendingNotif: MethodChannel.Result? = null
    private var pendingMic: MethodChannel.Result? = null
    private var pendingSave: MethodChannel.Result? = null
    private var pendingSavePath: String? = null
    private val audioPlayer = AudioPlayer { state -> emit("playerState", state) }
    private var decoder: AudioDecoder? = null
    private var shareConsumed = false

    init {
        channel.setMethodCallHandler(this)
        RecorderHub.listener = { state -> emit("recorderState", state) }
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

    /// Fichiers reçus par « Partager » (un ou plusieurs, par exemple des vocaux WhatsApp) ou « Ouvrir avec ».
    private fun sharedUris(intent: Intent?): List<Uri> {
        if (intent == null) return emptyList()
        return when (intent.action) {
            Intent.ACTION_SEND -> {
                val uri: Uri? = if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                }
                listOfNotNull(uri)
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                val list: ArrayList<Uri>? = if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                }
                list?.filterNotNull() ?: emptyList()
            }
            Intent.ACTION_VIEW -> listOfNotNull(intent.data)
            else -> emptyList()
        }
    }

    // --- Appels depuis Dart ----------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickAudio" -> pickAudio(result)
            "getInitialShare" -> {
                val uris = if (shareConsumed) emptyList() else sharedUris(activity.intent)
                shareConsumed = true
                result.success(uris.map { describe(it) })
            }
            "getDeviceInfo" -> result.success(deviceInfo())
            "getPaths" -> result.success(
                mapOf(
                    "files" to activity.filesDir.absolutePath,
                    "cache" to activity.cacheDir.absolutePath,
                ),
            )
            "decodeToWav" -> decodeToWav(call, result)
            "startForeground" -> {
                val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
                TranscriptionService.start(
                    activity,
                    (args["title"] as? String) ?: "Andika",
                    (args["text"] as? String) ?: "",
                    (args["progress"] as? Number)?.toInt() ?: -1,
                    (args["channelName"] as? String) ?: "Transcription",
                )
                result.success(null)
            }
            "stopForeground" -> {
                TranscriptionService.stop(activity)
                result.success(null)
            }
            "notificationsAllowed" -> result.success(notificationsAllowed())
            "requestNotifications" -> requestNotifications(result)
            "playerLoad" -> {
                try {
                    val path = call.argument<String>("path") ?: throw IllegalArgumentException("path")
                    result.success(audioPlayer.load(path))
                } catch (e: Exception) {
                    result.error("player", e.message ?: "Lecture impossible", null)
                }
            }
            "playerPlay" -> { audioPlayer.play(); result.success(null) }
            "playerPause" -> { audioPlayer.pause(); result.success(null) }
            "playerSeek" -> {
                audioPlayer.seek(call.argument<Int>("positionMs") ?: 0)
                result.success(null)
            }
            "playerSpeed" -> {
                audioPlayer.setSpeed((call.argument<Double>("speed") ?: 1.0).toFloat())
                result.success(null)
            }
            "playerRelease" -> { audioPlayer.release(); result.success(null) }
            "shareFile" -> {
                try {
                    shareFile(
                        call.argument<String>("path") ?: throw IllegalArgumentException("path"),
                        call.argument<String>("mime") ?: "text/plain",
                        call.argument<String>("title") ?: "",
                    )
                    result.success(null)
                } catch (e: Exception) {
                    result.error("share", e.message ?: "Partage impossible", null)
                }
            }
            "getBatteryInfo" -> result.success(batteryInfo())
            "microphoneAllowed" -> result.success(microphoneAllowed())
            "requestMicrophone" -> requestMicrophone(result)
            "recorderStart" -> recorderStart(call, result)
            "recorderPause" -> { RecorderHub.recorder?.pause(); result.success(null) }
            "recorderResume" -> { RecorderHub.recorder?.resume(); result.success(null) }
            "recorderStop" -> recorderStop(result)
            "recorderStatus" -> result.success(RecorderHub.status())
            "saveFileAs" -> saveFileAs(call, result)
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
        if (requestCode == REQ_SAVE) {
            onSaveResult(resultCode, data)
            return true
        }
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
        val uris = sharedUris(intent)
        if (uris.isEmpty()) return
        emit("shared", uris.map { describe(it) })
    }

    private fun shareFile(path: String, mime: String, title: String) {
        val file = File(path)
        val uri = androidx.core.content.FileProvider.getUriForFile(
            activity, "${activity.packageName}.fileprovider", file,
        )
        val send = Intent(Intent.ACTION_SEND)
            .setType(mime)
            .putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        activity.startActivity(Intent.createChooser(send, title))
    }

    private fun notificationsAllowed(): Boolean {
        if (Build.VERSION.SDK_INT < 33) return true
        return activity.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
            android.content.pm.PackageManager.PERMISSION_GRANTED
    }

    private fun requestNotifications(result: MethodChannel.Result) {
        if (notificationsAllowed()) {
            result.success(true)
            return
        }
        if (pendingNotif != null) {
            result.error("busy", "Une demande est déjà en cours", null)
            return
        }
        pendingNotif = result
        activity.requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIF)
    }

    /** Retourne vrai si le résultat concernait ce pont. */
    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode == REQ_MIC) {
            val mic = pendingMic ?: return true
            pendingMic = null
            mic.success(grantResults.isNotEmpty() &&
                grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED)
            return true
        }
        if (requestCode != REQ_NOTIF) return false
        val result = pendingNotif ?: return true
        pendingNotif = null
        result.success(grantResults.isNotEmpty() &&
            grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED)
        return true
    }

    // --- Enregistreur et « Enregistrer sous… » ---------------------------------

    private fun microphoneAllowed(): Boolean =
        activity.checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) ==
            android.content.pm.PackageManager.PERMISSION_GRANTED

    private fun requestMicrophone(result: MethodChannel.Result) {
        if (microphoneAllowed()) {
            result.success(true)
            return
        }
        if (pendingMic != null) {
            result.error("busy", "Une demande est déjà en cours", null)
            return
        }
        pendingMic = result
        activity.requestPermissions(arrayOf(android.Manifest.permission.RECORD_AUDIO), REQ_MIC)
    }

    private fun recorderStart(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path == null) {
            result.error("bad_args", "path manquant", null)
            return
        }
        if (RecorderHub.recorder?.isRunning == true) {
            result.error("busy", "Un enregistrement est déjà en cours", null)
            return
        }
        if (!microphoneAllowed()) {
            result.error("permission", "Autorisation du micro refusée", null)
            return
        }
        val appContext = activity.applicationContext
        val rec = AudioRecorder(File(path)) { state, elapsed, level, error ->
            RecorderHub.listener?.invoke(
                mapOf("state" to state, "elapsedMs" to elapsed, "level" to level, "error" to error),
            )
            if (state == "stopped") RecorderService.stop(appContext)
        }
        try {
            rec.start()
        } catch (e: RecorderException) {
            result.error(e.code, e.message, null)
            return
        }
        RecorderHub.recorder = rec
        try {
            RecorderService.start(
                activity,
                call.argument<String>("title") ?: "Andika",
                call.argument<String>("text") ?: "",
                call.argument<String>("channelName") ?: "Enregistrement",
            )
        } catch (e: Exception) {
            Thread { rec.stop() }.start()
            RecorderHub.recorder = null
            result.error("service", e.message ?: "Service impossible à démarrer", null)
            return
        }
        result.success(null)
    }

    private fun recorderStop(result: MethodChannel.Result) {
        val rec = RecorderHub.recorder
        if (rec == null) {
            result.success(mapOf("durationMs" to 0L, "path" to null))
            return
        }
        Thread {
            val ms = rec.stop()
            postToMain {
                if (RecorderHub.recorder === rec) RecorderHub.recorder = null
                result.success(mapOf("durationMs" to ms, "path" to rec.path))
            }
        }.start()
    }

    private fun saveFileAs(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        val name = call.argument<String>("name")
        val mime = call.argument<String>("mime") ?: "application/octet-stream"
        if (path == null || name == null) {
            result.error("bad_args", "path ou name manquant", null)
            return
        }
        if (pendingSave != null) {
            result.error("busy", "Un enregistrement de fichier est déjà en cours", null)
            return
        }
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mime
            putExtra(Intent.EXTRA_TITLE, name)
        }
        pendingSave = result
        pendingSavePath = path
        try {
            activity.startActivityForResult(intent, REQ_SAVE)
        } catch (e: Exception) {
            pendingSave = null
            pendingSavePath = null
            result.error("no_picker", "Aucun sélecteur de fichiers disponible", null)
        }
    }

    private fun onSaveResult(resultCode: Int, data: Intent?) {
        val result = pendingSave ?: return
        val path = pendingSavePath
        pendingSave = null
        pendingSavePath = null
        val uri = data?.data
        if (resultCode != android.app.Activity.RESULT_OK || uri == null || path == null) {
            result.success(false)
            return
        }
        Thread {
            try {
                val out = activity.contentResolver.openOutputStream(uri, "w")
                    ?: throw java.io.IOException("Destination inaccessible")
                out.use { o -> File(path).inputStream().use { it.copyTo(o) } }
                postToMain { result.success(true) }
            } catch (e: Exception) {
                postToMain { result.error("save_failed", e.message ?: "Enregistrement impossible", null) }
            }
        }.start()
    }

    private fun batteryInfo(): Map<String, Any?> {
        val bm = activity.getSystemService(Context.BATTERY_SERVICE) as android.os.BatteryManager
        val pm = activity.getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
        val level = bm.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY)
        val status = bm.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_STATUS)
        val charging = status == android.os.BatteryManager.BATTERY_STATUS_CHARGING ||
            status == android.os.BatteryManager.BATTERY_STATUS_FULL
        return mapOf(
            "level" to level,
            "charging" to charging,
            "powerSave" to pm.isPowerSaveMode,
            "ignoringOptimizations" to pm.isIgnoringBatteryOptimizations(activity.packageName),
        )
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
