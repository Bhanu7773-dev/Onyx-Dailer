import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:proximity_sensor/proximity_sensor.dart';
import 'package:wavedialer/logic/call_controller.dart';
import 'package:wavedialer/services/telecom_service.dart';
import 'package:wavedialer/themes/onyx/dialpad_screen.dart';

// ── Nothing Phone palette ──────────────────────────────────────────────────
const _nBg       = Color(0xFF0D0D0D);
const _nCard     = Color(0xFF1A1A1A);
const _nButton   = Color(0xFF242424);
const _nButtonAc = Color(0xFFFFFFFF);
const _nRed      = Color(0xFFE5162A);
const _nGreen    = Color(0xFF30D158);
const _nLabel    = Color(0xFF9E9E9E);
const _nWhite    = Color(0xFFFFFFFF);

// ── Nothing dot-matrix font name ───────────────────────────────────────────
const _nFont = 'NothingFont';

class CallScreen extends StatefulWidget {
  final String? initialNumber;
  final int?    initialState;
  final String? initialName;
  final int     initialSeconds;
  final bool    exitOnEnd;

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

class _CallScreenState extends State<CallScreen>
    with TickerProviderStateMixin {
  final CallController _c = CallController();
  Timer? _exitTimer;

  // Hero transition: incoming (full-bg) → active (compact avatar)
  late final AnimationController _heroCtrl;
  late final Animation<double> _heroProgress; // 0 = incoming, 1 = active
  // Ripple animation for incoming screen
  late final AnimationController _rippleCtrl;

  bool _wasActive = false; // so we only animate once

  @override
  void initState() {
    super.initState();

    _heroCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _heroProgress = CurvedAnimation(
      parent: _heroCtrl,
      curve: Curves.easeInOutCubic,
    );

    _rippleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    _c.init(
      initialNumber: widget.initialNumber ?? 'Unknown',
      initialState:  widget.initialState  ?? 0,
      initialName:   widget.initialName,
      initialSeconds: widget.initialSeconds,
    );
    _c.addListener(_onControllerChange);

    // If we launched straight into active (answered from notification), skip animation
    if (widget.initialState == 4) {
      _heroCtrl.value = 1.0;
      _wasActive = true;
      _rippleCtrl.stop();
    }
  }

  @override
  void dispose() {
    _c.removeListener(_onControllerChange);
    _c.dispose();
    _exitTimer?.cancel();
    _heroCtrl.dispose();
    _rippleCtrl.dispose();
    ProximitySensor.setProximityScreenOff(false);
    super.dispose();
  }

  void _onControllerChange() {
    if (!mounted) return;
    setState(() {});

    // Transition to active layout when call is answered
    if (_c.callState == 4 && !_wasActive) {
      _wasActive = true;
      _rippleCtrl.stop();
      _heroCtrl.forward();
    }

    // Handle call end
    if (_c.callState == 7) {
      ProximitySensor.setProximityScreenOff(false);
      if (_exitTimer == null) {
        _exitTimer = Timer(Duration(seconds: widget.exitOnEnd ? 1 : 2), () {
          if (mounted) {
            ProximitySensor.setProximityScreenOff(false);
            if (widget.exitOnEnd) {
              SystemNavigator.pop();
            } else if (Navigator.canPop(context)) {
              Navigator.pop(context, _c.dtmfInput);
            }
          }
        });
      }
    }
  }

  // ── Avatar/initials widget ─────────────────────────────────────────────
  Widget _avatar({required double size}) {
    final displayName = _c.name ?? _c.number;
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    return Container(
      width: size, height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF2C2C2C),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: size * 0.42,
            fontWeight: FontWeight.w600,
            color: _nWhite,
            fontFamily: _nFont,
          ),
        ),
      ),
    );
  }

  // ── Ripple rings behind answer button (incoming screen) ─────────────────
  Widget _buildRippleRings() {
    return AnimatedBuilder(
      animation: _rippleCtrl,
      builder: (_, __) {
        return Stack(
          alignment: Alignment.center,
          children: List.generate(3, (i) {
            final progress = (_rippleCtrl.value + i / 3) % 1.0;
            final scale = 0.4 + progress * 0.6;
            final opacity = (1.0 - progress).clamp(0.0, 1.0) * 0.25;
            return Transform.scale(
              scale: scale,
              child: Container(
                width: 200, height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _nWhite.withValues(alpha: opacity),
                    width: 1.5,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  // ── Full-screen incoming layout ─────────────────────────────────────────
  Widget _buildIncomingScreen() {
    final size = MediaQuery.of(context).size;
    final displayName = _c.name ?? _c.number;
    final isSpam = _c.isSpam;

    return Column(
      children: [
        // Avatar section — only top 38% so name sits right below
        SizedBox(
          height: size.height * 0.38,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: const Color(0xFF1A1A1A)),
              Center(child: _avatar(size: size.width * 0.48)),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.6, 1.0],
                      colors: [
                        Colors.black.withValues(alpha: 0.0),
                        Colors.black.withValues(alpha: 0.45),
                        _nBg,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Name + "is calling" pill — directly below avatar, no gap
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 14),
              Text(
                displayName.toUpperCase(),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: _nFont,
                  fontSize: 34,
                  color: _nWhite,
                  height: 1.1,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
                decoration: BoxDecoration(
                  color: isSpam ? _nRed : _nRed.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(
                  isSpam ? 'SPAM DETECTED' : 'is calling...',
                  style: const TextStyle(
                    fontFamily: _nFont,
                    fontSize: 12,
                    color: _nWhite,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),

        const Spacer(),

        // Decline (left) + Answer (right) — no ripple, full width spread
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Decline
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => TelecomService.endCall(),
                    child: Container(
                      width: 72, height: 72,
                      decoration: BoxDecoration(
                        color: _nRed,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: _nRed.withValues(alpha: 0.35), blurRadius: 20, spreadRadius: 3)],
                      ),
                      child: const Icon(Icons.call_end_rounded, color: _nWhite, size: 34),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text('Decline', style: TextStyle(color: _nLabel, fontSize: 13, fontFamily: _nFont, letterSpacing: 1)),
                ],
              ),
              // Answer — plain button, no ripple
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => TelecomService.answerCall(),
                    child: Container(
                      width: 72, height: 72,
                      decoration: BoxDecoration(
                        color: _nGreen,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: _nGreen.withValues(alpha: 0.4), blurRadius: 24, spreadRadius: 4)],
                      ),
                      child: const Icon(Icons.call_rounded, color: _nWhite, size: 34),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text('Answer', style: TextStyle(color: _nLabel, fontSize: 13, fontFamily: _nFont, letterSpacing: 1)),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 52),
      ],
    );
  }

  // ── Compact active call layout ─────────────────────────────────────────
  Widget _buildActiveScreen() {
    return Column(
      children: [
        // Push avatar row ~3x lower than before (~35% from top)
        const SizedBox(height: 160),

        // Avatar + name + timer row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              _avatar(size: 56),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (_c.name ?? _c.number).toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: _nFont,
                        fontSize: 20,
                        color: _nWhite,
                        letterSpacing: 1.5,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _TimerDisplay(timerText: _c.getStateString()),
                  ],
                ),
              ),
            ],
          ),
        ),


        const SizedBox(height: 32),

        // ── Animated dot-matrix waveform ─────────────────────────────────
        const _NothingWaveform(),

        const Spacer(),

        // Keypad overlay or control grid
        if (_c.showKeypad) ...[ _buildKeypad() ]
        else ...[ _buildControlGrid() ],

        const SizedBox(height: 28),

        // End call button
        GestureDetector(
          onTap: () {
            if (_c.callState != 7) TelecomService.endCall();
          },
          child: Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: _nRed,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: _nRed.withValues(alpha: 0.35), blurRadius: 20, spreadRadius: 3)],
            ),
            child: const Icon(Icons.call_end_rounded, color: _nWhite, size: 34),
          ),
        ),

        const SizedBox(height: 48),
      ],
    );
  }

  // ── 3×2 control button grid ─────────────────────────────────────────────
  Widget _buildControlGrid() {
    final buttons = [
      _NBtn(icon: Icons.mic_off_rounded,     label: 'Mute',     active: _c.isMuted,      onTap: _c.toggleMute),
      _NBtn(icon: Icons.dialpad_rounded,     label: 'Keypad',   active: false,            onTap: _c.toggleKeypad),
      _NBtn(icon: Icons.volume_up_rounded,   label: 'Speaker',  active: _c.isSpeakerOn,  onTap: _c.toggleSpeaker),
      if (_c.callCount >= 2) ...[
        _NBtn(icon: Icons.merge_type_rounded,  label: 'Merge', active: false, onTap: () async {
          _c.mergeCall();
          await Future.delayed(const Duration(milliseconds: 600));
          await _c.updateCallCount();
        }),
        _NBtn(icon: Icons.swap_calls_rounded,  label: 'Swap',  active: false, onTap: _c.swapCall),
        _NBtn(icon: Icons.fiber_manual_record_rounded, label: 'Record', active: _c.isRecording, onTap: _c.toggleRecording),
      ] else ...[
        _NBtn(icon: Icons.add_rounded,         label: 'Add',   active: false, onTap: () => _showAddCallSheet()),
        _NBtn(icon: Icons.pause_rounded,       label: 'Hold',  active: _c.isHold, onTap: _c.toggleHold),
        _NBtn(icon: Icons.fiber_manual_record_rounded, label: 'Record', active: _c.isRecording, onTap: _c.toggleRecording),
      ],
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: buttons.take(3).map(_buildBtn).toList(),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: buttons.skip(3).take(3).map(_buildBtn).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildBtn(_NBtn b) {
    return GestureDetector(
      onTap: b.onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 68, height: 68,
            decoration: BoxDecoration(
              color: b.active ? _nButtonAc : _nButton,
              shape: BoxShape.circle,
            ),
            child: Icon(
              b.icon,
              size: 28,
              color: b.active ? Colors.black : _nWhite,
            ),
          ),
          const SizedBox(height: 8),
          Text(b.label, style: const TextStyle(color: _nLabel, fontSize: 12, fontFamily: _nFont, letterSpacing: 1)),
        ],
      ),
    );
  }

  // ── In-call keypad ──────────────────────────────────────────────────────
  Widget _buildKeypad() {
    const digits = [
      ['1',''], ['2','ABC'], ['3','DEF'],
      ['4','GHI'], ['5','JKL'], ['6','MNO'],
      ['7','PQRS'], ['8','TUV'], ['9','WXYZ'],
      ['*',''], ['0','+'], ['#',''],
    ];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            _c.dtmfInput.isEmpty ? ' ' : _c.dtmfInput,
            style: const TextStyle(fontSize: 28, color: _nWhite, fontFamily: _nFont, letterSpacing: 3),
            maxLines: 1, overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(
            children: List.generate(4, (row) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(3, (col) {
                  final d = digits[row * 3 + col];
                  return GestureDetector(
                    onTap: () => _c.onDigitPressed(d[0]),
                    child: Container(
                      width: 68, height: 68,
                      decoration: const BoxDecoration(color: _nButton, shape: BoxShape.circle),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(d[0], style: const TextStyle(fontSize: 26, color: _nWhite, fontFamily: _nFont)),
                        if (d[1].isNotEmpty) Text(d[1], style: const TextStyle(fontSize: 9, color: _nLabel, fontFamily: _nFont, letterSpacing: 2)),
                      ]),
                    ),
                  );
                }),
              ),
            )),
          ),
        ),
        GestureDetector(
          onTap: _c.toggleKeypad,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('Hide', style: TextStyle(color: _nLabel, fontSize: 16, fontFamily: _nFont, letterSpacing: 1)),
          ),
        ),
      ],
    );
  }

  void _showAddCallSheet() async {
    if (!_c.isHold) {
      _c.toggleHold();
      await Future.delayed(const Duration(milliseconds: 300));
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: _nCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              ListTile(
                leading: const Icon(Icons.dialpad_rounded, color: _nWhite),
                title: const Text('Dial a number', style: TextStyle(color: _nWhite, fontFamily: _nFont)),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const DialpadScreen()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.contacts_rounded, color: _nWhite),
                title: const Text('Choose from contacts', style: TextStyle(color: _nWhite, fontFamily: _nFont)),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => _AddCallContactPicker(
                      onNumberSelected: (num) => TelecomService.handleOutgoingCall(context, num),
                    ),
                  ));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Main build ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isIncoming = _c.callState == 2;
    final isEnded    = _c.callState == 7;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        ProximitySensor.setProximityScreenOff(false);
        if (_c.callState == 7) {
          if (widget.exitOnEnd) {
            SystemNavigator.pop();
          } else if (Navigator.canPop(context)) {
            Navigator.pop(context, _c.dtmfInput);
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
        backgroundColor: _nBg,
        resizeToAvoidBottomInset: false,
        body: isIncoming
            ? SafeArea(child: _buildIncomingScreen())
            : AnimatedBuilder(
                animation: _heroProgress,
                builder: (_, __) {
                  // Fade/slide transition from full-bg to compact
                  return SafeArea(
                    child: Opacity(
                      opacity: _heroProgress.value,
                      child: Transform.translate(
                        offset: Offset(0, 40 * (1 - _heroProgress.value)),
                        child: Column(
                          children: [
                            Expanded(
                              child: isEnded
                                  ? _buildEndedOverlay()
                                  : _buildActiveScreen(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildEndedOverlay() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _avatar(size: 80),
          const SizedBox(height: 24),
          Text(
            (_c.name ?? _c.number).toUpperCase(),
            style: const TextStyle(fontFamily: _nFont, fontSize: 22, color: _nWhite, letterSpacing: 2),
          ),
          const SizedBox(height: 12),
          const Text('CALL ENDED', style: TextStyle(fontFamily: _nFont, fontSize: 14, color: _nLabel, letterSpacing: 3)),
        ],
      ),
    );
  }
}

// ── Nothing-style animated dot-matrix waveform ───────────────────────────────
class _NothingWaveform extends StatefulWidget {
  const _NothingWaveform();
  @override
  State<_NothingWaveform> createState() => _NothingWaveformState();
}

class _NothingWaveformState extends State<_NothingWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  // Relative heights (0.0–1.0) for each bar column. Vary each bar differently.
  static const _phases = [0.0, 0.3, 0.6, 0.15, 0.45, 0.75, 0.2, 0.5, 0.8,
                           0.05, 0.35, 0.65, 0.9, 0.25, 0.55];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  double _barHeight(int index, double t) {
    // Each bar oscillates at its own phase offset
    final phase = _phases[index % _phases.length];
    final v = (t + phase) % 1.0;
    // Sine-like using triangle wave for a choppier dot-matrix look
    final tri = v < 0.5 ? v * 2 : (1.0 - v) * 2;
    return 0.15 + tri * 0.85;
  }

  @override
  Widget build(BuildContext context) {
    const barCount = 22;
    const barW = 3.0;
    const barSpacing = 5.0;
    const maxBarH = 52.0;
    const dotSize = 3.0;
    const dotGap = 1.5;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return SizedBox(
          height: maxBarH,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(barCount, (i) {
              final h = _barHeight(i, _ctrl.value) * maxBarH;
              final dotCount = (h / (dotSize + dotGap)).floor().clamp(1, 12);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: barSpacing / 2),
                child: SizedBox(
                  width: barW,
                  height: maxBarH,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(dotCount, (_) => Padding(
                      padding: EdgeInsets.only(bottom: dotGap),
                      child: Container(
                        width: barW,
                        height: dotSize,
                        decoration: BoxDecoration(
                          color: _nWhite.withValues(alpha: 0.18 + 0.12 * (dotCount / 12)),
                          borderRadius: BorderRadius.circular(1.5),
                        ),
                      ),
                    )),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

// ── Blinking "active" timer display ─────────────────────────────────────────
class _TimerDisplay extends StatefulWidget {
  final String timerText;
  const _TimerDisplay({required this.timerText});
  @override
  State<_TimerDisplay> createState() => _TimerDisplayState();
}
class _TimerDisplayState extends State<_TimerDisplay> with SingleTickerProviderStateMixin {
  late final AnimationController _blink;
  @override
  void initState() {
    super.initState();
    _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  }
  @override
  void dispose() { _blink.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _blink,
      builder: (_, __) => Text(
        widget.timerText,
        style: TextStyle(
          fontFamily: _nFont,
          fontSize: 14,
          color: _nLabel.withValues(alpha: 0.5 + 0.5 * _blink.value),
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

// ── Helper data class ─────────────────────────────────────────────────────
class _NBtn {
  final IconData icon;
  final String   label;
  final bool     active;
  final VoidCallback onTap;
  const _NBtn({required this.icon, required this.label, required this.active, required this.onTap});
}

// ── Add-call contact picker ──────────────────────────────────────────────
class _AddCallContactPicker extends StatefulWidget {
  final void Function(String number) onNumberSelected;
  const _AddCallContactPicker({required this.onNumberSelected});
  @override
  State<_AddCallContactPicker> createState() => _AddCallContactPickerState();
}

class _AddCallContactPickerState extends State<_AddCallContactPicker> {
  List<Contact> _contacts = [];
  List<Contact> _filtered = [];
  final TextEditingController _search = TextEditingController();
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (await Permission.contacts.isGranted) {
      final all = await FlutterContacts.getAll(properties: {ContactProperty.phone});
      all.sort((a, b) => (a.displayName ?? '').compareTo(b.displayName ?? ''));
      if (mounted) setState(() {
        _contacts = all.where((c) => c.phones.isNotEmpty).toList();
        _filtered  = _contacts;
        _loading   = false;
      });
    } else {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _filter(String q) {
    final lq = q.toLowerCase();
    setState(() {
      _filtered = _contacts.where((c) {
        final name = (c.displayName ?? '').toLowerCase();
        final nums = c.phones.any((p) => p.number.replaceAll(RegExp(r'\D'), '').contains(lq));
        return name.contains(lq) || nums;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _nBg,
      appBar: AppBar(
        backgroundColor: _nCard,
        title: const Text('SELECT CONTACT', style: TextStyle(color: _nWhite, fontFamily: _nFont, letterSpacing: 2, fontSize: 16)),
        iconTheme: const IconThemeData(color: _nWhite),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _search,
              onChanged: _filter,
              style: const TextStyle(color: _nWhite, fontFamily: _nFont),
              decoration: InputDecoration(
                hintText: 'Search',
                hintStyle: const TextStyle(color: _nLabel, fontFamily: _nFont),
                prefixIcon: const Icon(Icons.search, color: _nLabel),
                filled: true,
                fillColor: const Color(0xFF2A2A2A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _nWhite))
          : _filtered.isEmpty
              ? const Center(child: Text('No contacts', style: TextStyle(color: _nLabel, fontFamily: _nFont)))
              : ListView.builder(
                  itemCount: _filtered.length,
                  itemBuilder: (ctx, i) {
                    final c   = _filtered[i];
                    final num = c.phones.first.number;
                    final dn  = c.displayName?.isNotEmpty == true ? c.displayName! : num;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF2C2C2C),
                        child: Text(dn[0].toUpperCase(), style: const TextStyle(color: _nWhite, fontFamily: _nFont)),
                      ),
                      title: Text(dn, style: const TextStyle(color: _nWhite, fontFamily: _nFont)),
                      subtitle: Text(num, style: const TextStyle(color: _nLabel, fontSize: 13, fontFamily: _nFont)),
                      trailing: const Icon(Icons.call_rounded, color: _nGreen, size: 22),
                      onTap: () {
                        Navigator.pop(context);
                        widget.onNumberSelected(num);
                      },
                    );
                  },
                ),
    );
  }
}
