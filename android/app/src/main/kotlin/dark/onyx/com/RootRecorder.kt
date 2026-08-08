package dark.onyx.com

import android.media.AudioFormat
import android.media.AudioRecord
import java.io.FileOutputStream
import java.io.RandomAccessFile

object RootRecorder {
    @Volatile
    private var isRecording = true

    @JvmStatic
    fun main(args: Array<String>) {
        if (args.isEmpty()) {
            println("Usage: RootRecorder <output_file_path>")
            return
        }
        val path = args[0]

        try {
            val sampleRate = 8000
            val channelConfig = AudioFormat.CHANNEL_IN_MONO
            val audioFormat = AudioFormat.ENCODING_PCM_16BIT
            val minBufSize = maxOf(
                AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat),
                8192
            )
            isRecording = true

            // Stop-signal listener thread
            Thread {
                try {
                    System.`in`.read()
                    isRecording = false
                } catch (_: Exception) {
                    isRecording = false
                }
            }.start()

            // 1. Primary Attempt: Single-stream VOICE_CALL (Source 4) - Hardware combined stream
            println("RootRecorder: Attempting hardware VOICE_CALL (Source 4)...")
            var voiceCallRecord: AudioRecord? = null
            try {
                val testRec = AudioRecord(4, sampleRate, channelConfig, audioFormat, minBufSize)
                if (testRec.state == AudioRecord.STATE_INITIALIZED) {
                    voiceCallRecord = testRec
                } else {
                    testRec.release()
                }
            } catch (e: Exception) {
                println("RootRecorder: VOICE_CALL init exception: ${e.message}")
            }

            val fos = FileOutputStream(path)
            writeWavHeader(fos, sampleRate, 1, 16)
            var totalBytes = 0

            if (voiceCallRecord != null) {
                println("RootRecorder: VOICE_CALL initialized successfully. Using combined 2-way hardware capture...")
                voiceCallRecord.startRecording()
                val buf = ByteArray(minBufSize)

                while (isRecording) {
                    val read = voiceCallRecord.read(buf, 0, buf.size)
                    if (read > 0) {
                        fos.write(buf, 0, read)
                        totalBytes += read
                    } else if (read < 0) {
                        println("RootRecorder: VOICE_CALL read error: $read")
                        break
                    }
                }
                voiceCallRecord.stop()
                voiceCallRecord.release()
            } else {
                // 2. Dual-stream fallback (Uplink + Downlink)
                println("RootRecorder: VOICE_CALL unavailable. Initializing dual-stream fallback...")

                val UPLINK_GAIN = 4.0f
                val DOWNLINK_GAIN = 3.0f

                val uplinkSources = intArrayOf(2, 1, 7) // VOICE_UPLINK, MIC, VOICE_COMMUNICATION
                val downlinkSources = intArrayOf(3, 4)  // VOICE_DOWNLINK, VOICE_CALL

                var uplinkRecorder: AudioRecord? = null
                for (src in uplinkSources) {
                    try {
                        val r = AudioRecord(src, sampleRate, channelConfig, audioFormat, minBufSize)
                        if (r.state == AudioRecord.STATE_INITIALIZED) {
                            uplinkRecorder = r
                            println("RootRecorder: Uplink source initialized: $src")
                            break
                        }
                        r.release()
                    } catch (_: Exception) {}
                }

                var downlinkRecorder: AudioRecord? = null
                for (src in downlinkSources) {
                    try {
                        val r = AudioRecord(src, sampleRate, channelConfig, audioFormat, minBufSize)
                        if (r.state == AudioRecord.STATE_INITIALIZED) {
                            downlinkRecorder = r
                            println("RootRecorder: Downlink source initialized: $src")
                            break
                        }
                        r.release()
                    } catch (_: Exception) {}
                }

                val uplinkOk = uplinkRecorder != null
                val downlinkOk = downlinkRecorder != null

                if (!uplinkOk && !downlinkOk) {
                    println("RootRecorder: FATAL ERROR: No audio source initialized.")
                    System.exit(1)
                }

                uplinkRecorder?.startRecording()
                downlinkRecorder?.startRecording()

                val uplinkBuf = ShortArray(minBufSize / 2)
                val downlinkBuf = ShortArray(minBufSize / 2)
                val mixedBuf = ByteArray(minBufSize)

                while (isRecording) {
                    val uplinkRead = uplinkRecorder?.read(uplinkBuf, 0, uplinkBuf.size) ?: 0
                    val downlinkRead = downlinkRecorder?.read(downlinkBuf, 0, downlinkBuf.size) ?: 0

                    val validUpRead = if (uplinkRead > 0) uplinkRead else 0
                    val validDownRead = if (downlinkRead > 0) downlinkRead else 0

                    val samplesToProcess = maxOf(validUpRead, validDownRead)
                    if (samplesToProcess == 0) continue

                    for (i in 0 until samplesToProcess) {
                        val up = if (validUpRead > i) uplinkBuf[i].toInt() else 0
                        val down = if (validDownRead > i) downlinkBuf[i].toInt() else 0
                        val boostedUp = (up * UPLINK_GAIN).toInt()
                        val boostedDown = (down * DOWNLINK_GAIN).toInt()
                        val mixed = (boostedUp + boostedDown).coerceIn(-32768, 32767)
                        mixedBuf[i * 2] = (mixed and 0xFF).toByte()
                        mixedBuf[i * 2 + 1] = ((mixed shr 8) and 0xFF).toByte()
                    }

                    val byteCount = samplesToProcess * 2
                    fos.write(mixedBuf, 0, byteCount)
                    totalBytes += byteCount
                }

                uplinkRecorder?.stop()
                uplinkRecorder?.release()
                downlinkRecorder?.stop()
                downlinkRecorder?.release()
            }

            println("RootRecorder: Stop signal received. Finalizing file...")
            fos.flush()
            fos.close()

            // Fix WAV header with actual sizes
            val raf = RandomAccessFile(path, "rw")
            raf.seek(4)
            raf.writeInt(Integer.reverseBytes(36 + totalBytes)) // ChunkSize
            raf.seek(40)
            raf.writeInt(Integer.reverseBytes(totalBytes))      // Subchunk2Size
            raf.close()

            // Fix permissions so user file managers can access it
            Runtime.getRuntime().exec(arrayOf("chmod", "666", path)).waitFor()
            try {
                Runtime.getRuntime().exec(arrayOf("am", "broadcast", "-a", "android.intent.action.MEDIA_SCANNER_SCAN_FILE", "-d", "file://$path"))
            } catch (_: Exception) {}

            println("RootRecorder: Recording saved successfully. Total bytes: $totalBytes")
            System.exit(0)

        } catch (e: Exception) {
            println("RootRecorder: FATAL ERROR: ${e.message}")
            e.printStackTrace()
            System.exit(1)
        }
    }

    private fun writeWavHeader(out: FileOutputStream, sampleRate: Int, channels: Int, bitsPerSample: Int) {
        val byteRate = sampleRate * channels * bitsPerSample / 8
        val blockAlign = channels * bitsPerSample / 8
        fun writeInt(v: Int) = out.write(byteArrayOf(
            (v and 0xFF).toByte(), ((v shr 8) and 0xFF).toByte(),
            ((v shr 16) and 0xFF).toByte(), ((v shr 24) and 0xFF).toByte()
        ))
        fun writeShort(v: Int) = out.write(byteArrayOf(
            (v and 0xFF).toByte(), ((v shr 8) and 0xFF).toByte()
        ))
        out.write("RIFF".toByteArray())
        writeInt(0)           // Placeholder: ChunkSize
        out.write("WAVE".toByteArray())
        out.write("fmt ".toByteArray())
        writeInt(16)          // Subchunk1Size
        writeShort(1)         // AudioFormat: PCM
        writeShort(channels)  // NumChannels
        writeInt(sampleRate)  // SampleRate
        writeInt(byteRate)    // ByteRate
        writeShort(blockAlign)// BlockAlign
        writeShort(bitsPerSample) // BitsPerSample
        out.write("data".toByteArray())
        writeInt(0)           // Placeholder: Subchunk2Size
    }
}
