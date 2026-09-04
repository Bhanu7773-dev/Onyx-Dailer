import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavedialer/logic/dialpad_controller.dart';
import 'package:wavedialer/services/telecom_service.dart';
import 'package:wavedialer/themes/nothing/call_screen.dart' as nothing_call;
import 'package:wavedialer/logic/theme_controller.dart' as tc;

String get _nFont => tc.ThemeController.instance.nothingFontFamily;

// Nothing Phone UI palette
const _bg          = Color(0xFF000000);
const _nLabel      = Color(0xFFFFFFFF);
const _nSecondary  = Color(0xFF888888);
const _nKeyBg      = Color(0xFF1A1A1A);
const _nKeyPressed = Color(0xFF2E2E2E);
const _nRed        = Color(0xFFE5162A);
const _nDivider    = Color(0xFF222222);

double _getNothingFontSize(int length) {
  if (length <= 7) return 36;
  if (length <= 10) return 30;
  if (length <= 13) return 24;
  if (length <= 16) return 20;
  return 16;
}

double _getNothingLetterSpacing(int length) {
  if (length <= 7) return 3.5;
  if (length <= 10) return 2.0;
  if (length <= 13) return 1.0;
  if (length <= 16) return 0.5;
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
      debugPrint('DialpadScreen(Nothing): sims=${sims.length}, defaultSim=$defSim, simulate=${prefs.getBool('simulate_dual_sim')}');
      if (mounted) {
        setState(() {
          _simCards = sims;
          _defaultSim = defSim;
        });
      }
    } catch (_) {}
  }

  Future<void> _handleCall({String? simId}) async {
    if (_controller.number.isEmpty) {
      await _controller.fillLastCalledNumber();
      return;
    }
    final number = _controller.number;
    final nav = Navigator.of(context);
    final called = await _controller.call(context, null, simId);
    if (!called || !mounted) return;
    nav.pushReplacement(
      MaterialPageRoute(
        builder: (_) => nothing_call.CallScreen(
          initialNumber: number,
          initialState: 1, // Dialing
          exitOnEnd: false,
        ),
      ),
    );
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
              // Drag handle
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 6),
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                      color: _nSecondary.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),

              // Contact suggestions / actions
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
                    (_controller.matchedContact!.displayName ?? '').toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _nSecondary,
                      letterSpacing: 1.5,
                      fontFamily: _nFont,
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
                          _controller.number.isEmpty ? '' : _controller.number,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: _getNothingFontSize(_controller.number.length),
                            fontWeight: FontWeight.w300,
                            color: _nLabel,
                            letterSpacing: _getNothingLetterSpacing(_controller.number.length),
                            fontFamily: _nFont,
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
                                color: _nSecondary, size: 24),
                          ),
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                  ],
                ),
              ),

              // "Add contact" hint
              if (_controller.number.isNotEmpty && _controller.suggestedContacts.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: GestureDetector(
                    onTap: () async {
                      final c = Contact(phones: [Phone(number: _controller.number)]);
                      await FlutterContacts.native.showCreator(contact: c);
                      _controller.fetchContacts();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: _nRed.withValues(alpha: 0.7), width: 1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Add contact',
                        style: TextStyle(color: _nRed, fontSize: 12, letterSpacing: 0.5),
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 20),

              // Keypad
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    _keyRow([('1', 'QO'), ('2', 'ABC'), ('3', 'DEF')]),
                    _keyRow([('4', 'GHI'), ('5', 'JKL'), ('6', 'MNO')]),
                    _keyRow([('7', 'PQRS'), ('8', 'TUV'), ('9', 'WXYZ')]),
                    _keyRow([('*', ''), ('0', '+'), ('#', '')]),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // Call button row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Recents icon
                    _IconButton(
                      icon: Icons.history_rounded,
                      color: _nSecondary,
                      onTap: () => Navigator.pop(context, 1),
                    ),
                    // Unified Split Capsule Pill if dual SIM and 'ask', otherwise classic call button
                    _simCards.length >= 2 && _defaultSim == 'ask'
                        ? _NothingDualSimCapsuleButton(
                            sim1: _simCards[0],
                            sim2: _simCards[1],
                            onCallSim1: () => _handleCall(simId: _simCards[0]['id']),
                            onCallSim2: () => _handleCall(simId: _simCards[1]['id']),
                          )
                        : _NothingCallButton(onTap: () => _handleCall()),
                    // Contacts icon or Red Backspace button
                    _controller.number.isNotEmpty
                        ? _NothingIconKey(
                            icon: Icons.backspace_outlined,
                            color: _nRed,
                            bgColor: _nRed.withValues(alpha: 0.15),
                            onTap: _controller.delete,
                            onLongPress: _controller.clearAll,
                          )
                        : _IconButton(
                            icon: Icons.contacts_outlined,
                            color: _nSecondary,
                            onTap: () => Navigator.pop(context, 2),
                          ),
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
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: keys.map((k) => _NothingDialKey(
          digit: k.$1,
          letters: k.$2,
          onTap: (d) => _controller.press(d, context),
        )).toList(),
      ),
    );
  }

  Widget _suggestionList() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: _controller.suggestedContacts.length,
      separatorBuilder: (ctx, i) => const Divider(color: _nDivider, height: 1),
      itemBuilder: (ctx, i) {
        final c = _controller.suggestedContacts[i];
        final phone = c.phones.isNotEmpty ? c.phones.first.number : '';
        final initial = (c.displayName != null && c.displayName!.isNotEmpty)
            ? c.displayName![0].toUpperCase()
            : '#';
        return Container(
          color: _bg,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: Row(
              children: [
                // Grayscale avatar
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFF2A2A2A),
                  backgroundImage: c.photo?.thumbnail != null
                      ? MemoryImage(c.photo!.thumbnail!)
                      : null,
                  child: c.photo?.thumbnail == null
                      ? Text(initial, style: const TextStyle(
                          color: _nLabel, fontSize: 15, fontWeight: FontWeight.w600))
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (c.displayName ?? 'Unknown').toUpperCase(),
                        style: const TextStyle(
                          color: _nLabel, fontSize: 13,
                          fontWeight: FontWeight.w700, letterSpacing: 0.8,
                        ),
                      ),
                      if (phone.isNotEmpty)
                        Text(phone, style: const TextStyle(
                            color: _nSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                // CALL pill
                GestureDetector(
                  onTap: () async {
                    final nav = Navigator.of(context);
                    await _controller.call(context, phone);
                    if (!mounted) return;
                    nav.pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => nothing_call.CallScreen(
                          initialNumber: phone,
                          initialState: 1,
                          exitOnEnd: false,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF333333), width: 1),
                    ),
                    child: const Text(
                      'CALL',
                      style: TextStyle(
                        color: _nLabel, fontSize: 12,
                        fontWeight: FontWeight.w700, letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _nKeyBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _nDivider, width: 1),
        ),
        child: Row(
          children: [
            Icon(icon, color: _nRed, size: 20),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(
                color: _nLabel, fontSize: 14, letterSpacing: 0.3)),
          ],
        ),
      ),
    );
  }
}

