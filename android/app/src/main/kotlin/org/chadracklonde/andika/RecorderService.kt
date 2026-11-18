package org.chadracklonde.andika

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Enregistreur partagé entre l'activité et le service : le service garde le processus
 * en vie (écran éteint, application en arrière-plan), l'enregistreur écrit dans son fil.
 */
object RecorderHub {
    @Volatile var recorder: AudioRecorder? = null

    /** Reçoit les événements d'état ; remplacé quand l'activité est recréée. */
    @Volatile var listener: ((Map<String, Any?>) -> Unit)? = null

    fun status(): Map<String, Any?> {
        val r = recorder
        return mapOf(
            "state" to when {
                r == null || !r.isRunning -> "idle"
                r.isPaused -> "paused"
                else -> "recording"
            },
            "elapsedMs" to (r?.elapsedMs ?: 0L),
            "level" to (r?.level ?: 0.0),
            "path" to r?.path,
        )
    }
}

/** Service d'avant-plan de type micro, avec notification et verrou processeur. */
class RecorderService : Service() {

    companion object {
        const val CHANNEL_ID = "andika_recording"
        const val NOTIFICATION_ID = 7002
        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"
        const val EXTRA_CHANNEL_NAME = "channelName"

        /** Délai maximal du verrou : 6 heures. */
        private const val WAKELOCK_TIMEOUT_MS = 6L * 60 * 60 * 1000

        fun start(context: Context, title: String, text: String, channelName: String) {
            val intent = Intent(context, RecorderService::class.java)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_TEXT, text)
                .putExtra(EXTRA_CHANNEL_NAME, channelName)
            if (Build.VERSION.SDK_INT >= 26) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, RecorderService::class.java))
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        val title = intent.getStringExtra(EXTRA_TITLE) ?: "Andika"
        val text = intent.getStringExtra(EXTRA_TEXT) ?: ""
        val channelName = intent.getStringExtra(EXTRA_CHANNEL_NAME) ?: "Enregistrement"
        ensureChannel(channelName)
        val notification = buildNotification(title, text)
        if (Build.VERSION.SDK_INT >= 30) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        acquireWakeLock()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    private fun ensureChannel(name: String) {
        if (Build.VERSION.SDK_INT < 26) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            val channel = NotificationChannel(CHANNEL_ID, name, NotificationManager.IMPORTANCE_LOW)
            channel.setShowBadge(false)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(title: String, text: String): Notification {
        val open = PendingIntent.getActivity(
            this,
            1,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder.setSmallIcon(R.drawable.ic_launcher_andika)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setUsesChronometer(true)
            .setWhen(System.currentTimeMillis())
            .build()
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "andika:recording").apply {
            setReferenceCounted(false)
            acquire(WAKELOCK_TIMEOUT_MS)
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Exception) {
        }
        wakeLock = null
    }
}
