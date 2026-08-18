import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavedialer/services/telecom_service.dart';
import 'package:wavedialer/screens/dialpad_screen.dart';
import 'package:proximity_sensor/proximity_sensor.dart';

const _bg = Color(0xFF000000);
const _iosSecondary = Color(0xFF8E8E93);
const _buttonBg = Color(0x33FFFFFF);
const _buttonActiveBg = Color(0xFFFFFFFF);
const _iosRed = Color(0xFFFF3B30);
const _iosGreen = Color(0xFF34C759);

class CallScreen extends StatefulWidget {
  final String? initialNumber;
  final int? initialState;
  final String? initialName;
  final bool exitOnEnd;
  const CallScreen({super.key, this.initialNumber, this.initialState, this.initialName, this.exitOnEnd = false});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  int _callState = 0;
  String _number = '';
  String? _name;
  bool _showKeypad = false;
  bool _isSpeakerOn = false;
  bool _isMuted = false;
  bool _isHold = false;
  bool _isRecording = false;
  String _dtmfInput = '';
  int _callCount = 1;
  
  StreamSubscription? _subscription;
  StreamSubscription<int>? _proximitySub;
  Timer? _timer;
  int _seconds = 0;
  bool _isNear = false;
  bool _blockProximity = false;
  bool _isHoldActionPending = false;

  @override
  void initState() {
    super.initState();
    _number = widget.initialNumber ?? 'Unknown';
    _callState = widget.initialState ?? 0;
    
    if (widget.initialName != null && widget.initialName!.isNotEmpty) {
      _name = widget.initialName;
    } else {
      _resolveContactName();
    }
    
    _initProximity();
    _subscription = TelecomService.callStateStream.listen((data) {
      if (!mounted) return;

      // Update call count on every event
      _updateCallCount();

      final incomingNumber = (data['number'] as String?) ?? 'Unknown';
      final newState = data['state'] as int;

      // When a call disconnects and we have another call on hold, auto-unhold it
      if (newState == 7 && incomingNumber != _number) {
        debugPrint('CallScreen: Other call disconnected, auto-unholding...');
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && _isHold) {
            TelecomService.setHold(false);
            setState(() => _isHold = false);
          }
        });
        return;
      }