// ── Nothing Dial Key ─────────────────────────────────────────────────────────

class _NothingDialKey extends StatefulWidget {
  final String digit;
  final String letters;
  final void Function(String) onTap;
  const _NothingDialKey({required this.digit, required this.letters, required this.onTap});

  @override
  State<_NothingDialKey> createState() => _NothingDialKeyState();
}

class _NothingDialKeyState extends State<_NothingDialKey> {
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
        duration: const Duration(milliseconds: 70),
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: _pressed ? _nKeyPressed : _nKeyBg,
          shape: BoxShape.circle,
          border: Border.all(
            color: _pressed ? const Color(0xFF444444) : const Color(0xFF2A2A2A),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              widget.digit,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w300,
                color: _nLabel,
                height: 1.1,
              ),
            ),
            if (widget.letters.isNotEmpty)
              Text(
                widget.letters,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: _nSecondary,
                  letterSpacing: 1.5,
                  height: 1.0,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Icon-only key (backspace) ─────────────────────────────────────────────────

class _NothingIconKey extends StatefulWidget {
  final IconData icon;
  final Color color;
  final Color bgColor;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const _NothingIconKey({
    required this.icon, required this.color,
    required this.bgColor, required this.onTap, this.onLongPress,
  });

  @override
  State<_NothingIconKey> createState() => _NothingIconKeyState();
}

class _NothingIconKeyState extends State<_NothingIconKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onLongPress: widget.onLongPress,
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 70),
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: _pressed ? widget.bgColor.withValues(alpha: 0.25) : widget.bgColor,
          shape: BoxShape.circle,
        ),
        child: Icon(widget.icon, color: widget.color, size: 26),
      ),
    );
  }
}

// ── White Nothing-style call button ──────────────────────────────────────────

class _NothingCallButton extends StatefulWidget {
  final Future<void> Function() onTap;
  const _NothingCallButton({required this.onTap});

  @override
  State<_NothingCallButton> createState() => _NothingCallButtonState();
}

class _NothingCallButtonState extends State<_NothingCallButton> {
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
          color: _pressed ? Colors.grey.shade200 : Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.call_rounded, color: Colors.black, size: 32),
      ),
    );
  }
}

// ── Small icon-only button (recents/contacts) ─────────────────────────────────

class _IconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _IconButton({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 48, height: 72,
        child: Center(child: Icon(icon, color: color, size: 28)),
      ),
    );
  }
}

// ── Unified Split Capsule Pill (Dual SIM) ───────────────────────────────────

class _NothingDualSimCapsuleButton extends StatefulWidget {
  final Map<String, String> sim1;
  final Map<String, String> sim2;
  final Future<void> Function() onCallSim1;
  final Future<void> Function() onCallSim2;

  const _NothingDualSimCapsuleButton({
    required this.sim1,
    required this.sim2,
    required this.onCallSim1,
    required this.onCallSim2,
  });

  @override
  State<_NothingDualSimCapsuleButton> createState() => _NothingDualSimCapsuleButtonState();
}

class _NothingDualSimCapsuleButtonState extends State<_NothingDualSimCapsuleButton> {
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
      width: 172,
      height: 72,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(36),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, 4),
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
                  color: _sim1Pressed ? Colors.grey.shade300 : Colors.white,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.call_rounded, color: Colors.black, size: 20),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '1',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                fontFamily: _nFont,
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
                        style: TextStyle(
                          color: Colors.black87,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                          fontFamily: _nFont,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Subtle vertical micro-divider seam
            Container(
              width: 1.2,
              height: 44,
              color: const Color(0xFFDDDDDD),
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
                  color: _sim2Pressed ? Colors.grey.shade300 : Colors.white,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.call_rounded, color: Colors.black, size: 20),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '2',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                fontFamily: _nFont,
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
                        style: TextStyle(
                          color: Colors.black87,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                          fontFamily: _nFont,
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
