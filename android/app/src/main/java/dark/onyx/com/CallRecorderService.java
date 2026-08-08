package dark.onyx.com;

import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import android.util.Log;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.File;

public class CallRecorderService extends ICallRecorderService.Stub {
    private static final String TAG = "OnyxShizukuRecorder";
    private boolean mIsRecording = false;
    private RecordingThread mRecordingThread;

    @Override
    public void startRecording(String filePath) {
        if (mIsRecording) return;
        mIsRecording = true;
        mRecordingThread = new RecordingThread(filePath);
        mRecordingThread.start();
        Log.d(TAG, "Recording started: " + filePath);
    }

    @Override
    public void stopRecording() {
        mIsRecording = false;
        if (mRecordingThread != null) {
            mRecordingThread.stopRecording();
            mRecordingThread = null;
        }
        Log.d(TAG, "Recording stopped");
    }

    @Override
    public boolean isRecording() {
        return mIsRecording;
    }

    private class RecordingThread extends Thread {
        private final String mFilePath;
        private AudioRecord mAudioRecord;
        private volatile boolean mRunning = true;
        private int mCurrentSourceIndex = 0;

        private final int[] sources = {
            MediaRecorder.AudioSource.VOICE_CALL,          // 4
            MediaRecorder.AudioSource.VOICE_COMMUNICATION, // 7
            MediaRecorder.AudioSource.VOICE_RECOGNITION,   // 6
            MediaRecorder.AudioSource.MIC,                 // 1
            MediaRecorder.AudioSource.VOICE_DOWNLINK,      // 3
            MediaRecorder.AudioSource.VOICE_UPLINK         // 2
        };

        public RecordingThread(String filePath) {
            this.mFilePath = filePath;
        }

        public void stopRecording() {
            mRunning = false;
        }

        @Override
        public void run() {
            int sampleRate = 8000; // 8kHz Telephony Standard
            int channelConfig = AudioFormat.CHANNEL_IN_MONO;
            int audioFormat = AudioFormat.ENCODING_PCM_16BIT;
            int bufferSize = Math.max(AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat), 8192);

            Log.d(TAG, "RecordingThread started for: " + mFilePath);
            try (FileOutputStream os = new FileOutputStream(mFilePath)) {
                Log.d(TAG, "File opened successfully");
                writeWavHeader(os, channelConfig, sampleRate, audioFormat);
                
                long totalAudioLen = 0;
                int sourceRetries = 0;
                byte[] data = new byte[bufferSize];

                while (mRunning) {
                    if (mAudioRecord == null || mAudioRecord.getState() != AudioRecord.STATE_INITIALIZED) {
                        mAudioRecord = initializeAudioRecord(sampleRate, channelConfig, audioFormat, bufferSize);
                        if (mAudioRecord == null) {
                            Log.e(TAG, "Failed to initialize AudioRecord. Retrying in 1s...");
                            try { Thread.sleep(1000); } catch (InterruptedException e) { break; }
                            continue;
                        }
                        try {
                            mAudioRecord.startRecording();
                            Log.d(TAG, "AudioRecord started. Source: " + sources[mCurrentSourceIndex] + ", State: " + mAudioRecord.getRecordingState());
                        } catch (Exception e) {
                            Log.e(TAG, "startRecording failed: " + e.getMessage());
                            mAudioRecord.release();
                            mAudioRecord = null;
                            mCurrentSourceIndex = (mCurrentSourceIndex + 1) % sources.length;
                            continue;
                        }
                    }

                    int read = mAudioRecord.read(data, 0, bufferSize);
                    if (read > 0) {
                        os.write(data, 0, read);
                        totalAudioLen += read;
                        sourceRetries = 0; // Reset retries on successful read
                    } else if (read < 0) {
                        sourceRetries++;
                        Log.w(TAG, "AudioRecord read error: " + read + " on source " + sources[mCurrentSourceIndex] + " (retry " + sourceRetries + "/5)");
                        
                        if (mAudioRecord != null) {
                            try { mAudioRecord.stop(); } catch (Exception ignored) {}
                            mAudioRecord.release();
                            mAudioRecord = null;
                        }

                        if (sourceRetries >= 5) {
                            sourceRetries = 0;
                            mCurrentSourceIndex = (mCurrentSourceIndex + 1) % sources.length;
                            Log.e(TAG, "Max retries reached. Switching to next source: " + sources[mCurrentSourceIndex]);
                        }
                        
                        try { Thread.sleep(200); } catch (InterruptedException e) { break; }
                    }
                }

                Log.d(TAG, "Loop finished. Total bytes: " + totalAudioLen);
                if (mAudioRecord != null) {
                    try { mAudioRecord.stop(); } catch (Exception ignored) {}
                    mAudioRecord.release();
                }
                
                // Update WAV header with final length
                updateWavHeader(mFilePath, totalAudioLen);
                Log.d(TAG, "WAV header updated");

                // Fix file permissions and trigger media scanner
                try {
                    Runtime.getRuntime().exec(new String[]{"chmod", "666", mFilePath}).waitFor();
                    Runtime.getRuntime().exec(new String[]{"am", "broadcast", "-a", "android.intent.action.MEDIA_SCANNER_SCAN_FILE", "-d", "file://" + mFilePath});
                } catch (Exception e) {
                    Log.e(TAG, "Permission / MediaScanner error: " + e.getMessage());
                }

            } catch (IOException e) {
                Log.e(TAG, "IO Error during recording: " + e.getMessage());
            } finally {
                mIsRecording = false;
                Log.d(TAG, "RecordingThread finished");
            }
        }