      setState(() {
        // If we were disconnected but now a new call is starting, cancel the pop timer!
        if (_callState == 7 && newState != 7) {
          _timer?.cancel();
        }
        
        _callState = newState;

        if (data['name'] != null && (data['name'] as String).isNotEmpty) {
          _name = data['name'] as String;
        }

        if (incomingNumber != 'Unknown' && incomingNumber != _number) {
          _number = incomingNumber;
          if (_name == null) {
            _resolveContactName(); // Re-resolve if number actually changed and we don't have a name
          }
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
        _timer = Timer(Duration(seconds: widget.exitOnEnd ? 1 : 2), () {
          if (mounted) {
            if (widget.exitOnEnd) {
              SystemNavigator.pop();
            } else if (Navigator.canPop(context)) {
              Navigator.pop(context, _dtmfInput);
            }
          }
        });
      }
    });
  }

  Future<void> _resolveContactName() async {
    if (await Permission.contacts.isGranted) {
      final contacts = await FlutterContacts.getAll(properties: {ContactProperty.phone});
      final cleanQuery = _number.replaceAll(RegExp(r'\D'), '');
      
      // If the query is just a few digits, don't match (prevents false positives)
      if (cleanQuery.length < 5) return;

      for (var contact in contacts) {
        for (var phone in contact.phones) {
          final cleanPhone = phone.number.replaceAll(RegExp(r'\D'), '');
          
          // Match if one number ends with the other (handles +91 vs local)
          if (cleanPhone.isNotEmpty && 
             (cleanPhone.endsWith(cleanQuery) || cleanQuery.endsWith(cleanPhone))) {
            if (mounted) {
              setState(() {
                _name = contact.displayName;
                debugPrint('CallScreen: Resolved local contact name: $_name');
              });
            }
            return;
          }
        }
      }
    }
  }

  Future<void> _initProximity() async {
    final prefs = await SharedPreferences.getInstance();
    _blockProximity = prefs.getBool('block_proximity') ?? false;
    
    if (!_blockProximity) {
      ProximitySensor.setProximityScreenOff(true);
      _proximitySub = ProximitySensor.events.listen((event) {
        if (mounted) setState(() => _isNear = (event > 0));
      });
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _proximitySub?.cancel();
    _timer?.cancel();
    ProximitySensor.setProximityScreenOff(false);
    super.dispose();
  }

  Future<void> _updateCallCount() async {
    final info = await TelecomService.getCallInfo();
    if (!mounted) return;
    final count = (info['count'] as int?) ?? 1;
    final isConf = (info['isConference'] as bool?) ?? false;
    final isHolding = (info['isHolding'] as bool?) ?? false;

    setState(() {
      _callCount = count;
      if (isConf) {
        _name = 'Conference Call';
        _isHold = false;
      } else if (!isHolding && _isHold) {
        _isHold = false;
      }
    });
  }

  void _onDigitPressed(String digit) {
    setState(() => _dtmfInput += digit);
    TelecomService.playLocalDtmf(digit);
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

  Future<void> _toggleRecording() async {
    setState(() => _isRecording = !_isRecording);
    if (_isRecording) {
      final safeNumber = _number.replaceAll(RegExp(r'[^0-9+]'), '');
      final fileName = 'Call_${safeNumber}_${DateTime.now().millisecondsSinceEpoch}.wav';
      final dir = Directory('/storage/emulated/0/Music/OnyxDialer');
      if (!(await dir.exists())) await dir.create(recursive: true);
      TelecomService.startRecording('${dir.path}/$fileName');
    } else {
      TelecomService.stopRecording();
    }
  }

  String _getMetadataString() {
    switch (_callState) {
      case 2: return 'I N C O M I N G  C A L L';
      case 1:
      case 9: return 'O U T G O I N G  C A L L';
      case 4: return 'A C T I V E  C A L L';
      default: return 'O N Y X  D I A L E R';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            
            if (!_showKeypad) ...[
              // Subtle Metadata
              Center(
                child: Text(
                  _getMetadataString(),
                  style: TextStyle(
                    fontSize: 14, 
                    color: Colors.white.withOpacity(0.5), 
                    fontWeight: FontWeight.w600, 
                    letterSpacing: 4
                  ),
                ),
              ),
              const SizedBox(height: 12),
              
              // Hero Name
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Center(
                  child: Text(
                    _name ?? _number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 42, 
                      color: Colors.white, 
                      fontWeight: FontWeight.w600,
                      letterSpacing: -1
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              
              const SizedBox(height: 8),
              
              // Status / Timer / Number
              Center(
                child: Text(
                  _getStateString(),
                  style: TextStyle(
                    fontSize: 18, 
                    color: _callState == 4 ? _iosGreen : Colors.white.withOpacity(0.5), 
                    fontWeight: _callState == 4 ? FontWeight.bold : FontWeight.normal
                  ),
                ),
              ),
                
              const SizedBox(height: 24),
            ],

            const Spacer(),

            if (_showKeypad) ...[
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
              GestureDetector(
                onTap: () => setState(() => _showKeypad = false),
                child: const Center(child: Text('Hide', style: TextStyle(fontSize: 18, color: Colors.white))),
              ),
              const SizedBox(height: 40),
            ] else if (_callState != 2 && _callState != 7) ...[
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
                    if (_callCount >= 2) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildControlButton(
                            icon: Icons.merge_type_rounded,
                            label: 'merge',
                            onTap: () async {
                              setState(() {
                                _isHold = false;
                                _callCount = 1;
                                _name = 'Conference Call';
                              });
                              await TelecomService.mergeCall();
                              await Future.delayed(const Duration(milliseconds: 600));
                              await _updateCallCount();
                            },
                          ),
                          _buildControlButton(
                            icon: Icons.swap_calls_rounded,
                            label: 'swap',
                            onTap: () => TelecomService.swapCall(),
                          ),
                          _buildControlButton(
                            icon: Icons.fiber_manual_record_rounded,
                            label: 'record',
                            onTap: _toggleRecording,
                            isActive: _isRecording,
                          ),
                        ],
                      ),
                    ] else ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildControlButton(
                            icon: Icons.add_rounded,
                            label: 'add call',
                            onTap: () async {
                              // Hold the current call first
                              if (!_isHold) {
                                setState(() => _isHold = true);
                                await TelecomService.setHold(true);
                                await Future.delayed(const Duration(milliseconds: 300));
                              }
                              if (!mounted) return;
                              // Show options: Dialpad or Contacts
                              showModalBottomSheet(
                                context: context,
                                backgroundColor: const Color(0xFF1C1C1E),
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                                ),
                                builder: (ctx) => SafeArea(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 36, height: 4,
                                          margin: const EdgeInsets.only(bottom: 20),
                                          decoration: BoxDecoration(
                                            color: Colors.white24,
                                            borderRadius: BorderRadius.circular(2),
                                          ),
                                        ),
                                        ListTile(
                                          leading: const Icon(Icons.dialpad_rounded, color: Colors.white),
                                          title: const Text('Dial a number', style: TextStyle(color: Colors.white, fontSize: 17)),
                                          onTap: () {
                                            Navigator.pop(ctx);
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(builder: (_) => const DialpadScreen()),
                                            );
                                          },
                                        ),
                                        ListTile(
                                          leading: const Icon(Icons.contacts_rounded, color: Colors.white),
                                          title: const Text('Choose from contacts', style: TextStyle(color: Colors.white, fontSize: 17)),
                                          onTap: () {
                                            Navigator.pop(ctx);
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => _AddCallContactPicker(
                                                  onNumberSelected: (number) {
                                                    TelecomService.handleOutgoingCall(context, number);
                                                  },
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          _buildControlButton(
                            icon: Icons.pause_rounded,
                            label: 'hold',
                            onTap: () async {
                              if (_isHoldActionPending) return;
                              setState(() => _isHoldActionPending = true);
                              
                              final newHoldState = !_isHold;
                              setState(() => _isHold = newHoldState);
                              await TelecomService.setHold(newHoldState);
                              
                              // Allow next action after short delay
                              await Future.delayed(const Duration(milliseconds: 500));
                              if (mounted) setState(() => _isHoldActionPending = false);
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
                  ],
                ),
              ),
              const SizedBox(height: 60),
            ],

            Padding(
              padding: const EdgeInsets.only(bottom: 80, left: 48, right: 48),
              child: _callState == 2
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildAction(
                          icon: Icons.call_end_rounded,
                          label: 'Decline',
                          color: _iosRed,
                          onTap: () => TelecomService.endCall(),
                        ),
                        _buildAction(
                          icon: Icons.call_rounded,
                          label: 'Answer',
                          color: _iosGreen,
                          onTap: () => TelecomService.answerCall(),
                        ),
                      ],
                    )
                  : Center(
                      child: _buildAction(
                        icon: Icons.call_end_rounded,
                        label: 'End Call',
                        color: _iosRed,
                        onTap: () {
                          if (_callState != 7) TelecomService.endCall();
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 84, height: 84,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: color.withOpacity(0.3), blurRadius: 20, spreadRadius: 5)
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 40),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

// In-app contact picker for "Add Call" flow
class _AddCallContactPicker extends StatefulWidget {
  final void Function(String number) onNumberSelected;
  const _AddCallContactPicker({required this.onNumberSelected});

  @override
  State<_AddCallContactPicker> createState() => _AddCallContactPickerState();
}

class _AddCallContactPickerState extends State<_AddCallContactPicker> {
  List<Contact> _contacts = [];
  List<Contact> _filtered = [];
  final TextEditingController _searchCtrl = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    if (await Permission.contacts.isGranted) {
      final contacts = await FlutterContacts.getAll(properties: {ContactProperty.phone});
      contacts.sort((a, b) => (a.displayName ?? '').compareTo(b.displayName ?? ''));
      if (mounted) {
        setState(() {
          _contacts = contacts.where((c) => c.phones.isNotEmpty).toList();
          _filtered = _contacts;
          _loading = false;
        });
      }
    } else {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _filter(String query) {
    final q = query.toLowerCase();
    setState(() {
      _filtered = _contacts.where((c) {
        final name = (c.displayName ?? '').toLowerCase();
        final nameMatch = name.contains(q);
        final phoneMatch = c.phones.any((p) => p.number.replaceAll(RegExp(r'\D'), '').contains(q));
        return nameMatch || phoneMatch;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text('Select Contact', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _filter,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search contacts...',
                hintStyle: const TextStyle(color: Color(0xFF8E8E93)),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF8E8E93)),
                filled: true,
                fillColor: const Color(0xFF2C2C2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _filtered.isEmpty
              ? const Center(child: Text('No contacts found', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 16)))
              : ListView.builder(
                  itemCount: _filtered.length,
                  itemBuilder: (ctx, i) {
                    final c = _filtered[i];
                    final phone = c.phones.first.number;
                    final displayName = (c.displayName != null && c.displayName!.isNotEmpty) ? c.displayName! : phone;
                    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '#';
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF48484A),
                        child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                      ),
                      title: Text(displayName, style: const TextStyle(color: Colors.white, fontSize: 16)),
                      subtitle: Text(phone, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 13)),
                      trailing: const Icon(Icons.call_rounded, color: Color(0xFF34C759), size: 22),
                      onTap: () {
                        Navigator.pop(context);
                        widget.onNumberSelected(phone);
                      },
                    );
                  },
                ),
    );
  }
}
