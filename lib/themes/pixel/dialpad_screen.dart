// Pixel dialpad screen
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavedialer/logic/dialpad_controller.dart';
import 'package:wavedialer/services/telecom_service.dart';

// ── Pixel Material 3 Expressive Palette ───────────────────────────────────────
const _kBg = Color(0xFF0B0F14);
const _kCardBg = Color(0xFF10151C);
const _kAvatarBg = Color(0xFF1C232E);
const _kButtonBg = Color(0xFF1A222D);
const _kKeyBg = Color(0xFF121720);
const _kKeyPressed = Color(0xFF223145);

const _kBlueAccent = Color(0xFF5B9DFF);
const _kCallButtonBg = Color(0xFF8AB4F8);
const _kCallIconColor = Color(0xFF09182C);
const _kTextWhite = Color(0xFFFFFFFF);
const _kTextMuted = Color(0xFF8E9CAE);
const _kSeparator = Color(0xFF1E2836);
const _kHandleColor = Color(0xFF2C3440);

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
      await prefs.reload();
      final sims = await TelecomService.getSimCards();
      final defSim = prefs.getString('default_sim') ?? 'ask';
      if (mounted) {
        setState(() {
          _simCards = sims;
          _defaultSim = defSim;
        });
      }
    } catch (_) {}
  }

  Future<void> _handleCall({String? directNumber}) async {
    final simId = (_simCards.length >= 2 && _defaultSim != 'ask') ? _defaultSim : null;
    if (_controller.number.isEmpty && directNumber == null) {
      await _controller.fillLastCalledNumber();
      return;
    }
    await _controller.call(context, directNumber, simId);
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

  double _getFontSize(int length) {
    if (length <= 5) return 46;
    if (length <= 8) return 40;
    if (length <= 11) return 32;
    if (length <= 14) return 26;
    if (length <= 17) return 22;
    return 18;
  }

  Widget _buildHighlightedPhone(String phone, String query) {
    final cleanQuery = query.replaceAll(RegExp(r'\D'), '');
    if (cleanQuery.isEmpty) {
      return Text(phone, style: const TextStyle(color: _kTextMuted, fontSize: 13));
    }

    // Direct substring check
    if (phone.contains(query)) {
      final idx = phone.indexOf(query);
      return Text.rich(
        TextSpan(
          style: const TextStyle(color: _kTextMuted, fontSize: 13),
          children: [
            TextSpan(text: phone.substring(0, idx)),
            TextSpan(
              text: phone.substring(idx, idx + query.length),
              style: const TextStyle(color: _kBlueAccent, fontWeight: FontWeight.bold),
            ),
            TextSpan(text: phone.substring(idx + query.length)),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    // Match on normalized digits
    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    final matchStart = cleanPhone.indexOf(cleanQuery);
    if (matchStart != -1) {
      // Find start and end indices in the original phone string
      int digitCount = 0;
      int charStart = -1;
      int charEnd = -1;

      for (int i = 0; i < phone.length; i++) {
        if (RegExp(r'\d').hasMatch(phone[i])) {
          if (digitCount == matchStart && charStart == -1) {
            charStart = i;
          }
          if (digitCount == matchStart + cleanQuery.length - 1) {
            charEnd = i + 1;
            break;
          }
          digitCount++;
        }
      }

      if (charStart != -1 && charEnd != -1 && charEnd <= phone.length) {
        return Text.rich(
          TextSpan(
            style: const TextStyle(color: _kTextMuted, fontSize: 13),
            children: [
              TextSpan(text: phone.substring(0, charStart)),
              TextSpan(
                text: phone.substring(charStart, charEnd),
                style: const TextStyle(color: _kBlueAccent, fontWeight: FontWeight.bold),
              ),
              TextSpan(text: phone.substring(charEnd)),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      }
    }

    return Text(phone, style: const TextStyle(color: _kTextMuted, fontSize: 13));
  }

  @override
  Widget build(BuildContext context) {
    final number = _controller.number;
    final matchedName = _controller.matchedContact?.displayName ?? '';
    final suggestions = _controller.suggestedContacts;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: _kBg,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _kBg,
        body: SafeArea(
          child: Column(
            children: [
              // Top drag handle
              GestureDetector(
                onTap: () => Navigator.pop(context),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: _kHandleColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),

              // ── Top T9 Suggestions Card (if any matches) ──────────────────
              if (number.isNotEmpty && suggestions.isNotEmpty)
                _buildSuggestionsCard(suggestions)
              else
                const SizedBox(height: 12),

              const Spacer(),

              // ── Matched Contact Name & Number Display ─────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    // Matched Name (if contact is identified)
                    if (number.isNotEmpty && matchedName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          matchedName,
                          style: const TextStyle(
                            color: _kTextMuted,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      )
                    else if (number.isEmpty)
                      const SizedBox(height: 22),

                    // Number Display with Backspace Icon
                    Row(
                      children: [
                        const SizedBox(width: 44), // balance backspace
                        Expanded(
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                number.isEmpty ? '' : number,
                                style: TextStyle(
                                  color: _kTextWhite,
                                  fontSize: _getFontSize(number.length),
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Backspace button
                        SizedBox(
                          width: 44,
                          child: number.isNotEmpty
                              ? GestureDetector(
                                  onTap: () => _controller.delete(),
                                  onLongPress: () => _controller.clearAll(),
                                  child: const Icon(
                                    Icons.backspace_outlined,
                                    color: _kTextWhite,
                                    size: 24,
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Keypad Grid (3x4) ─────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    _buildKeyRow(['1', '2', '3'], ['', 'ABC', 'DEF']),
                    const SizedBox(height: 14),
                    _buildKeyRow(['4', '5', '6'], ['GHI', 'JKL', 'MNO']),
                    const SizedBox(height: 14),
                    _buildKeyRow(['7', '8', '9'], ['PQRS', 'TUV', 'WXYZ']),
                    const SizedBox(height: 14),
                    _buildKeyRow(['*', '0', '#'], ['', '+', '']),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // ── Bottom Call Button ────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Center(
                  child: GestureDetector(
                    onTap: () => _handleCall(),
                    child: Container(
                      width: 82,
                      height: 82,
                      decoration: BoxDecoration(
                        color: _kCallButtonBg,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _kCallButtonBg.withValues(alpha: 0.35),
                            blurRadius: 24,
                            spreadRadius: 2,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.call_rounded,
                          color: _kCallIconColor,
                          size: 34,
                        ),
                      ),
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

  // ── Suggestions Card ──────────────────────────────────────────────────────
  Widget _buildSuggestionsCard(List<Contact> suggestions) {
    final displayItems = suggestions.take(3).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: displayItems.length,
        separatorBuilder: (_, _) => const Divider(color: _kSeparator, height: 1, indent: 64, endIndent: 16),
        itemBuilder: (context, index) {
          final contact = displayItems[index];
          final name = contact.displayName ?? 'Unknown';
          final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
          final phone = contact.phones.isNotEmpty ? contact.phones.first.number : '';

          return InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              if (phone.isNotEmpty) {
                _handleCall(directNumber: phone);
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  // Initial Avatar
                  Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(
                      color: _kAvatarBg,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: _kTextWhite,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 14),

                  // Contact Name & Highlighted Phone
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            color: _kTextWhite,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        _buildHighlightedPhone(phone, _controller.number),
                      ],
                    ),
                  ),

                  // Call Action Button
                  GestureDetector(
                    onTap: () {
                      if (phone.isNotEmpty) {
                        _handleCall(directNumber: phone);
                      }
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: _kButtonBg,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.call_outlined,
                        color: Color(0xFFC5D2E0),
                        size: 19,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Keypad Grid Rows & Keys ───────────────────────────────────────────────
  Widget _buildKeyRow(List<String> digits, List<String> letters) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(3, (i) {
        return _PixelDialKey(
          digit: digits[i],
          letters: letters[i],
          onTap: () => _controller.press(digits[i], context),
          onLongPress: digits[i] == '0'
              ? () {
                  HapticFeedback.mediumImpact();
                  _controller.press('+', context);
                }
              : null,
        );
      }),
    );
  }
}

class _PixelDialKey extends StatefulWidget {
  final String digit;
  final String letters;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _PixelDialKey({
    required this.digit,
    required this.letters,
    required this.onTap,
    this.onLongPress,
  });

  @override
  State<_PixelDialKey> createState() => _PixelDialKeyState();
}

class _PixelDialKeyState extends State<_PixelDialKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: 82,
        height: 82,
        decoration: BoxDecoration(
          color: _pressed ? _kKeyPressed : _kKeyBg,
          shape: BoxShape.circle,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              widget.digit,
              style: TextStyle(
                color: _kTextWhite,
                fontSize: widget.digit == '*' || widget.digit == '#' ? 34 : 32,
                fontWeight: FontWeight.bold,
                height: 1.1,
              ),
            ),
            if (widget.letters.isNotEmpty)
              Text(
                widget.letters,
                style: const TextStyle(
                  color: _kTextMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
