import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavedialer/services/telecom_service.dart';

const _bg = Color(0xFF000000);
const _iosSecondary = Color(0xFF8E8E93);
const _buttonBg = Color(0x33FFFFFF);
const _buttonActiveBg = Color(0xFFFFFFFF);
const _iosRed = Color(0xFFFF3B30);
const _iosGreen = Color(0xFF34C759);

class CallScreen extends StatefulWidget {
  final String initialNumber;
  
  const CallScreen({super.key, required this.initialNumber});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  int _callState = 0; // 0=New, 1=Dialing, 2=Ringing, 4=Active, 7=Disconnected
  String _number = '';
  String? _name;
  bool _showKeypad = false;
  bool _isSpeakerOn = false;
  bool _isMuted = false;
  bool _isHold = false;
  bool _isRecording = false;
  String _dtmfInput = '';
  
  StreamSubscription? _subscription;
  Timer? _timer;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _number = widget.initialNumber;
    _resolveContactName();
    _subscription = TelecomService.callStateStream.listen((data) {
      if (!mounted) return;
      setState(() {
        _callState = data['state'] as int;
        if (data['number'] != 'Unknown') {
          _number = data['number'] as String;
        }
      });

      if (_callState == 4 && _timer == null) {
        _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (mounted) setState(() => _seconds++);
        });
        _maybeAutoRecord();
      }

