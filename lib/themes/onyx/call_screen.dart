import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavedialer/services/telecom_service.dart';
import 'package:wavedialer/themes/onyx/dialpad_screen.dart';
import 'package:proximity_sensor/proximity_sensor.dart';
import 'package:wavedialer/logic/call_controller.dart';

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
  final int initialSeconds;
  final bool exitOnEnd;
  const CallScreen({
    super.key,
    this.initialNumber,
    this.initialState,
    this.initialName,
    this.initialSeconds = 0,
    this.exitOnEnd = false,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final CallController _controller = CallController();
  Timer? _exitTimer;

  @override
  void initState() {
    super.initState();
    _controller.init(
      initialNumber: widget.initialNumber ?? 'Unknown',
      initialState: widget.initialState ?? 0,
      initialName: widget.initialName,
      initialSeconds: widget.initialSeconds,
    );
    _controller.addListener(_onControllerChange);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChange);
    _controller.dispose();
    _exitTimer?.cancel();
    ProximitySensor.setProximityScreenOff(false);
    super.dispose();
  }

  void _onControllerChange() {
    if (!mounted) return;
    setState(() {});

    // Manage exit transition when call ends
    if (_controller.callState == 7) {
      ProximitySensor.setProximityScreenOff(false);
      if (_exitTimer == null) {
        _exitTimer = Timer(Duration(seconds: widget.exitOnEnd ? 1 : 2), () {
          if (mounted) {
            ProximitySensor.setProximityScreenOff(false);
            if (widget.exitOnEnd) {
              SystemNavigator.pop();
            } else if (Navigator.canPop(context)) {
              Navigator.pop(context, _controller.dtmfInput);
            }
          }
        });
      }
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
      onTap: () => _controller.onDigitPressed(digit),
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        ProximitySensor.setProximityScreenOff(false);
        if (_controller.callState == 7) {
          if (widget.exitOnEnd) {
            SystemNavigator.pop();
          } else if (Navigator.canPop(context)) {
            Navigator.pop(context, _controller.dtmfInput);
          } else {
            SystemNavigator.pop();
          }
        } else {
          // While call is ringing or active, back button minimizes UI while call continues in notification
          if (Navigator.canPop(context)) {
            Navigator.pop(context);
          } else {
            SystemNavigator.pop();
          }
        }
      },
      child: Scaffold(
        backgroundColor: _bg,
        resizeToAvoidBottomInset: false,
        body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            
            if (!_controller.showKeypad) ...[
              // Subtle Metadata
              Center(
                child: Text(
                  _controller.getMetadataString(),
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
                    _controller.name ?? _controller.number,
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
              if (_controller.isSpam) ...[
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: _iosRed.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _iosRed, width: 1.5),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warning_amber_rounded, color: _iosRed, size: 18),
                        SizedBox(width: 6),
                        Text(
                          'SPAM SUSPECTED',
                          style: TextStyle(
                            color: _iosRed,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              
              // Status / Timer / Number
              Center(
                child: Text(
                  _controller.getStateString(),
                  style: TextStyle(
                    fontSize: 18, 
                    color: _controller.callState == 4 ? _iosGreen : Colors.white.withOpacity(0.5), 
                    fontWeight: _controller.callState == 4 ? FontWeight.bold : FontWeight.normal
                  ),
                ),
              ),
                
              const SizedBox(height: 24),
            ],

            const Spacer(),

            if (_controller.showKeypad) ...[
              Container(
                height: 50,
                alignment: Alignment.center,
                child: Text(
                  _controller.dtmfInput.isEmpty ? " " : _controller.dtmfInput,
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
                onTap: _controller.toggleKeypad,
                child: const Center(child: Text('Hide', style: TextStyle(fontSize: 18, color: Colors.white))),
              ),
              const SizedBox(height: 40),
            ] else if (_controller.callState != 2 && _controller.callState != 7) ...[
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
                          onTap: _controller.toggleMute,
                          isActive: _controller.isMuted,
                        ),
                        _buildControlButton(
                          icon: Icons.dialpad_rounded,
                          label: 'keypad',
                          onTap: _controller.toggleKeypad,
                        ),
                        _buildControlButton(
                          icon: Icons.volume_up_rounded,
                          label: 'speaker',
                          onTap: _controller.toggleSpeaker,
                          isActive: _controller.isSpeakerOn,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    if (_controller.callCount >= 2) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildControlButton(
                            icon: Icons.merge_type_rounded,
                            label: 'merge',
                            onTap: () async {
                              _controller.mergeCall();
                              await Future.delayed(const Duration(milliseconds: 600));
                              await _controller.updateCallCount();
                            },
                          ),
                          _buildControlButton(
                            icon: Icons.swap_calls_rounded,
                            label: 'swap',
                            onTap: _controller.swapCall,
                          ),
                          _buildControlButton(
                            icon: Icons.fiber_manual_record_rounded,
                            label: 'record',
                            onTap: _controller.toggleRecording,
                            isActive: _controller.isRecording,
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
                              if (!_controller.isHold) {
                                _controller.toggleHold();
                                await Future.delayed(const Duration(milliseconds: 300));
                              }
                              if (!mounted) return;
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
                            onTap: _controller.toggleHold,
                            isActive: _controller.isHold,
                          ),
                          _buildControlButton(
                            icon: Icons.fiber_manual_record_rounded,
                            label: 'record',
                            onTap: _controller.toggleRecording,
                            isActive: _controller.isRecording,
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
              child: _controller.callState == 2
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
                          if (_controller.callState != 7) TelecomService.endCall();
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    ));
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
