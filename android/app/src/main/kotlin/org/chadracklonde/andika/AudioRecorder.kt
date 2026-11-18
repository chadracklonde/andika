package org.chadracklonde.andika

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.StatFs
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

class RecorderException(val code: String, message: String) : Exception(message)

/**
 * Enregistreur : micro 16 kHz mono PCM 16 bits écrit directement dans un WAV avec
 * l'en-tête de 44 octets d'Andika (même format que l'audio importé, donc aucune
 * conversion avant la transcription). L'en-tête est remis à jour toutes les 5 secondes :
 * après un arrêt brutal, au plus 5 secondes sont perdues et Dart répare le reste.
 */
class AudioRecorder(
    private val outFile: File,
    /** (état, durée en ms, niveau 0..1, erreur). État : recording, paused, stopped. */
    private val onUpdate: (String, Long, Double, String?) -> Unit,
) {
    companion object {
        const val SAMPLE_RATE = 16000
        const val HEADER_SIZE = 44
        const val MIN_FREE_BYTES = 50L * 1024 * 1024
        private const val HEADER_REFRESH_NS = 5_000_000_000L
        private const val SPACE_CHECK_NS = 10_000_000_000L

        fun header(dataBytes: Long): ByteArray {
            val b = ByteBuffer.allocate(HEADER_SIZE).order(ByteOrder.LITTLE_ENDIAN)
            b.put("RIFF".toByteArray(Charsets.US_ASCII))
            b.putInt((36 + dataBytes).toInt())
            b.put("WAVE".toByteArray(Charsets.US_ASCII))
            b.put("fmt ".toByteArray(Charsets.US_ASCII))
            b.putInt(16)
            b.putShort(1)
            b.putShort(1)
            b.putInt(SAMPLE_RATE)
            b.putInt(SAMPLE_RATE * 2)
            b.putShort(2)
            b.putShort(16)
            b.put("data".toByteArray(Charsets.US_ASCII))
            b.putInt(dataBytes.toInt())
            return b.array()
        }
    }

    @Volatile private var running = false
    @Volatile private var paused = false
    @Volatile private var samples = 0L
    @Volatile private var lastLevel = 0.0
    private var thread: Thread? = null

    val isRunning: Boolean get() = running
    val isPaused: Boolean get() = paused
    val elapsedMs: Long get() = samples * 1000L / SAMPLE_RATE
    val level: Double get() = lastLevel
    val path: String get() = outFile.absolutePath

    /** Démarre l'enregistrement. Lève [RecorderException] (permission, no_mic, busy, no_space). */
    fun start() {
        outFile.parentFile?.mkdirs()
        val free = StatFs((outFile.parentFile ?: outFile).absolutePath).availableBytes
        if (free < MIN_FREE_BYTES) throw RecorderException("no_space", "Espace de stockage insuffisant")
        val minBuf = AudioRecord.getMinBufferSize(
            SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
        )
        if (minBuf <= 0) throw RecorderException("no_mic", "Micro indisponible")
        val bufSize = maxOf(minBuf * 2, SAMPLE_RATE * 2)
        val rec: AudioRecord = try {
            AudioRecord(
                MediaRecorder.AudioSource.MIC, SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, bufSize,
            )
        } catch (e: SecurityException) {
            throw RecorderException("permission", "Autorisation du micro refusée")
        } catch (e: Exception) {
            throw RecorderException("no_mic", e.message ?: "Micro indisponible")
        }
        if (rec.state != AudioRecord.STATE_INITIALIZED) {
            rec.release()
            throw RecorderException("no_mic", "Micro indisponible")
        }
        val file: RandomAccessFile
        try {
            file = RandomAccessFile(outFile, "rw")
            file.setLength(0)
            file.write(header(0))
        } catch (e: IOException) {
            rec.release()
            throw RecorderException("no_space", e.message ?: "Écriture impossible")
        }
        try {
            rec.startRecording()
        } catch (e: IllegalStateException) {
            rec.release()
            file.close()
            throw RecorderException("busy", "Micro utilisé par une autre application")
        }
        if (rec.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
            rec.release()
            file.close()
            throw RecorderException("busy", "Micro utilisé par une autre application")
        }
        samples = 0
        paused = false
        running = true
        thread = Thread({ loop(rec, file) }, "andika-recorder").also { it.start() }
    }

    fun pause() {
        if (running) paused = true
    }

    fun resume() {
        if (running) paused = false
    }

    /** Arrête et attend la fin de l'écriture. Retourne la durée enregistrée. */
    fun stop(): Long {
        running = false
        try {
            thread?.join(3000)
        } catch (_: InterruptedException) {
        }
        return elapsedMs
    }

    private fun updateHeader(file: RandomAccessFile) {
        val dataBytes = samples * 2
        val pos = file.filePointer
        val b = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN)
        file.seek(4)
        file.write(b.putInt((36 + dataBytes).toInt()).array())
        b.clear()
        file.seek(40)
        file.write(b.putInt(dataBytes.toInt()).array())
        file.seek(pos)
    }

    private fun loop(rec: AudioRecord, file: RandomAccessFile) {
        val buf = ByteArray(SAMPLE_RATE / 5 * 2) // 200 ms
        var error: String? = null
        var lastHeader = System.nanoTime()
        var lastSpace = lastHeader
        try {
            while (running) {
                val n = rec.read(buf, 0, buf.size)
                if (n < 0) {
                    error = "read_error"
                    break
                }
                if (n == 0) continue
                var peak = 0
                var i = 0
                while (i + 1 < n) {
                    val v = (buf[i].toInt() and 0xFF) or (buf[i + 1].toInt() shl 8)
                    val a = if (v < 0) -v else v
                    if (a > peak) peak = a
                    i += 2
                }
                lastLevel = minOf(1.0, peak / 32768.0)
                if (!paused) {
                    file.write(buf, 0, n)
                    samples += n / 2
                }
                onUpdate(if (paused) "paused" else "recording", elapsedMs, lastLevel, null)
                val now = System.nanoTime()
                if (now - lastHeader > HEADER_REFRESH_NS) {
                    updateHeader(file)
                    lastHeader = now
                }
                if (now - lastSpace > SPACE_CHECK_NS) {
                    lastSpace = now
                    val free = StatFs((outFile.parentFile ?: outFile).absolutePath).availableBytes
                    if (free < MIN_FREE_BYTES) {
                        error = "no_space"
                        break
                    }
                }
            }
        } catch (e: IOException) {
            error = "no_space"
        } finally {
            try {
                updateHeader(file)
                file.close()
            } catch (_: Exception) {
            }
            try {
                rec.stop()
            } catch (_: Exception) {
            }
            rec.release()
            running = false
            onUpdate("stopped", elapsedMs, 0.0, error)
        }
    }
}
