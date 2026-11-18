package org.chadracklonde.andika

import android.media.MediaPlayer
import android.media.PlaybackParams
import android.os.Build
import android.os.Handler
import android.os.Looper

/**
 * Lecteur du WAV de travail, pour réécouter l'enregistrement pendant la relecture.
 * Tous les appels se font sur le fil principal. L'état est envoyé à Dart toutes les
 * 200 ms pendant la lecture, et à chaque changement.
 */
class AudioPlayer(private val emit: (Map<String, Any?>) -> Unit) {
    private var player: MediaPlayer? = null
    private var completed = false
    private val handler = Handler(Looper.getMainLooper())
    private val ticker = object : Runnable {
        override fun run() {
            publish()
            if (player?.isPlaying == true) handler.postDelayed(this, 200)
        }
    }

    /** Charge un fichier et retourne sa durée en ms. */
    fun load(path: String): Int {
        release()
        val p = MediaPlayer()
        try {
            p.setDataSource(path)
            p.prepare()
        } catch (e: Exception) {
            p.release()
            throw e
        }
        p.setOnCompletionListener {
            completed = true
            handler.removeCallbacks(ticker)
            publish()
        }
        player = p
        completed = false
        publish()
        return p.duration
    }

    fun play() {
        val p = player ?: return
        if (completed) {
            p.seekTo(0)
            completed = false
        }
        p.start()
        handler.removeCallbacks(ticker)
        handler.post(ticker)
    }

    fun pause() {
        val p = player ?: return
        if (p.isPlaying) p.pause()
        handler.removeCallbacks(ticker)
        publish()
    }

    fun seek(positionMs: Int) {
        val p = player ?: return
        p.seekTo(positionMs.coerceIn(0, p.duration))
        completed = false
        publish()
    }

    fun setSpeed(speed: Float) {
        val p = player ?: return
        if (Build.VERSION.SDK_INT < 23) return
        try {
            val wasPlaying = p.isPlaying
            p.playbackParams = PlaybackParams().setSpeed(speed.coerceIn(0.5f, 2.0f))
            // Sur certains appareils, changer la vitesse relance la lecture.
            if (!wasPlaying && p.isPlaying) p.pause()
        } catch (_: Exception) {
        }
    }

    fun release() {
        handler.removeCallbacks(ticker)
        try {
            player?.release()
        } catch (_: Exception) {
        }
        player = null
        completed = false
    }

    private fun publish() {
        val p = player ?: return
        val position = try {
            if (completed) p.duration else p.currentPosition
        } catch (_: Exception) {
            0
        }
        emit(
            mapOf(
                "positionMs" to position,
                "durationMs" to p.duration,
                "playing" to (try { p.isPlaying } catch (_: Exception) { false }),
                "completed" to completed,
            ),
        )
    }
}
