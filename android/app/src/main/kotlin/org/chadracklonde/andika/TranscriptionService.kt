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
 * Service d'avant-plan (type dataSync) qui garde le processus en vie pendant une
 * transcription, avec une notification de progression. Il ne fait aucun calcul :
 * le travail reste dans l'isolate Dart. Un verrou partiel maintient le processeur
 * actif écran éteint ; il est relâché à l'arrêt, avec un délai maximal de sécurité.
 */
class TranscriptionService : Service() {

    companion object {
        const val CHANNEL_ID = "andika_transcription"
        const val NOTIFICATION_ID = 7001
        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"
        const val EXTRA_PROGRESS = "progress" // -1 = indéterminé, sinon 0..100
        const val EXTRA_CHANNEL_NAME = "channelName"
        const val ACTION_STOP = "org.chadracklonde.andika.STOP"

        /** Délai maximal du verrou : 6 heures. */
        private const val WAKELOCK_TIMEOUT_MS = 6L * 60 * 60 * 1000

        fun start(context: Context, title: String, text: String, progress: Int, channelName: String) {
            val intent = Intent(context, TranscriptionService::class.java)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_TEXT, text)
                .putExtra(EXTRA_PROGRESS, progress)
                .putExtra(EXTRA_CHANNEL_NAME, channelName)
            if (Build.VERSION.SDK_INT >= 26) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, TranscriptionService::class.java))
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) {
            // Relance par le système sans données : rien à afficher, on s'arrête.
            stopSelf()
            return START_NOT_STICKY
        }
        val title = intent.getStringExtra(EXTRA_TITLE) ?: "Andika"
        val text = intent.getStringExtra(EXTRA_TEXT) ?: ""
        val progress = intent.getIntExtra(EXTRA_PROGRESS, -1)
        val channelName = intent.getStringExtra(EXTRA_CHANNEL_NAME) ?: "Transcription"
        ensureChannel(channelName)
        val notification = buildNotification(title, text, progress)
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
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

    private fun buildNotification(title: String, text: String, progress: Int): Notification {
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder.setSmallIcon(R.drawable.ic_launcher_andika)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
        if (progress in 0..100) {
            builder.setProgress(100, progress, false)
        } else {
            builder.setProgress(0, 0, true)
        }
        return builder.build()
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "andika:transcription").apply {
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
