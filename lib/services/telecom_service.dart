import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class TelecomService {
  static const MethodChannel _methodChannel = MethodChannel('dark.onyx.com/telecom_commands');
  static const EventChannel _eventChannel = EventChannel('dark.onyx.com/telecom_events');

  static Stream<Map<String, dynamic>> get callStateStream {
    return _eventChannel.receiveBroadcastStream().map((event) => Map<String, dynamic>.from(event));
  }

  static Future<void> requestDefaultDialer() async {
    await _methodChannel.invokeMethod('requestDefaultDialer');
  }

  static Future<void> makeCall(String number) async {
    await _methodChannel.invokeMethod('makeCall', {'number': number});
  }

  static Future<void> answerCall() async {
    await _methodChannel.invokeMethod('answerCall');
  }

  static Future<void> endCall() async {
    await _methodChannel.invokeMethod('endCall');
  }

  static Future<void> playDtmf(String digit) async {
    await _methodChannel.invokeMethod('playDtmf', {'digit': digit});
  }

  static Future<void> playLocalDtmf(String digit) async {
    await _methodChannel.invokeMethod('playLocalDtmf', {'digit': digit});
  }

  static Future<void> setSpeaker(bool enabled) async {
    await _methodChannel.invokeMethod('setSpeaker', {'enabled': enabled});
  }

  static Future<void> setMuted(bool enabled) async {
    await _methodChannel.invokeMethod('setMuted', {'enabled': enabled});
  }

  static Future<void> setHold(bool enabled) async {
    await _methodChannel.invokeMethod('setHold', {'enabled': enabled});
  }

  // === Root Recording Engine ===
  
  static Process? _recordingProcess;
  static bool get isRecording => _recordingProcess != null;

  static Future<void> startRecording(String filePath) async {
    if (isRecording) return;
    try {
      debugPrint('TelecomService: Starting root recording to $filePath');
      final classpathCmd = 'pm path dark.onyx.com | cut -d: -f2';
      final command = 'export CLASSPATH=\$($classpathCmd) && app_process / dark.onyx.com.RootRecorder "$filePath"';
      
      _recordingProcess = await Process.start('su', ['-c', command]);
      
      _recordingProcess!.stdout.transform(utf8.decoder).listen((data) {
        debugPrint('RootRecorder: ${data.trim()}');
      });
      _recordingProcess!.stderr.transform(utf8.decoder).listen((data) {
        debugPrint('RootRecorder Error: ${data.trim()}');
      });
      
    } catch (e) {
      debugPrint('TelecomService: Failed to start recording: $e');
      _recordingProcess = null;
    }
  }

  static void stopRecording() {
    if (!isRecording) return;
    try {
      debugPrint('TelecomService: Sending stop signal to recording process...');
      _recordingProcess!.stdin.writeln('stop');
      _recordingProcess!.stdin.flush();
      _recordingProcess = null;
    } catch (e) {
      debugPrint('TelecomService: Failed to stop recording cleanly: $e');
      _recordingProcess?.kill();
      _recordingProcess = null;
    }
  }
}