        private AudioRecord initializeAudioRecord(int sampleRate, int channelConfig, int audioFormat, int bufferSize) {
            for (int i = 0; i < sources.length; i++) {
                int index = (mCurrentSourceIndex + i) % sources.length;
                int source = sources[index];
                try {
                    AudioRecord record = new AudioRecord(source, sampleRate, channelConfig, audioFormat, bufferSize);
                    if (record.getState() == AudioRecord.STATE_INITIALIZED) {
                        mCurrentSourceIndex = index;
                        Log.d(TAG, "Successfully initialized audio source: " + source);
                        return record;
                    }
                    record.release();
                } catch (Exception e) {
                    Log.e(TAG, "Failed to init source " + source + ": " + e.getMessage());
                }
            }
            return null;
        }

        private void writeWavHeader(FileOutputStream out, int channelConfig, int sampleRate, int audioFormat) throws IOException {
            byte[] header = new byte[44];
            int channels = (channelConfig == AudioFormat.CHANNEL_IN_MONO) ? 1 : 2;
            long byteRate = sampleRate * channels * 2;

            header[0] = 'R'; header[1] = 'I'; header[2] = 'F'; header[3] = 'F';
            header[4] = 0; header[5] = 0; header[6] = 0; header[7] = 0; // Size (fill later)
            header[8] = 'W'; header[9] = 'A'; header[10] = 'V'; header[11] = 'E';
            header[12] = 'f'; header[13] = 'm'; header[14] = 't'; header[15] = ' ';
            header[16] = 16; header[17] = 0; header[18] = 0; header[19] = 0; // Subchunk1Size
            header[20] = 1; header[21] = 0; // AudioFormat (PCM)
            header[22] = (byte) channels; header[23] = 0;
            header[24] = (byte) (sampleRate & 0xff);
            header[25] = (byte) ((sampleRate >> 8) & 0xff);
            header[26] = (byte) ((sampleRate >> 16) & 0xff);
            header[27] = (byte) ((sampleRate >> 24) & 0xff);
            header[28] = (byte) (byteRate & 0xff);
            header[29] = (byte) ((byteRate >> 8) & 0xff);
            header[30] = (byte) ((byteRate >> 16) & 0xff);
            header[31] = (byte) ((byteRate >> 24) & 0xff);
            header[32] = (byte) (channels * 2); header[33] = 0; // BlockAlign
            header[34] = 16; header[35] = 0; // BitsPerSample
            header[36] = 'd'; header[37] = 'a'; header[38] = 't'; header[39] = 'a';
            header[40] = 0; header[41] = 0; header[42] = 0; header[43] = 0; // Data size (fill later)

            out.write(header, 0, 44);
        }

        private void updateWavHeader(String filePath, long totalAudioLen) {
            try (java.io.RandomAccessFile raf = new java.io.RandomAccessFile(filePath, "rw")) {
                long totalDataLen = totalAudioLen + 36;
                raf.seek(4);
                raf.write((int) (totalDataLen & 0xff));
                raf.write((int) ((totalDataLen >> 8) & 0xff));
                raf.write((int) ((totalDataLen >> 16) & 0xff));
                raf.write((int) ((totalDataLen >> 24) & 0xff));
                raf.seek(40);
                raf.write((int) (totalAudioLen & 0xff));
                raf.write((int) ((totalAudioLen >> 8) & 0xff));
                raf.write((int) ((totalAudioLen >> 16) & 0xff));
                raf.write((int) ((totalAudioLen >> 24) & 0xff));
            } catch (IOException e) {
                Log.e(TAG, "Failed to update WAV header: " + e.getMessage());
            }
        }
    }
}