      if (_callState == 7) {
        if (_isRecording) {
          TelecomService.stopRecording();
          if (mounted) setState(() => _isRecording = false);
        }
        
        _timer?.cancel();
        _timer = Timer(const Duration(seconds: 2), () {
          if (mounted && Navigator.canPop(context)) {
            Navigator.pop(context, _dtmfInput);
          }
        });
      }
    });
  }

  Future<void> _resolveContactName() async {
    if (await Permission.contacts.isGranted) {
      final contacts = await FlutterContacts.getAll(properties: {ContactProperty.phone});
      final cleanQuery = _number.replaceAll(RegExp(r'\D'), '');
      
      for (var contact in contacts) {
        for (var phone in contact.phones) {
          final cleanPhone = phone.number.replaceAll(RegExp(r'\D'), '');
          if (cleanPhone.isNotEmpty && cleanQuery.isNotEmpty && 
             (cleanPhone.contains(cleanQuery) || cleanQuery.contains(cleanPhone))) {
            if (mounted) {
              setState(() => _name = contact.displayName);
            }
            return;
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  void _onDigitPressed(String digit) {
    setState(() => _dtmfInput += digit);
    TelecomService.playDtmf(digit);
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _maybeAutoRecord() async {
    final prefs = await SharedPreferences.getInstance();
    final autoRecord = prefs.getBool('auto_record') ?? false;
    if (autoRecord && !_isRecording) _toggleRecording();
  }

  void _toggleRecording() {
    setState(() => _isRecording = !_isRecording);
    if (_isRecording) {
      final safeNumber = _number.replaceAll(RegExp(r'[^0-9+]'), '');
      final fileName = 'Call_${safeNumber}_${DateTime.now().millisecondsSinceEpoch}.wav';
      final dir = Directory('/sdcard/Music/OnyxDialer');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      TelecomService.startRecording('${dir.path}/$fileName');
    } else {
      TelecomService.stopRecording();
    }
  }

  String _getStateString() {
    if (_isHold || _callState == 3) return 'On Hold';
    switch (_callState) {
      case 1:
      case 9: return 'calling...';
      case 2: return 'Incoming Call';
      case 4: return _formatDuration(_seconds);
      case 7: return 'Call Ended';
      case 10: return 'Disconnecting...';
      default: return 'connecting...';
    }
  }

  // ── UI Components ────────────────────────────────────────────────────────

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: isActive ? _buttonActiveBg : _buttonBg,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 32,
              color: isActive ? Colors.black : Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildDialButton(String digit, String letters) {
    return GestureDetector(
      onTap: () => _onDigitPressed(digit),
      child: Container(
        width: 76,
        height: 76,
        decoration: const BoxDecoration(
          color: _buttonBg,
          shape: BoxShape.circle,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              digit,
              style: const TextStyle(fontSize: 34, color: Colors.white, fontWeight: FontWeight.w400),
            ),
            if (letters.isNotEmpty)
              Text(
                letters,
                style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600, letterSpacing: 1.5),
              ),
          ],
        ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            // Header Info
            const SizedBox(height: 40),
            
            if (!_showKeypad) ...[
              // Large Avatar to fill the empty space
              Container(
                width: 110, height: 110,
                decoration: const BoxDecoration(
                  color: Color(0xFF2C2C2E),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  (_name != null && _name!.trim().isNotEmpty) ? _name!.trim()[0].toUpperCase() : '#',
                  style: const TextStyle(fontSize: 52, color: Colors.white, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(height: 24),
            ],

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _name ?? _number,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 34, color: Colors.white, fontWeight: FontWeight.w400),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _getStateString(),
              style: const TextStyle(fontSize: 18, color: _iosSecondary),
            ),
            
            if (_name != null && _showKeypad == false) ...[
              const SizedBox(height: 8),
              Text(
                _number,
                style: const TextStyle(fontSize: 16, color: _iosSecondary),
              ),
            ],

            const Spacer(),

            // Middle Section
            if (_showKeypad) ...[
              // DTMF Keypad Overlay
              Container(
                height: 50,
                alignment: Alignment.center,
                child: Text(
                  _dtmfInput.isEmpty ? " " : _dtmfInput,
                  style: const TextStyle(fontSize: 32, color: Colors.white, fontWeight: FontWeight.w500, letterSpacing: 2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 45),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildDialButton('1', ''),
                        _buildDialButton('2', 'ABC'),
                        _buildDialButton('3', 'DEF'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildDialButton('4', 'GHI'),
                        _buildDialButton('5', 'JKL'),
                        _buildDialButton('6', 'MNO'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildDialButton('7', 'PQRS'),
                        _buildDialButton('8', 'TUV'),
                        _buildDialButton('9', 'WXYZ'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildDialButton('*', ''),
                        _buildDialButton('0', '+'),
                        _buildDialButton('#', ''),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              // Hide Keypad Button
              GestureDetector(
                onTap: () => setState(() => _showKeypad = false),
                child: const Text('Hide', style: TextStyle(fontSize: 18, color: Colors.white)),
              ),
              const SizedBox(height: 40),
            ] else ...[
              // 6-Button Grid
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 45),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildControlButton(
                          icon: Icons.mic_off_rounded,
                          label: 'mute',
                          onTap: () {
                            setState(() => _isMuted = !_isMuted);
                            TelecomService.setMuted(_isMuted);
                          },
                          isActive: _isMuted,
                        ),
                        _buildControlButton(
                          icon: Icons.dialpad_rounded,
                          label: 'keypad',
                          onTap: () => setState(() => _showKeypad = true),
                        ),
                        _buildControlButton(
                          icon: Icons.volume_up_rounded,
                          label: 'speaker',
                          onTap: () {
                            setState(() => _isSpeakerOn = !_isSpeakerOn);
                            TelecomService.setSpeaker(_isSpeakerOn);
                          },
                          isActive: _isSpeakerOn,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildControlButton(
                          icon: Icons.add_rounded,
                          label: 'add call',
                          onTap: () {},
                        ),
                        _buildControlButton(
                          icon: Icons.pause_rounded,
                          label: 'hold',
                          onTap: () {
                            setState(() => _isHold = !_isHold);
                            TelecomService.setHold(_isHold);
                          },
                          isActive: _isHold,
                        ),
                        _buildControlButton(
                          icon: Icons.fiber_manual_record_rounded,
                          label: 'record',
                          onTap: _toggleRecording,
                          isActive: _isRecording,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 60),
            ],

            // Bottom Actions
            Padding(
              padding: const EdgeInsets.only(bottom: 48, left: 45, right: 45),
              child: _callState == 2
                  ? Row( // Incoming Call (Accept/Decline)
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        GestureDetector(
                          onTap: () => TelecomService.endCall(),
                          child: Container(
                            width: 76, height: 76,
                            decoration: const BoxDecoration(color: _iosRed, shape: BoxShape.circle),
                            child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 36),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => TelecomService.answerCall(),
                          child: Container(
                            width: 76, height: 76,
                            decoration: const BoxDecoration(color: _iosGreen, shape: BoxShape.circle),
                            child: const Icon(Icons.call_rounded, color: Colors.white, size: 36),
                          ),
                        ),
                      ],
                    )
                  : Center( // Active/Dialing Call (End)
                      child: GestureDetector(
                        onTap: () {
                          if (_callState != 7) TelecomService.endCall();
                        },
                        child: Container(
                          width: 76, height: 76,
                          decoration: const BoxDecoration(color: _iosRed, shape: BoxShape.circle),
                          child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 36),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
