import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  // === Recording Engine Selection ===
  
  static Process? _rootRecordingProcess;
  static bool _isShizukuRecording = false;

  static Future<void> startRecording(String filePath) async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('start_mode') ?? 'none';

    if (mode == 'root') {
      await _startRootRecording(filePath);
    } else if (mode == 'shizuku') {
      await _startShizukuRecording(filePath);
    } else {
      debugPrint('TelecomService: Recording disabled in Basic Mode');
    }
  }

  static Future<void> stopRecording() async {
    await _stopRootRecording();
    await _stopShizukuRecording();
  }

  // === Root Recording Engine ===

  static Future<void> _startRootRecording(String filePath) async {
    if (_rootRecordingProcess != null) return;
    try {
      debugPrint('TelecomService: Starting root recording to $filePath');
      final classpathCmd = 'pm path dark.onyx.com | cut -d: -f2';
      final command = 'export CLASSPATH=\$($classpathCmd) && app_process / dark.onyx.com.RootRecorder "$filePath"';
      
      _rootRecordingProcess = await Process.start('su', ['-c', command]);
      
      _rootRecordingProcess!.stdout.transform(utf8.decoder).listen((data) => debugPrint('RootRecorder: ${data.trim()}'));
      _rootRecordingProcess!.stderr.transform(utf8.decoder).listen((data) => debugPrint('RootRecorder Error: ${data.trim()}'));
      
    } catch (e) {
      debugPrint('TelecomService: Failed to start root recording: $e');
      _rootRecordingProcess = null;
    }
  }

  static Future<void> _stopRootRecording() async {
    if (_rootRecordingProcess == null) return;
    try {
      debugPrint('TelecomService: Stopping root recording...');
      _rootRecordingProcess!.stdin.writeln('stop');
      await _rootRecordingProcess!.stdin.flush();
      _rootRecordingProcess = null;
    } catch (e) {
      _rootRecordingProcess?.kill();
      _rootRecordingProcess = null;
    }
  }

  // === Shizuku Recording Engine ===

  static Future<void> _startShizukuRecording(String filePath) async {
    if (_isShizukuRecording) return;
    try {
      debugPrint('TelecomService: Starting Shizuku recording to $filePath');
      await _methodChannel.invokeMethod('startShizukuRecording', {'filePath': filePath});
      _isShizukuRecording = true;
    } catch (e) {
      debugPrint('TelecomService: Failed to start Shizuku recording: $e');
    }
  }

  static Future<void> _stopShizukuRecording() async {
    try {
      debugPrint('TelecomService: Stopping Shizuku recording...');
      await _methodChannel.invokeMethod('stopShizukuRecording');
      _isShizukuRecording = false;
    } catch (e) {
      debugPrint('TelecomService: Failed to stop Shizuku recording: $e');
    }
  }
}
