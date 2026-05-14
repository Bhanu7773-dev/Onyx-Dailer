import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavedialer/services/telecom_service.dart';

class CallScreen extends StatefulWidget {
  final String initialNumber;
  
  const CallScreen({Key? key, required this.initialNumber}) : super(key: key);

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
        // Auto-record if setting is enabled
        _maybeAutoRecord();
      }

      if (_callState == 7) {
        if (_isRecording) {
          TelecomService.stopRecording();
          if (mounted) {
            setState(() {
              _isRecording = false;
            });
          }
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
              setState(() {
                _name = contact.displayName;
              });
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
    setState(() {
      _dtmfInput += digit;
    });
    TelecomService.playDtmf(digit);
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Future<void> _maybeAutoRecord() async {
    final prefs = await SharedPreferences.getInstance();
    final autoRecord = prefs.getBool('auto_record') ?? false;
    if (autoRecord && !_isRecording) {
      _toggleRecording();
    }
  }

  void _toggleRecording() {
    setState(() {
      _isRecording = !_isRecording;
    });

    if (_isRecording) {
      final safeNumber = _number.replaceAll(RegExp(r'[^0-9+]'), '');
      final fileName = 'Call_${safeNumber}_${DateTime.now().millisecondsSinceEpoch}.wav';
      final dir = Directory('/sdcard/Music/OnyxDialer');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      TelecomService.startRecording('${dir.path}/$fileName');
    } else {
      TelecomService.stopRecording();
    }
  }

  String _getStateString() {
    if (_isHold || _callState == 3) {
      return 'On Hold';
    }
    
    switch (_callState) {
      case 1:
      case 9:
        return 'Calling...';
      case 2:
        return 'Incoming Call...';
      case 4:
        return _formatDuration(_seconds);
      case 7:
        return 'Call Ended';
      case 10:
        return 'Disconnecting...';
      default:
        return 'Connecting...';
    }
  }

  Widget _buildDialButton(String digit, String letters, BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _onDigitPressed(digit),
        splashColor: theme.colorScheme.secondaryContainer.withOpacity(0.5),
        highlightColor: theme.colorScheme.secondaryContainer.withOpacity(0.3),
        child: SizedBox(
          width: 75,
          height: 75,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                digit, 
                style: TextStyle(
                  fontSize: 32, 
                  fontWeight: FontWeight.w400,
                  color: theme.colorScheme.onSurface,
                )
              ),
              if (letters.isNotEmpty)
                Text(
                  letters, 
                  style: TextStyle(
                    fontSize: 10, 
                    color: theme.colorScheme.onSurfaceVariant, 
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                  )
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            if (_showKeypad) ...[
              const Spacer(),
              Container(
                height: 60,
                alignment: Alignment.center,
                child: Text(
                  _dtmfInput.isEmpty ? " " : _dtmfInput,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildDialButton('1', '', context),
                        _buildDialButton('2', 'ABC', context),
                        _buildDialButton('3', 'DEF', context),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildDialButton('4', 'GHI', context),
                        _buildDialButton('5', 'JKL', context),
                        _buildDialButton('6', 'MNO', context),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildDialButton('7', 'PQRS', context),
                        _buildDialButton('8', 'TUV', context),
                        _buildDialButton('9', 'WXYZ', context),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildDialButton('*', '', context),
                        _buildDialButton('0', '+', context),
                        _buildDialButton('#', '', context),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              _buildControlButton(Icons.dialpad, 'Hide', () {
                setState(() {
                  _showKeypad = false;
                });
              }),
              const SizedBox(height: 24),
            ] else ...[
              const SizedBox(height: 60),
              CircleAvatar(
                radius: 60,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(Icons.person, size: 60, color: theme.colorScheme.onPrimaryContainer),
              ),
              const SizedBox(height: 24),
              Text(
                _name ?? _number,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_name != null) ...[
                const SizedBox(height: 8),
                Text(
                  _number,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                _getStateString(),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: _callState == 7 ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildControlButton(Icons.mic_off, 'Mute', () {
                        setState(() {
                          _isMuted = !_isMuted;
                        });
                        TelecomService.setMuted(_isMuted);
                      }, isActive: _isMuted),
                      _buildControlButton(Icons.dialpad, 'Keypad', () {
                        setState(() {
                          _showKeypad = true;
                        });
                      }),
                      _buildControlButton(Icons.volume_up, 'Speaker', () {
                        setState(() {
                          _isSpeakerOn = !_isSpeakerOn;
                        });
                        TelecomService.setSpeaker(_isSpeakerOn);
                      }, isActive: _isSpeakerOn),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildControlButton(Icons.add_call, 'Add call', () {}),
                      _buildControlButton(Icons.pause, 'Hold', () {
                        setState(() {
                          _isHold = !_isHold;
                        });
                        TelecomService.setHold(_isHold);
                      }, isActive: _isHold),
                      _buildControlButton(Icons.fiber_manual_record, 'Record', _toggleRecording, isActive: _isRecording),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
            
            // End / Answer Buttons
            Padding(
              padding: const EdgeInsets.only(bottom: 48.0),
              child: _callState == 2 
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      FloatingActionButton.large(
                        heroTag: 'decline',
                        onPressed: () => TelecomService.endCall(),
                        backgroundColor: theme.colorScheme.errorContainer,
                        elevation: 0,
                        shape: const CircleBorder(),
                        child: Icon(Icons.call_end, color: theme.colorScheme.onErrorContainer, size: 36),
                      ),
                      FloatingActionButton.large(
                        heroTag: 'answer',
                        onPressed: () => TelecomService.answerCall(),
                        backgroundColor: Colors.green,
                        elevation: 0,
                        shape: const CircleBorder(),
                        child: const Icon(Icons.call, color: Colors.white, size: 36),
                      ),
                    ],
                  )
                : FloatingActionButton.large(
                    heroTag: 'end',
                    onPressed: () {
                      if (_callState != 7) {
                        TelecomService.endCall();
                      }
                    },
                    backgroundColor: theme.colorScheme.errorContainer,
                    elevation: 0,
                    shape: const CircleBorder(),
                    child: Icon(Icons.call_end, color: theme.colorScheme.onErrorContainer, size: 36),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton(IconData icon, String label, VoidCallback onTap, {bool isActive = false}) {
    final theme = Theme.of(context);
    final color = isActive ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant;
    final bgColor = isActive ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest;
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onTap,
          icon: Icon(icon, size: 32, color: color),
          style: IconButton.styleFrom(
            backgroundColor: bgColor,
            padding: const EdgeInsets.all(16),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
