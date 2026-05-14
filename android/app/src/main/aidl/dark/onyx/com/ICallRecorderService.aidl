package dark.onyx.com;

interface ICallRecorderService {
    void startRecording(String filePath);
    void stopRecording();
    boolean isRecording();
}
