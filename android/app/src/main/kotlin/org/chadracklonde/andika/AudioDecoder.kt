package org.chadracklonde.andika

import android.content.Context
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Erreur de décodage avec un code lisible par Dart (voir PlatformBridge). */
class DecodeException(val code: String, message: String) : Exception(message)

class DecodeResult(val durationMs: Long, val sampleCount: Long)

/**
 * Écrit un fichier WAV PCM 16 bits mono 16 kHz. L'en-tête de 44 octets est réservé
 * au début puis complété à la fermeture : Dart s'appuie sur cette taille fixe.
 */
class WavWriter(private val file: File) {
    private val out = BufferedOutputStream(FileOutputStream(file), 1 shl 16)
    private val buffer = ByteArray(1 shl 15)
    private var used = 0
    var sampleCount = 0L
        private set

    init {
        out.write(ByteArray(HEADER_SIZE))
    }

    fun write(sample: Short) {
        if (used + 2 > buffer.size) flushBuffer()
        buffer[used++] = (sample.toInt() and 0xFF).toByte()
        buffer[used++] = ((sample.toInt() shr 8) and 0xFF).toByte()
        sampleCount++
    }

    private fun flushBuffer() {
        out.write(buffer, 0, used)
        used = 0
    }

    /** Termine le fichier et écrit l'en-tête. */
    fun close() {
        flushBuffer()
        out.flush()
        out.close()
        RandomAccessFile(file, "rw").use { raf ->
            val dataBytes = sampleCount * 2
            val header = ByteBuffer.allocate(HEADER_SIZE).order(ByteOrder.LITTLE_ENDIAN)
            header.put("RIFF".toByteArray(Charsets.US_ASCII))
            header.putInt((36 + dataBytes).toInt())
            header.put("WAVE".toByteArray(Charsets.US_ASCII))
            header.put("fmt ".toByteArray(Charsets.US_ASCII))
            header.putInt(16)            // taille du bloc fmt
            header.putShort(1)           // PCM
            header.putShort(1)           // mono
            header.putInt(SAMPLE_RATE)
            header.putInt(SAMPLE_RATE * 2)
            header.putShort(2)           // alignement
            header.putShort(16)          // bits par échantillon
            header.put("data".toByteArray(Charsets.US_ASCII))
            header.putInt(dataBytes.toInt())
            raf.seek(0)
            raf.write(header.array())
        }
    }

    /** Ferme sans écrire d'en-tête (cas d'erreur : le fichier sera supprimé). */
    fun abort() {
        try {
            out.close()
        } catch (_: IOException) {
        }
    }

    companion object {
        const val HEADER_SIZE = 44
        const val SAMPLE_RATE = 16000
    }
}

/**
 * Rééchantillonnage « par aire » (moyenne pondérée) d'un signal mono vers 16 kHz.
 * Fonctionne pour tout rapport de fréquences ; le filtrage par moyenne limite le
 * repliement de spectre lors d'une réduction (44,1 ou 48 kHz vers 16 kHz).
 */
class AreaResampler(inputRate: Int, private val writer: WavWriter) {
    private val ratio = inputRate.toDouble() / WavWriter.SAMPLE_RATE
    private var phase = 0.0
    private var acc = 0.0

    /** [x] est un échantillon entre -1 et 1. */
    fun push(x: Float) {
        var left = 1.0
        while (left > 1e-9) {
            val need = ratio - phase
            if (left >= need) {
                acc += x * need
                emit(acc / ratio)
                acc = 0.0
                phase = 0.0
                left -= need
            } else {
                acc += x * left
                phase += left
                left = 0.0
            }
        }
    }

    /** Écrit le dernier échantillon partiel, s'il y en a un. */
    fun finish() {
        if (phase > 1e-6) {
            emit(acc / phase)
            acc = 0.0
            phase = 0.0
        }
    }

    private fun emit(value: Double) {
        var v = Math.round(value * 32767.0)
        if (v > 32767L) v = 32767L
        if (v < -32768L) v = -32768L
        writer.write(v.toShort())
    }
}

/** Décode un fichier audio ou vidéo en WAV 16 kHz mono (MediaExtractor + MediaCodec). */
class AudioDecoder(private val context: Context) {
    @Volatile
    var cancelled = false

