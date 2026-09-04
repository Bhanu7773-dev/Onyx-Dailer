import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavedialer/logic/dialpad_controller.dart';
import 'package:wavedialer/services/telecom_service.dart';

// iOS colors
const _bg         = Color(0xFF000000);
const _iosBlue    = Color(0xFF007AFF);
const _iosGreen   = Color(0xFF34C759);
const _iosLabel   = Color(0xFFFFFFFF);
const _iosSecondary = Color(0xFF8E8E93);
const _keyBg      = Color(0xFF2C2C2E);   // button background
const _keyBgPressed = Color(0xFF48484A); // pressed state

double _getOnyxFontSize(int length) {
  if (length <= 7) return 40;
  if (length <= 10) return 32;
  if (length <= 13) return 26;
  if (length <= 16) return 21;
  return 17;
}

double _getOnyxLetterSpacing(int length) {
  if (length <= 7) return 2.0;
  if (length <= 10) return 1.2;
  if (length <= 13) return 0.6;
  return 0.0;
}

class DialpadScreen extends StatefulWidget {
  const DialpadScreen({super.key});

  @override
  State<DialpadScreen> createState() => _DialpadScreenState();
}

class _DialpadScreenState extends State<DialpadScreen> {
  final DialpadController _controller = DialpadController();
  List<Map<String, String>> _simCards = [];
  String _defaultSim = 'ask';

  @override
  void initState() {
    super.initState();
    _controller.init();
    _controller.addListener(_onControllerChange);
    _loadSimCards();
  }

  Future<void> _loadSimCards() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload(); // Ensure fresh values from disk
      final sims = await TelecomService.getSimCards();
      final defSim = prefs.getString('default_sim') ?? 'ask';
      debugPrint('DialpadScreen: sims=${sims.length}, defaultSim=$defSim, simulate=${prefs.getBool('simulate_dual_sim')}');
      if (mounted) {
        setState(() {
          _simCards = sims;
          _defaultSim = defSim;
        });
      }
    } catch (_) {}
  }

  Future<void> _handleCall({String? simId}) async {
    await _controller.call(context, null, simId);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChange);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: _bg,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Column(
            children: [
              // Close handle
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 4),
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                      color: _iosSecondary.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),

              // Contact suggestions
              Expanded(
                child: ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white, Colors.white, Colors.transparent],
                    stops: [0.0, 0.6, 1.0],
                  ).createShader(bounds),
                  blendMode: BlendMode.dstIn,
                  child: _controller.suggestedContacts.isEmpty
                      ? _controller.number.isNotEmpty
                          ? _contactActions()
                          : const SizedBox()
                      : _suggestionList(),
                ),
              ),

              // Matched contact name banner (if contact found)
              if (_controller.number.isNotEmpty && _controller.matchedContact != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6, left: 24, right: 24),
                  child: Text(
                    _controller.matchedContact!.displayName ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: _iosSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),

              // Number display
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    if (_controller.number.isNotEmpty)
                      const SizedBox(width: 36)
                    else
                      const SizedBox.shrink(),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.center,
                        child: Text(
                          _controller.number,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: _getOnyxFontSize(_controller.number.length),
                            fontWeight: FontWeight.w300,
                            color: _iosLabel,
                            letterSpacing: _getOnyxLetterSpacing(_controller.number.length),
                          ),
                        ),
                      ),
                    ),
                    if (_controller.number.isNotEmpty)
                      GestureDetector(
                        onTap: _controller.delete,
                        onLongPress: _controller.clearAll,
                        child: const SizedBox(
                          width: 36,
                          child: Center(
                            child: Icon(Icons.backspace_outlined,
                                color: _iosSecondary, size: 26),
                          ),
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Keypad grid
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    _keyRow([
                      ('1', ''),
                      ('2', 'ABC'),
                      ('3', 'DEF'),
                    ]),
                    _keyRow([
                      ('4', 'GHI'),
                      ('5', 'JKL'),
                      ('6', 'MNO'),
                    ]),
                    _keyRow([
                      ('7', 'PQRS'),
                      ('8', 'TUV'),
                      ('9', 'WXYZ'),
                    ]),
                    _keyRow([
                      ('*', ''),
                      ('0', '+'),
                      ('#', ''),
                    ]),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Call button row
              SizedBox(
                height: 80,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Unified Split Capsule Pill if dual SIM and 'ask', otherwise classic call button
                    _simCards.length >= 2 && _defaultSim == 'ask'
                        ? _OnyxDualSimCapsuleButton(
                            sim1: _simCards[0],
                            sim2: _simCards[1],
                            onCallSim1: () => _handleCall(simId: _simCards[0]['id']),
                            onCallSim2: () => _handleCall(simId: _simCards[1]['id']),
                          )
                        : _CallButton(onTap: () => _handleCall()),
                  ],
                ),
              ),

              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  Widget _keyRow(List<(String, String)> keys) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: keys.map((k) => _DialKey(digit: k.$1, letters: k.$2, onTap: (d) => _controller.press(d, context))).toList(),
      ),
    );
  }

  Widget _suggestionList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: _controller.suggestedContacts.length,
      itemBuilder: (ctx, i) {
        final c = _controller.suggestedContacts[i];
        final phone = c.phones.isNotEmpty ? c.phones.first.number : '';
        final initial = (c.displayName != null && c.displayName!.isNotEmpty)
            ? c.displayName![0].toUpperCase()
            : '#';
        return GestureDetector(
          onTap: () => _controller.call(context, phone),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFF48484A),
                  backgroundImage: c.photo?.thumbnail != null
                      ? MemoryImage(c.photo!.thumbnail!)
                      : null,
                  child: c.photo?.thumbnail == null
                      ? Text(initial,
                          style: const TextStyle(
                              color: _iosLabel, fontSize: 16, fontWeight: FontWeight.w500))
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.displayName ?? 'Unknown',
                          style: const TextStyle(
                              color: _iosLabel, fontSize: 16, fontWeight: FontWeight.w500)),
                      if (phone.isNotEmpty)
                        Text(phone,
                            style: const TextStyle(color: _iosSecondary, fontSize: 13)),
                    ],
                  ),
                ),
                const Icon(Icons.call_rounded, color: _iosGreen, size: 22),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _contactActions() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      children: [
        _actionTile(Icons.person_add_outlined, 'Create new contact', () async {
          final c = Contact(phones: [Phone(number: _controller.number)]);
          await FlutterContacts.native.showCreator(contact: c);
          _controller.fetchContacts();
        }),
        const SizedBox(height: 8),
        _actionTile(Icons.group_add_outlined, 'Add to existing contact', () async {
          final id = await FlutterContacts.native.showPicker();
          if (id != null) {
            final c = await FlutterContacts.get(id, properties: {ContactProperty.phone});
            if (c != null && mounted) {
              c.phones.add(Phone(number: _controller.number));
              await FlutterContacts.update(c);
              _controller.fetchContacts();
            }
          }
        }),
      ],
    );
  }

  Widget _actionTile(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: _iosBlue, size: 20),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(color: _iosBlue, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}

