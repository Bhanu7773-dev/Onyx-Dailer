import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavedialer/services/telecom_service.dart';
import 'package:wavedialer/themes/pixel/dialpad_screen.dart';
import 'package:proximity_sensor/proximity_sensor.dart';
import 'package:wavedialer/logic/call_controller.dart';

const _kCallBg = Color(0xFF0C0E12);
const _kCardBg = Color(0xFF161D26);
const _kAvatarBg = Color(0xFF1E2632);
const _kBlueAccent = Color(0xFF8AB4F8);
const _kRedEnd = Color(0xFFFF5C50);
const _kRedMuted = Color(0xFFFF7769);
const _kTextMuted = Color(0xFF8E9CAE);
const _kGreenAnswer = Color(0xFF34C759);

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

class _CallScreenState extends State<CallScreen> with WidgetsBindingObserver {
  final CallController _controller = CallController();
  Timer? _exitTimer;
  String _simLabel = 'SIM 1';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSimLabel();
    _controller.init(
      initialNumber: widget.initialNumber ?? 'Unknown',
      initialState: widget.initialState ?? 0,
      initialName: widget.initialName,
      initialSeconds: widget.initialSeconds,
    );
    _controller.addListener(_onControllerChange);
  }

  Future<void> _loadSimLabel() async {
    try {
      final sims = await TelecomService.getSimCards();
      if (sims.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final defaultSimId = prefs.getString('default_sim');
        final matchingSim = sims.firstWhere(
          (s) => s['id'] == defaultSimId,
          orElse: () => sims.first,
        );
        final label = matchingSim['label'] ?? matchingSim['carrier'] ?? 'SIM 1';
        if (mounted) setState(() => _simLabel = label);
      }
    } catch (e) {
      debugPrint('Error loading SIM label: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onControllerChange);
    _controller.dispose();
    _exitTimer?.cancel();
    ProximitySensor.setProximityScreenOff(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _controller.callState == 7) {
      ProximitySensor.setProximityScreenOff(false);
      _exitTimer?.cancel();
      if (widget.exitOnEnd) {
        SystemNavigator.pop();
      } else if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context, _controller.dtmfInput);
      } else if (mounted) {
        SystemNavigator.pop();
      }
    }
  }

  void _onControllerChange() {
    if (!mounted) return;
    setState(() {});

    if (_controller.callState == 7) {
      ProximitySensor.setProximityScreenOff(false);
      _exitTimer ??= Timer(Duration(seconds: widget.exitOnEnd ? 1 : 2), () {
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

  void _showAddCallSheet() {
    if (!_controller.isHold) {
      _controller.toggleHold();
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: _kCardBg,
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
                    color: const Color(0xFF353E4A),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Add Call',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Current call will be placed on hold',
                style: TextStyle(color: _kTextMuted, fontSize: 13),
              ),
              const SizedBox(height: 18),
              // Option 1: Dial a number
              InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DialpadScreen()),
                  );
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: _kAvatarBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _kBlueAccent.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.dialpad_rounded, color: _kBlueAccent, size: 22),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Dial a number',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Enter digits on keypad',
                              style: TextStyle(color: _kTextMuted, fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: _kTextMuted, size: 22),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Option 2: Choose from contacts
              InkWell(
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
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: _kAvatarBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _kBlueAccent.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.contacts_rounded, color: _kBlueAccent, size: 22),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Choose from contacts',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Search saved address book',
                              style: TextStyle(color: _kTextMuted, fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: _kTextMuted, size: 22),
                    ],
                  ),
                ),
              ),
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
                    style: TextStyle(color: _kTextMuted, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_controller.isNear) {
      return const Scaffold(backgroundColor: Colors.black);
    }

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
          if (Navigator.canPop(context)) {
            Navigator.pop(context);
          } else {
            SystemNavigator.pop();
          }
        }
      },
      child: Scaffold(
        backgroundColor: _kCallBg,
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 12),

              // ── Top Status Indicators (Carrier & Recording) ───────────────
              _buildTopPills(),

              const Spacer(flex: 1),

              // ── Center Avatar with Concentric Halo ─────────────────────────
              _buildAvatar(),

              const SizedBox(height: 20),

              // ── Contact Name, Number & Timer ──────────────────────────────
              _buildContactInfo(),

              const Spacer(flex: 2),

              // ── Middle Section: Keypad or 2x3 Controls ────────────────────
              if (_controller.showKeypad)
                _buildKeypadSection()
              else if (_controller.callState != 2 && _controller.callState != 7)
                _buildControlButtons(),

              const Spacer(flex: 2),

              // ── Bottom End / Incoming Action Button ───────────────────────
              Padding(
                padding: const EdgeInsets.only(bottom: 36),
                child: _controller.callState == 2
                    ? _buildIncomingActions()
                    : _buildEndCallButton(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Top Status Pills: [ Carrier ]  [ • Recording ] ────────────────────────
  Widget _buildTopPills() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // SIM / Carrier Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            decoration: BoxDecoration(
              color: _kCardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Text(
              _controller.simLabel ?? _simLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          // Recording Pill
          if (_controller.isRecording) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF281414),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _kRedEnd.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: _kRedEnd,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  const Text(
                    'Recording',
                    style: TextStyle(
                      color: _kRedMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ] else if (_controller.isSpam) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF281414),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _kRedEnd.withValues(alpha: 0.3)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber_rounded, color: _kRedEnd, size: 14),
                  SizedBox(width: 6),
                  Text(
                    'Spam',
                    style: TextStyle(
                      color: _kRedMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Circular Avatar with Halo Ring ────────────────────────────────────────
  Widget _buildAvatar() {
    final name = _controller.name ?? _controller.number;
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';

    return Center(
      child: Container(
        width: 144,
        height: 144,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.04),
            width: 1.5,
          ),
        ),
        alignment: Alignment.center,
        child: Container(
          width: 118,
          height: 118,
          decoration: const BoxDecoration(
            color: _kAvatarBg,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            initial,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 44,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  // ── Contact Info & Glowing Blue Duration ──────────────────────────────────
  Widget _buildContactInfo() {
    final name = (_controller.name != null && _controller.name!.trim().isNotEmpty)
        ? _controller.name!
        : _controller.number;
    final phone = _controller.number;

    String timerOrStateText;
    Color timerColor;

    if (_controller.callState == 4) {
      timerOrStateText = _controller.formatDuration(_controller.seconds);
      timerColor = _kBlueAccent;
    } else if (_controller.isHold || _controller.callState == 3) {
      timerOrStateText = 'On Hold';
      timerColor = const Color(0xFFFFB74D);
    } else if (_controller.callState == 7) {
      timerOrStateText = 'Call Ended';
      timerColor = _kRedMuted;
    } else if (_controller.callState == 2) {
      timerOrStateText = 'Incoming Call';
      timerColor = _kBlueAccent;
    } else {
      timerOrStateText = _controller.getStateString();
      timerColor = _kBlueAccent;
    }

    return Column(
      children: [
        // Name
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 27,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
        ),
        const SizedBox(height: 6),

        // Phone number
        if (name != phone && phone.isNotEmpty) ...[
          Text(
            phone,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _kTextMuted,
              fontSize: 15,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Timer / State
        Text(
          timerOrStateText,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: timerColor,
            fontSize: 23,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  // ── 2x3 Grid of Control Buttons ───────────────────────────────────────────
  Widget _buildControlButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          // Row 1: Mute, Keypad, Speaker
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildControlButton(
                icon: _controller.isMuted ? Icons.mic_off_rounded : Icons.mic_off_outlined,
                label: 'Mute',
                isActive: _controller.isMuted,
                onTap: _controller.toggleMute,
              ),
              _buildControlButton(
                icon: Icons.dialpad_rounded,
                label: 'Keypad',
                isActive: _controller.showKeypad,
                onTap: _controller.toggleKeypad,
              ),
              _buildControlButton(
                icon: _controller.isSpeakerOn ? Icons.volume_up_rounded : Icons.volume_up_outlined,
                label: 'Speaker',
                isActive: _controller.isSpeakerOn,
                onTap: _controller.toggleSpeaker,
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Row 2: Record, Add call, Hold (or Merge/Swap if multi-call)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildControlButton(
                icon: _controller.isRecording
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                label: 'Record',
                isActive: _controller.isRecording,
                isRecordButton: true,
                onTap: _controller.toggleRecording,
              ),
              if (_controller.callCount >= 2) ...[
                _buildControlButton(
                  icon: Icons.merge_type_rounded,
                  label: 'Merge',
                  onTap: () async {
                    _controller.mergeCall();
                    await Future.delayed(const Duration(milliseconds: 600));
                    await _controller.updateCallCount();
                  },
                ),
                _buildControlButton(
                  icon: Icons.swap_calls_rounded,
                  label: 'Swap',
                  onTap: _controller.swapCall,
                ),
              ] else ...[
                _buildControlButton(
                  icon: Icons.add_call,
                  label: 'Add call',
                  onTap: _showAddCallSheet,
                ),
                _buildControlButton(
                  icon: Icons.pause_rounded,
                  label: 'Hold',
                  isActive: _controller.isHold,
                  onTap: _controller.toggleHold,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
    bool isRecordButton = false,
  }) {
    final Color bgColor;
    final Color iconColor;
    final Color textColor;
    final Border? border;

    if (isActive) {
      if (isRecordButton) {
        bgColor = const Color(0xFF1B2738);
        border = Border.all(color: const Color(0xFF4A74A8), width: 1.5);
        iconColor = _kBlueAccent;
        textColor = _kBlueAccent;
      } else {
        bgColor = const Color(0xFF1D2E47);
        border = Border.all(color: _kBlueAccent, width: 1.5);
        iconColor = _kBlueAccent;
        textColor = _kBlueAccent;
      }
    } else {
      bgColor = _kCardBg;
      border = Border.all(color: Colors.white.withValues(alpha: 0.05));
      iconColor = Colors.white;
      textColor = _kTextMuted;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
              border: border,
            ),
            child: Icon(icon, color: iconColor, size: 27),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ── Keypad Overlay Section ────────────────────────────────────────────────
  Widget _buildKeypadSection() {
    return Column(
      children: [
        Container(
          height: 42,
          alignment: Alignment.center,
          child: Text(
            _controller.dtmfInput.isEmpty ? ' ' : _controller.dtmfInput,
            style: const TextStyle(
              fontSize: 28,
              color: Colors.white,
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
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
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildDialButton('4', 'GHI'),
                  _buildDialButton('5', 'JKL'),
                  _buildDialButton('6', 'MNO'),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildDialButton('7', 'PQRS'),
                  _buildDialButton('8', 'TUV'),
                  _buildDialButton('9', 'WXYZ'),
                ],
              ),
              const SizedBox(height: 12),
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
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            _controller.toggleKeypad();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: _kCardBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('Hide Keypad', style: TextStyle(fontSize: 14, color: _kTextMuted)),
          ),
        ),
      ],
    );
  }

  Widget _buildDialButton(String digit, String letters) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _controller.onDigitPressed(digit);
      },
      child: Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          color: _kCardBg,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              digit,
              style: const TextStyle(
                fontSize: 27,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (letters.isNotEmpty)
              Text(
                letters,
                style: const TextStyle(
                  fontSize: 10,
                  color: _kTextMuted,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Bottom End Call Button (Glowing Coral Red) ─────────────────────────────
  Widget _buildEndCallButton() {
    return Center(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          if (_controller.callState != 7) {
            TelecomService.endCall();
          }
        },
        child: Container(
          width: 74,
          height: 74,
          decoration: BoxDecoration(
            color: _kRedEnd,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _kRedEnd.withValues(alpha: 0.35),
                blurRadius: 24,
                spreadRadius: 2,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(
            Icons.call_end_rounded,
            color: Colors.white,
            size: 34,
          ),
        ),
      ),
    );
  }

  // ── Incoming Call Actions (Decline & Answer) ───────────────────────────────
  Widget _buildIncomingActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 52),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Decline
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  TelecomService.endCall();
                },
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: _kRedEnd,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _kRedEnd.withValues(alpha: 0.35),
                        blurRadius: 20,
                        spreadRadius: 2,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 34),
                ),
              ),
              const SizedBox(height: 10),
              const Text('Decline', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),

          // Answer
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  TelecomService.answerCall();
                },
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: _kGreenAnswer,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _kGreenAnswer.withValues(alpha: 0.35),
                        blurRadius: 20,
                        spreadRadius: 2,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.call_rounded, color: Colors.white, size: 34),
                ),
              ),
              const SizedBox(height: 10),
              const Text('Answer', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Contact Picker for "Add Call" ───────────────────────────────────────────
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
    const kBg = Color(0xFF0B0F14);

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        title: const Text(
          'Select Contact',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 19),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: _kCardBg,
                borderRadius: BorderRadius.circular(23),
                border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
              ),
              child: TextField(
                controller: _searchCtrl,
                onChanged: _filter,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: const InputDecoration(
                  hintText: 'Search contacts...',
                  hintStyle: TextStyle(color: _kTextMuted, fontSize: 14),
                  prefixIcon: Icon(Icons.search_rounded, color: _kTextMuted, size: 20),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kBlueAccent))
          : _filtered.isEmpty
              ? const Center(
                  child: Text('No contacts found', style: TextStyle(color: _kTextMuted, fontSize: 15)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _filtered.length,
                  itemBuilder: (ctx, i) {
                    final c = _filtered[i];
                    final phone = c.phones.first.number;
                    final displayName = (c.displayName != null && c.displayName!.isNotEmpty)
                        ? c.displayName!
                        : phone;
                    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: InkWell(
                        onTap: () {
                          Navigator.pop(context);
                          widget.onNumberSelected(phone);
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                          decoration: BoxDecoration(
                            color: _kCardBg,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: const BoxDecoration(
                                  color: _kAvatarBg,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    initial,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      displayName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      phone,
                                      style: const TextStyle(color: _kTextMuted, fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                width: 38,
                                height: 38,
                                decoration: const BoxDecoration(
                                  color: _kAvatarBg,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.call_rounded, color: _kBlueAccent, size: 19),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
