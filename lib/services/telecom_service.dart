import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavedialer/logic/theme_controller.dart';

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
      final List<dynamic>? result = await _methodChannel.invokeMethod('getSimCards');
      if (result != null) {
        return result.map((e) => Map<String, String>.from(e as Map)).toList();
      }
      return [];
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
      
      final currentTheme = ThemeController.instance.currentTheme;
      if (currentTheme == 'pixel') {
        _showPixelSimSelector(context, sims, number);
        return;
      }

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

  static void _showPixelSimSelector(BuildContext context, List<Map<String, String>> sims, String number) {
    const kCardBg = Color(0xFF161D26);
    const kAvatarBg = Color(0xFF1E2632);
    const kBlueAccent = Color(0xFF8AB4F8);
    const kTextWhite = Color(0xFFFFFFFF);
    const kTextMuted = Color(0xFF8E9CAE);
    const kSeparator = Color(0xFF353E4A);

    showModalBottomSheet(
      context: context,
      backgroundColor: kCardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: kSeparator,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Select Calling SIM',
                style: TextStyle(
                  color: kTextWhite,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Choose a SIM card to call $number',
                style: const TextStyle(color: kTextMuted, fontSize: 13),
              ),
              const SizedBox(height: 18),
              ...sims.asMap().entries.map((entry) {
                final index = entry.key;
                final sim = entry.value;
                final label = sim['label'] ?? 'SIM ${index + 1}';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      makeCall(number, simId: sim['id']);
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: kAvatarBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: kBlueAccent.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.sim_card_rounded,
                              color: kBlueAccent,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  label,
                                  style: const TextStyle(
                                    color: kTextWhite,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Slot ${index + 1}',
                                  style: const TextStyle(
                                    color: kTextMuted,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 36,
                            height: 36,
                            decoration: const BoxDecoration(
                              color: kCardBg,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.call_rounded,
                              color: kBlueAccent,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      color: kTextMuted,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
