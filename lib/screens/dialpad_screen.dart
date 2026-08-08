import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wavedialer/services/telecom_service.dart';
import 'package:wavedialer/screens/call_screen.dart';

// iOS colors
const _bg         = Color(0xFF000000);
const _iosBlue    = Color(0xFF007AFF);
const _iosGreen   = Color(0xFF34C759);
const _iosLabel   = Color(0xFFFFFFFF);
const _iosSecondary = Color(0xFF8E8E93);
const _keyBg      = Color(0xFF2C2C2E);   // button background
const _keyBgPressed = Color(0xFF48484A); // pressed state

class DialpadScreen extends StatefulWidget {
  const DialpadScreen({super.key});

  @override
  State<DialpadScreen> createState() => _DialpadScreenState();
}

class _DialpadScreenState extends State<DialpadScreen> {
  String _number = '';
  List<Contact> _allContacts = [];
  List<Contact> _suggestedContacts = [];

  @override
  void initState() {
    super.initState();
    _fetchContacts();
  }

  Future<void> _fetchContacts() async {
    if (await Permission.contacts.isGranted) {
      final contacts = await FlutterContacts.getAll(
          properties: {ContactProperty.phone});
      if (mounted) setState(() => _allContacts = contacts);
    }
  }

  String _nameToT9(String name) {
    const map = {
      'A':'2','B':'2','C':'2','D':'3','E':'3','F':'3',
      'G':'4','H':'4','I':'4','J':'5','K':'5','L':'5',
      'M':'6','N':'6','O':'6','P':'7','Q':'7','R':'7','S':'7',
      'T':'8','U':'8','V':'8','W':'9','X':'9','Y':'9','Z':'9',
    };
    return name.toUpperCase().split('').map((c) => map[c] ?? '').join();
  }

  void _updateSuggestions() {
    if (_number.isEmpty) { _suggestedContacts = []; return; }
    _suggestedContacts = _allContacts.where((c) {
      final t9 = _nameToT9(c.displayName ?? '');
      final phoneMatch = c.phones.any((p) =>
          p.number.replaceAll(RegExp(r'\D'), '').contains(_number));
      return t9.contains(_number) || phoneMatch;
    }).toList();
  }

  void _press(String digit) {
    HapticFeedback.lightImpact();
    TelecomService.playLocalDtmf(digit);
    setState(() {
      _number += digit;
      _updateSuggestions();
    });
  }

  void _delete() {
    if (_number.isNotEmpty) {
      HapticFeedback.lightImpact();
      setState(() {
        _number = _number.substring(0, _number.length - 1);
        _updateSuggestions();
      });
    }
  }

  void _clearAll() {
    HapticFeedback.mediumImpact();
    setState(() { _number = ''; _suggestedContacts = []; });
  }

  Future<void> _call([String? num]) async {
    final target = num ?? _number;
    if (target.isEmpty) return;
    HapticFeedback.heavyImpact();
    TelecomService.handleOutgoingCall(context, target);
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
                  child: _suggestedContacts.isEmpty
                      ? _number.isNotEmpty
                          ? _contactActions()
                          : const SizedBox()
                      : _suggestionList(),
                ),
              ),

              // Number display
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        _number,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.w300,
                          color: _iosLabel,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    if (_number.isNotEmpty)
                      GestureDetector(
                        onTap: _delete,
                        onLongPress: _clearAll,
                        child: const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(Icons.backspace_outlined,
                              color: _iosSecondary, size: 26),
                        ),
                      ),
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
                    // Green call button (centred)
                    _CallButton(onTap: _call),
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
        children: keys.map((k) => _DialKey(digit: k.$1, letters: k.$2, onTap: _press)).toList(),
      ),
    );
  }

  Widget _suggestionList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: _suggestedContacts.length,
      itemBuilder: (ctx, i) {
        final c = _suggestedContacts[i];
        final phone = c.phones.isNotEmpty ? c.phones.first.number : '';
        final initial = (c.displayName?.isNotEmpty == true)
            ? c.displayName![0].toUpperCase()
            : '#';
        return GestureDetector(
          onTap: () => _call(phone),
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
                  child: Text(initial,
                      style: const TextStyle(
                          color: _iosLabel, fontSize: 16, fontWeight: FontWeight.w500)),
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
          final c = Contact(phones: [Phone(number: _number)]);
          await FlutterContacts.native.showCreator(contact: c);
          _fetchContacts();
        }),
        const SizedBox(height: 8),
        _actionTile(Icons.group_add_outlined, 'Add to existing contact', () async {
          final id = await FlutterContacts.native.showPicker();
          if (id != null) {
            final c = await FlutterContacts.get(id, properties: {ContactProperty.phone});
            if (c != null && mounted) {
              c.phones.add(Phone(number: _number));
              await FlutterContacts.update(c);
              _fetchContacts();
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
