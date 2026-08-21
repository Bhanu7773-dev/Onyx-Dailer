import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TelecomService {
  static const MethodChannel _methodChannel = MethodChannel('dark.onyx.com/telecom_commands');
  static const EventChannel _eventChannel = EventChannel('dark.onyx.com/telecom_events');

  static final Stream<Map<String, dynamic>> callStateStream = 
      _eventChannel.receiveBroadcastStream().map((event) => Map<String, dynamic>.from(event));

  static Future<void> requestDefaultDialer() async {
    await _methodChannel.invokeMethod('requestDefaultDialer');
  }

  static Future<List<Map<String, String>>> getSimCards() async {
    try {
      final List<dynamic> result = await _methodChannel.invokeMethod('getSimCards');
      return result.map((e) => Map<String, String>.from(e as Map)).toList();
    } catch (e) {
      debugPrint('TelecomService: Failed to get SIM cards: $e');
      return [];
    }
  }

  static Future<void> makeCall(String number, {String? simId}) async {
    String? selectedSim = simId;
    if (selectedSim == null) {
      final prefs = await SharedPreferences.getInstance();
      selectedSim = prefs.getString('default_sim');
    }
    
    await _methodChannel.invokeMethod('makeCall', {
      'number': number,
      if (selectedSim != null && selectedSim != 'ask') 'simId': selectedSim,
    });
  }

  static Future<void> handleOutgoingCall(BuildContext context, String number) async {
    final prefs = await SharedPreferences.getInstance();
    final defaultSim = prefs.getString('default_sim') ?? 'ask';
    final sims = await getSimCards();

    if (defaultSim == 'ask' && sims.length > 1) {
      if (!context.mounted) return;
      showCupertinoModalPopup(
        context: context,
        builder: (BuildContext context) => CupertinoActionSheet(
          title: const Text('Select Calling SIM'),
          message: Text('Choose a SIM card to call $number.'),
          actions: sims.map((sim) => CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              makeCall(number, simId: sim['id']);
            },
            child: Text(sim['label'] ?? 'Unknown SIM'),
          )).toList(),
          cancelButton: CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ),
      );
    } else {
      makeCall(number);
    }
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

  static Future<bool> mergeCall() async {
    try {
      return await _methodChannel.invokeMethod<bool>('mergeCall') ?? false;
    } catch (e) {
      debugPrint('TelecomService: mergeCall failed: $e');
      return false;
    }
  }

  static Future<bool> swapCall() async {
    try {
      return await _methodChannel.invokeMethod<bool>('swapCall') ?? false;
    } catch (e) {
      debugPrint('TelecomService: swapCall failed: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>> getCallInfo() async {
    try {
      final res = await _methodChannel.invokeMethod('getCallInfo');
      if (res != null) {
        return Map<String, dynamic>.from(res as Map);
      }
    } catch (e) {
      debugPrint('TelecomService: getCallInfo failed: $e');
    }
    return {'count': 1, 'isConference': false, 'isHolding': false};
  }

  static Future<int> getCallCount() async {
    try {
      return await _methodChannel.invokeMethod<int>('getCallCount') ?? 0;
    } catch (e) {
      debugPrint('TelecomService: getCallCount failed: $e');
      return 0;
    }
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
      // For split APKs (--split-per-abi), pm path returns multiple lines.
      // We must join ALL APK paths with ':' for CLASSPATH so app_process finds our class.
      final command = 'export CLASSPATH=\$(pm path dark.onyx.com | sed "s/package://" | tr "\\n" ":") && app_process / dark.onyx.com.RootRecorder "$filePath"';
      
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
      final started = await _methodChannel.invokeMethod<bool>('startShizukuRecording', {'filePath': filePath}) ?? false;
      _isShizukuRecording = started;
      
      if (!started) {
        debugPrint('TelecomService: Service not ready immediately; retrying in 200ms...');
        await Future.delayed(const Duration(milliseconds: 200));
        if (!_isShizukuRecording) {
          final retryStarted = await _methodChannel.invokeMethod<bool>('startShizukuRecording', {'filePath': filePath}) ?? false;
          _isShizukuRecording = retryStarted;
          if (!retryStarted) {
            debugPrint('TelecomService: Retry also failed after 200ms');
          }
        }
      }
    } catch (e) {
      debugPrint('TelecomService: Failed to start Shizuku recording: $e');
      _isShizukuRecording = false;
    }
  }

  static Future<void> prepareShizukuService() async {
    try {
      debugPrint('TelecomService: Prewarm Shizuku service');
      await _methodChannel.invokeMethod<bool>('prepareShizukuService');
    } catch (e) {
      debugPrint('TelecomService: Error prewarm Shizuku: $e');
    }
  }

  static Future<void> _stopShizukuRecording() async {
    try {
      debugPrint('TelecomService: Stopping Shizuku recording...');
      await _methodChannel.invokeMethod<bool>('stopShizukuRecording');
    } catch (e) {
      debugPrint('TelecomService: Failed to stop Shizuku recording: $e');
    } finally {
      _isShizukuRecording = false;
    }
  }

  static Future<Map<String, dynamic>> handleSecretCode(String code) async {
    try {
      final res = await _methodChannel.invokeMethod('handleSecretCode', {'code': code});
      if (res != null) {
        return Map<String, dynamic>.from(res as Map);
      }
    } catch (e) {
      debugPrint('TelecomService: handleSecretCode failed: $e');
    }
    return {'handled': false};
  }
}