// Individual dial key

class _DialKey extends StatefulWidget {
  final String digit;
  final String letters;
  final void Function(String) onTap;

  const _DialKey({required this.digit, required this.letters, required this.onTap});

  @override
  State<_DialKey> createState() => _DialKeyState();
}

class _DialKeyState extends State<_DialKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap(widget.digit);
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: _pressed ? _keyBgPressed : _keyBg,
          shape: BoxShape.circle,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              widget.digit,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w300,
                color: _iosLabel,
                height: 1.1,
              ),
            ),
            if (widget.letters.isNotEmpty)
              Text(
                widget.letters,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _iosSecondary,
                  letterSpacing: 1.2,
                  height: 1.0,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Green call button

class _CallButton extends StatefulWidget {
  final Future<void> Function() onTap;
  const _CallButton({required this.onTap});

  @override
  State<_CallButton> createState() => _CallButtonState();
}

class _CallButtonState extends State<_CallButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: _pressed
              ? _iosGreen.withValues(alpha: 0.75)
              : _iosGreen,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: _iosGreen.withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Icon(Icons.call_rounded, color: Colors.white, size: 32),
      ),
    );
  }
}

// ── Unified Split Capsule Pill (Dual SIM - Onyx) ────────────────────────────

class _OnyxDualSimCapsuleButton extends StatefulWidget {
  final Map<String, String> sim1;
  final Map<String, String> sim2;
  final Future<void> Function() onCallSim1;
  final Future<void> Function() onCallSim2;

  const _OnyxDualSimCapsuleButton({
    required this.sim1,
    required this.sim2,
    required this.onCallSim1,
    required this.onCallSim2,
  });

  @override
  State<_OnyxDualSimCapsuleButton> createState() => _OnyxDualSimCapsuleButtonState();
}

class _OnyxDualSimCapsuleButtonState extends State<_OnyxDualSimCapsuleButton> {
  bool _sim1Pressed = false;
  bool _sim2Pressed = false;

  String _cleanLabel(String? raw, String fallback) {
    if (raw == null || raw.trim().isEmpty) return fallback;
    final clean = raw.trim().toUpperCase();
    if (clean.length > 7) return clean.substring(0, 7);
    return clean;
  }

  @override
  Widget build(BuildContext context) {
    final label1 = _cleanLabel(widget.sim1['label'], 'SIM 1');
    final label2 = _cleanLabel(widget.sim2['label'], 'SIM 2');

    return Container(
      width: 176,
      height: 72,
      decoration: BoxDecoration(
        color: _iosGreen,
        borderRadius: BorderRadius.circular(36),
        boxShadow: [
          BoxShadow(
            color: _iosGreen.withValues(alpha: 0.40),
            blurRadius: 22,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(36),
        child: Row(
          children: [
            // SIM 1 Half
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (_) => setState(() => _sim1Pressed = true),
                onTapUp: (_) {
                  setState(() => _sim1Pressed = false);
                  widget.onCallSim1();
                },
                onTapCancel: () => setState(() => _sim1Pressed = false),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 70),
                  color: _sim1Pressed
                      ? Colors.black.withValues(alpha: 0.18)
                      : Colors.transparent,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.call_rounded, color: Colors.white, size: 20),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              '1',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        label1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Vertical hairline divider
            Container(
              width: 1.2,
              height: 42,
              color: Colors.white.withValues(alpha: 0.28),
            ),

            // SIM 2 Half
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (_) => setState(() => _sim2Pressed = true),
                onTapUp: (_) {
                  setState(() => _sim2Pressed = false);
                  widget.onCallSim2();
                },
                onTapCancel: () => setState(() => _sim2Pressed = false),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 70),
                  color: _sim2Pressed
                      ? Colors.black.withValues(alpha: 0.18)
                      : Colors.transparent,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.call_rounded, color: Colors.white, size: 20),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              '2',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        label2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
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
