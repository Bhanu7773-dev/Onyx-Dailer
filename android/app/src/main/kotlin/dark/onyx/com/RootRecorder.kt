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

            // Gain factors — uplink (mic) is typically very quiet vs downlink
            val UPLINK_GAIN   = 4.0f  // Your mic (reduced from 8x)
            val DOWNLINK_GAIN = 3.0f  // Remote party (boosted from 1.5x)

            println("RootRecorder: Initializing dual-stream capture (mic + downlink)...")

            // MIC = 1 (raw mic, works on Realme/OPPO), VOICE_DOWNLINK = 3 (remote party)
            val uplinkRecorder = AudioRecord(1, sampleRate, channelConfig, audioFormat, minBufSize)
            val downlinkRecorder = AudioRecord(3, sampleRate, channelConfig, audioFormat, minBufSize)

            val uplinkOk = uplinkRecorder.state == AudioRecord.STATE_INITIALIZED
            val downlinkOk = downlinkRecorder.state == AudioRecord.STATE_INITIALIZED

            println("RootRecorder: MIC init: $uplinkOk, Downlink init: $downlinkOk")

            if (!uplinkOk && !downlinkOk) {
                println("RootRecorder: FATAL ERROR: Neither audio source could be initialized.")
                System.exit(1)
            }

            if (uplinkOk) uplinkRecorder.startRecording()
            if (downlinkOk) downlinkRecorder.startRecording()

            println("RootRecorder: Recording started. Saving to: $path")

            val fos = FileOutputStream(path)
            // Write placeholder WAV header (44 bytes)
            writeWavHeader(fos, sampleRate, 1, 16)

            val uplinkBuf = ShortArray(minBufSize / 2)
            val downlinkBuf = ShortArray(minBufSize / 2)
            val mixedBuf = ByteArray(minBufSize)
            var totalBytes = 0

            // Stop-signal listener thread
            Thread {
                try {
                    System.`in`.read()
                    isRecording = false
                } catch (e: Exception) {
                    isRecording = false
                }
            }.start()

            // Main record loop
            while (isRecording) {
                val uplinkRead = if (uplinkOk) uplinkRecorder.read(uplinkBuf, 0, uplinkBuf.size) else 0
                val downlinkRead = if (downlinkOk) downlinkRecorder.read(downlinkBuf, 0, downlinkBuf.size) else 0

                val samplesToProcess = maxOf(uplinkRead.coerceAtLeast(0), downlinkRead.coerceAtLeast(0))
                if (samplesToProcess == 0) continue

                for (i in 0 until samplesToProcess) {
                    val up = if (uplinkRead > i) uplinkBuf[i].toInt() else 0
                    val down = if (downlinkRead > i) downlinkBuf[i].toInt() else 0
                    // Apply gain to each stream, then sum with clipping
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

            println("RootRecorder: Stop signal received. Finalizing file...")
            if (uplinkOk) { uplinkRecorder.stop(); uplinkRecorder.release() }
            if (downlinkOk) { downlinkRecorder.stop(); downlinkRecorder.release() }
            fos.flush()
            fos.close()

            // Fix WAV header with actual sizes
            val raf = RandomAccessFile(path, "rw")
            raf.seek(4)
            raf.writeInt(Integer.reverseBytes(36 + totalBytes)) // ChunkSize
            raf.seek(40)
            raf.writeInt(Integer.reverseBytes(totalBytes))      // Subchunk2Size
            raf.close()

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