    fun decode(uri: Uri, outFile: File, onProgress: (Int) -> Unit): DecodeResult {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        var writer: WavWriter? = null
        var finished = false
        try {
            try {
                extractor.setDataSource(context, uri, null)
            } catch (e: Exception) {
                throw DecodeException("read_error", "Lecture impossible : ${e.message}")
            }

            var track = -1
            var format: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val f = extractor.getTrackFormat(i)
                val m = f.getString(MediaFormat.KEY_MIME) ?: continue
                if (m.startsWith("audio/")) {
                    track = i
                    format = f
                    break
                }
            }
            if (track < 0 || format == null) {
                throw DecodeException("no_audio", "Aucune piste audio dans ce fichier")
            }
            extractor.selectTrack(track)
            val mime = format.getString(MediaFormat.KEY_MIME)!!
            val durationUs =
                if (format.containsKey(MediaFormat.KEY_DURATION)) format.getLong(MediaFormat.KEY_DURATION) else 0L

            val dec: MediaCodec = try {
                val c = MediaCodec.createDecoderByType(mime)
                codec = c
                c.configure(format, null, null, 0)
                c.start()
                c
            } catch (e: Exception) {
                throw DecodeException("unsupported", "Format audio non pris en charge ($mime)")
            }

            val wav = WavWriter(outFile)
            writer = wav
            var sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var pcmFloat = false
            var resampler = AreaResampler(sampleRate, wav)

            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            var lastPercent = -1

            while (!outputDone) {
                if (cancelled) throw DecodeException("cancelled", "Annulé")

                if (!inputDone) {
                    val inIndex = dec.dequeueInputBuffer(10_000)
                    if (inIndex >= 0) {
                        val inBuf = dec.getInputBuffer(inIndex)!!
                        val size = extractor.readSampleData(inBuf, 0)
                        if (size < 0) {
                            dec.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            val timeUs = extractor.sampleTime
                            dec.queueInputBuffer(inIndex, 0, size, timeUs, 0)
                            extractor.advance()
                            if (durationUs > 0) {
                                val percent = (timeUs * 100 / durationUs).toInt().coerceIn(0, 99)
                                if (percent != lastPercent) {
                                    lastPercent = percent
                                    onProgress(percent)
                                }
                            }
                        }
                    }
                }

                val outIndex = dec.dequeueOutputBuffer(info, 10_000)
                if (outIndex >= 0) {
                    val outBuf = dec.getOutputBuffer(outIndex)
                    if (outBuf != null && info.size > 0) {
                        outBuf.position(info.offset)
                        outBuf.limit(info.offset + info.size)
                        outBuf.order(ByteOrder.nativeOrder())
                        if (pcmFloat) {
                            val fb = outBuf.asFloatBuffer()
                            while (fb.remaining() >= channels) {
                                var sum = 0f
                                for (c in 0 until channels) sum += fb.get()
                                resampler.push(sum / channels)
                            }
                        } else {
                            val sb = outBuf.asShortBuffer()
                            while (sb.remaining() >= channels) {
                                var sum = 0f
                                for (c in 0 until channels) sum += sb.get() / 32768f
                                resampler.push(sum / channels)
                            }
                        }
                    }
                    dec.releaseOutputBuffer(outIndex, false)
                    if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) outputDone = true
                } else if (outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val f = dec.outputFormat
                    val newRate = f.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    channels = f.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    pcmFloat = f.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                        f.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT
                    if (newRate != sampleRate) {
                        resampler.finish()
                        sampleRate = newRate
                        resampler = AreaResampler(sampleRate, wav)
                    }
                }
            }
            resampler.finish()
            wav.close()
            writer = null
            finished = true
            onProgress(100)
            return DecodeResult(wav.sampleCount * 1000L / WavWriter.SAMPLE_RATE, wav.sampleCount)
        } catch (e: DecodeException) {
            throw e
        } catch (e: Exception) {
            throw DecodeException("decode_error", "Erreur de décodage : ${e.message}")
        } finally {
            try {
                codec?.stop()
            } catch (_: Exception) {
            }
            try {
                codec?.release()
            } catch (_: Exception) {
            }
            extractor.release()
            writer?.abort()
            if (!finished) outFile.delete()
        }
    }
}
