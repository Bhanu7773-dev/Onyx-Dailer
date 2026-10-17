// Pixel contacts screen
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:wavedialer/logic/contacts_controller.dart';
import 'package:wavedialer/widgets/contact_details_sheet.dart';

// ── Pixel Material 3 Expressive Palette ───────────────────────────────────────
const _kBg = Color(0xFF0B0F14);
const _kSearchBg = Color(0xFF11161D);
const _kListContainerBg = Color(0xFF10151C);
const _kAvatarBg = Color(0xFF1C232E);
const _kButtonBg = Color(0xFF1A222D);
const _kAddButtonBg = Color(0xFF18222E);
const _kSeparator = Color(0xFF1B232F);

const _kBlueAccent = Color(0xFF5B9DFF);
const _kFabBlue = Color(0xFF8AB4F8);
const _kTextWhite = Color(0xFFFFFFFF);
const _kTextMuted = Color(0xFF8E9CAE);
const _kAlphabetInactive = Color(0xFF556575);
const _kSearchHint = Color(0xFF6C7C8C);
const _kCoralRed = Color(0xFFFF7769);

const List<String> _kAlphabet = [
  'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
  'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'
];

const double _kHeaderHeight = 40.0;
const double _kContactItemHeight = 62.0;
const double _kSectionGap = 14.0;

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final ContactsController _controller = ContactsController();
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _searchFocus = FocusNode();

  String _activeLetter = 'A';
  bool _isDraggingBar = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChange);
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.fetchContacts();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _searchFocus.dispose();
    _controller.removeListener(_onControllerChange);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChange() {
    if (mounted) setState(() {});
  }

  double _offsetForIndex(int targetIndex) {
    double offset = 0.0;
    for (int i = 0; i < targetIndex && i < _controller.flat.length; i++) {
      final item = _controller.flat[i];
      if (item is String) {
        offset += _kHeaderHeight;
      } else {
        final isLast = i == _controller.flat.length - 1 || _controller.flat[i + 1] is String;
        offset += isLast ? (_kContactItemHeight + _kSectionGap) : _kContactItemHeight;
      }
    }
    return offset;
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients || _controller.flat.isEmpty || _isDraggingBar) return;
    final offset = _scrollCtrl.offset;

    if (offset >= _scrollCtrl.position.maxScrollExtent - 40) {
      final lastLetter = _controller.letters.isNotEmpty ? _controller.letters.last : 'Z';
      if (_activeLetter != lastLetter && mounted) {
        setState(() => _activeLetter = lastLetter);
      }
      return;
    }

    double runningOffset = 0.0;
    String currentLetter = _controller.letters.isNotEmpty ? _controller.letters.first : 'A';

    for (int i = 0; i < _controller.flat.length; i++) {
      final item = _controller.flat[i];
      if (item is String) {
        if (offset >= runningOffset - 20) {
          currentLetter = item;
        } else {
          break;
        }
        runningOffset += _kHeaderHeight;
      } else {
        final isLast = i == _controller.flat.length - 1 || _controller.flat[i + 1] is String;
        runningOffset += isLast ? (_kContactItemHeight + _kSectionGap) : _kContactItemHeight;
      }
    }

    if (currentLetter != _activeLetter && mounted) {
      setState(() => _activeLetter = currentLetter);
    }
  }

  void _handleBarDrag(double localY, double totalHeight, {bool isTap = false}) {
    if (_kAlphabet.isEmpty || totalHeight <= 0) return;
    final letterHeight = totalHeight / _kAlphabet.length;
    final index = (localY / letterHeight).floor().clamp(0, _kAlphabet.length - 1);
    final letter = _kAlphabet[index];

    if (letter != _activeLetter || isTap) {
      HapticFeedback.selectionClick();
      _scrollToLetter(letter, smooth: isTap);
    }
  }

  void _scrollToLetter(String letter, {bool smooth = false}) {
    if (_controller.flat.isEmpty) return;

    int? targetIndex = _controller.letterIndex[letter];
    if (targetIndex == null) {
      final letterIdx = _kAlphabet.indexOf(letter);
      // Search forward for next letter with contacts
      for (int i = letterIdx + 1; i < _kAlphabet.length; i++) {
        if (_controller.letterIndex.containsKey(_kAlphabet[i])) {
          targetIndex = _controller.letterIndex[_kAlphabet[i]];
          break;
        }
      }
      // Search backward if none found forward
      if (targetIndex == null) {
        for (int i = letterIdx - 1; i >= 0; i--) {
          if (_controller.letterIndex.containsKey(_kAlphabet[i])) {
            targetIndex = _controller.letterIndex[_kAlphabet[i]];
            break;
          }
        }
      }
    }

    if (targetIndex == null) return;

    final targetOffset = _offsetForIndex(targetIndex);
    if (_scrollCtrl.hasClients) {
      final max = _scrollCtrl.position.maxScrollExtent;
      final clamped = targetOffset.clamp(0.0, max);
      if (smooth) {
        _scrollCtrl.animateTo(
          clamped,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      } else {
        _scrollCtrl.jumpTo(clamped);
      }
    }

    setState(() => _activeLetter = letter);
  }

  void _dial(String number) {
    _searchFocus.unfocus();
    _controller.dial(context, number);
  }

  void _handleCall(Contact contact) {
    _searchFocus.unfocus();
    if (contact.phones.isEmpty) return;
    if (contact.phones.length == 1) {
      _dial(contact.phones.first.number);
    } else {
      _showNumberPicker(contact);
    }
  }

  void _showNumberPicker(Contact contact) {
    HapticFeedback.lightImpact();
    final displayName = contact.displayName ?? 'Unknown';

    showModalBottomSheet(
      context: context,
      backgroundColor: _kListContainerBg,
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
                    color: _kSeparator,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Call $displayName',
                style: const TextStyle(
                  color: _kTextWhite,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Select which number you want to call.',
                style: TextStyle(color: _kTextMuted, fontSize: 13),
              ),
              const SizedBox(height: 18),

              ...contact.phones.map((p) {
                String label = p.label.label.name.toLowerCase();
                if (label == 'custom' && p.label.customLabel != null) label = p.label.customLabel!;
                if (label.isEmpty) label = 'phone';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      _dial(p.number);
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
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: _kBlueAccent.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.call_rounded, color: _kBlueAccent, size: 20),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  label.toUpperCase(),
                                  style: const TextStyle(
                                    color: _kTextMuted,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  p.number,
                                  style: const TextStyle(
                                    color: _kTextWhite,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.north_east_rounded, color: _kBlueAccent, size: 20),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showNewContactSheet() {
    HapticFeedback.lightImpact();
    final nameCtrl = TextEditingController();
    final phoneCtrls = [TextEditingController()];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kListContainerBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final bottomInset = MediaQuery.of(context).viewInsets.bottom;
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
            child: SingleChildScrollView(
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
                        color: _kSeparator,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'New Contact',
                        style: TextStyle(
                          color: _kTextWhite,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      GestureDetector(
                        onTap: () async {
                          final name = nameCtrl.text.trim();
                          final phones = phoneCtrls
                              .map((c) => c.text.trim())
                              .where((t) => t.isNotEmpty)
                              .map((t) => Phone(number: t))
                              .toList();

                          if (name.isNotEmpty && phones.isNotEmpty) {
                            final newContact = Contact(
                              name: Name(first: name),
                              phones: phones,
                            );
                            await FlutterContacts.create(newContact);
                            if (ctx.mounted) Navigator.pop(ctx);
                            _controller.fetchContacts();
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: _kFabBlue,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Save',
                            style: TextStyle(
                              color: Color(0xFF09182C),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  Container(
                    decoration: BoxDecoration(
                      color: _kAvatarBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: TextField(
                      controller: nameCtrl,
                      autofocus: true,
                      style: const TextStyle(color: _kTextWhite, fontSize: 16),
                      decoration: const InputDecoration(
                        hintText: 'Contact Name',
                        hintStyle: TextStyle(color: _kTextMuted),
                        border: InputBorder.none,
                        icon: Icon(Icons.person_outline_rounded, color: _kBlueAccent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  ...phoneCtrls.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final ctrl = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _kAvatarBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.phone_outlined, color: _kBlueAccent),
                            const SizedBox(width: 14),
                            Expanded(
                              child: TextField(
                                controller: ctrl,
                                keyboardType: TextInputType.phone,
                                style: const TextStyle(color: _kTextWhite, fontSize: 16),
                                decoration: const InputDecoration(
                                  hintText: 'Phone number',
                                  hintStyle: TextStyle(color: _kTextMuted),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            if (phoneCtrls.length > 1)
                              GestureDetector(
                                onTap: () => setSheetState(() => phoneCtrls.removeAt(idx)),
                                child: const Icon(Icons.remove_circle_outline_rounded, color: _kCoralRed, size: 22),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),

                  GestureDetector(
                    onTap: () => setSheetState(() => phoneCtrls.add(TextEditingController())),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      child: Row(
                        children: [
                          Icon(Icons.add_circle_outline_rounded, color: _kBlueAccent, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Add another phone number',
                            style: TextStyle(color: _kBlueAccent, fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                        ],
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

  Future<void> _showEditContactSheet(Contact contact) async {
    HapticFeedback.lightImpact();
    final fullContact = contact.id != null
        ? await FlutterContacts.get(
            contact.id!,
            properties: {ContactProperty.name, ContactProperty.phone},
          )
        : contact;

    if (fullContact == null || !mounted) return;

    final nameCtrl = TextEditingController(text: fullContact.displayName ?? '');
    final phoneCtrls = fullContact.phones.isNotEmpty
        ? fullContact.phones.map((p) => TextEditingController(text: p.number)).toList()
        : [TextEditingController()];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kListContainerBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final bottomInset = MediaQuery.of(context).viewInsets.bottom;
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
            child: SingleChildScrollView(
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
                        color: _kSeparator,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Edit Contact',
                        style: TextStyle(
                          color: _kTextWhite,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      GestureDetector(
                        onTap: () async {
                          final name = nameCtrl.text.trim();
                          final phones = phoneCtrls
                              .map((c) => c.text.trim())
                              .where((t) => t.isNotEmpty)
                              .map((t) => Phone(number: t))
                              .toList();

                          if (name.isNotEmpty && phones.isNotEmpty) {
                            final updatedContact = fullContact.copyWith(
                              name: fullContact.name?.copyWith(first: name) ?? Name(first: name),
                              phones: phones,
                            );
                            await FlutterContacts.update(updatedContact);
                            if (ctx.mounted) Navigator.pop(ctx);
                            _controller.fetchContacts();
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: _kFabBlue,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Save',
                            style: TextStyle(
                              color: Color(0xFF09182C),
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Name Field
                  const Text('Name', style: TextStyle(color: _kTextMuted, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: _kAvatarBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                    ),
                    child: TextField(
                      controller: nameCtrl,
                      style: const TextStyle(color: _kTextWhite),
                      decoration: const InputDecoration(
                        hintText: 'Full Name',
                        hintStyle: TextStyle(color: _kTextMuted),
                        prefixIcon: Icon(Icons.person_outline_rounded, color: _kTextMuted),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Phones
                  const Text('Phone Numbers', style: TextStyle(color: _kTextMuted, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  ...phoneCtrls.asMap().entries.map((entry) {
                    final i = entry.key;
                    final ctrl = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _kAvatarBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                        ),
                        child: Row(
                          children: [
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Icon(Icons.phone_outlined, color: _kTextMuted, size: 20),
                            ),
                            Expanded(
                              child: TextField(
                                controller: ctrl,
                                keyboardType: TextInputType.phone,
                                style: const TextStyle(color: _kTextWhite),
                                decoration: InputDecoration(
                                  hintText: 'Phone ${i + 1}',
                                  hintStyle: const TextStyle(color: _kTextMuted),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                              ),
                            ),
                            if (phoneCtrls.length > 1)
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline, color: _kCoralRed, size: 20),
                                onPressed: () {
                                  setSheetState(() => phoneCtrls.removeAt(i));
                                },
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: _kBlueAccent),
                    onPressed: () {
                      setSheetState(() => phoneCtrls.add(TextEditingController()));
                    },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add Phone Number'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showContactActionsSheet(Contact contact) {
    HapticFeedback.mediumImpact();
    final name = (contact.displayName ?? '').trim();
    final displayName = name.isNotEmpty ? name : 'Unknown';
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    final phone = contact.phones.isNotEmpty ? contact.phones.first.number : '';

    showModalBottomSheet(
      context: context,
      backgroundColor: _kListContainerBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: _kSeparator,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Contact header
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: _kAvatarBg,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: _kTextWhite,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
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
                            color: _kTextWhite,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (phone.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            phone,
                            style: const TextStyle(color: _kTextMuted, fontSize: 13),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Action 1: Call
              if (phone.isNotEmpty)
                _buildActionTile(
                  icon: Icons.call_rounded,
                  iconColor: _kBlueAccent,
                  title: 'Call $phone',
                  onTap: () {
                    Navigator.pop(ctx);
                    _handleCall(contact);
                  },
                ),

              // Action 2: Copy Phone Number
              if (phone.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildActionTile(
                  icon: Icons.copy_rounded,
                  iconColor: _kBlueAccent,
                  title: 'Copy Phone Number',
                  onTap: () {
                    Navigator.pop(ctx);
                    Clipboard.setData(ClipboardData(text: phone));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Phone number copied'), duration: Duration(seconds: 1)),
                    );
                  },
                ),
              ],

              // Action 3: Edit Contact
              const SizedBox(height: 10),
              _buildActionTile(
                icon: Icons.edit_outlined,
                iconColor: _kBlueAccent,
                title: 'Edit Contact',
                onTap: () {
                  Navigator.pop(ctx);
                  _showEditContactSheet(contact);
                },
              ),

              // Action 4: Delete Contact
              const SizedBox(height: 10),
              _buildActionTile(
                icon: Icons.delete_outline_rounded,
                iconColor: _kCoralRed,
                title: 'Delete Contact',
                titleColor: _kCoralRed,
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDeleteContact(contact);
                },
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    Color titleColor = _kTextWhite,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
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
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: titleColor,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: _kTextMuted, size: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteContact(Contact contact) async {
    HapticFeedback.mediumImpact();
    final displayName = contact.displayName ?? 'this contact';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: AlertDialog(
          backgroundColor: _kListContainerBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          title: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _kCoralRed.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_outline_rounded, color: _kCoralRed, size: 26),
              ),
              const SizedBox(height: 14),
              const Text(
                'Delete Contact?',
                style: TextStyle(color: _kTextWhite, fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to delete $displayName from your device?\nThis cannot be undone.',
            style: const TextStyle(color: _kTextMuted, fontSize: 14, height: 1.4),
            textAlign: TextAlign.center,
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel', style: TextStyle(color: _kTextMuted, fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _kCoralRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && contact.id != null) {
      try {
        await FlutterContacts.delete(contact.id!);
        _controller.fetchContacts();
      } catch (e) {
        debugPrint('Failed to delete contact: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final contactsList = _controller.flat;

    return Scaffold(
      backgroundColor: _kBg,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Top Header: Title & Add Button ────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Contacts',
                          style: TextStyle(
                            color: _kTextWhite,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _showNewContactSheet();
                          },
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: const BoxDecoration(
                              color: _kAddButtonBg,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.add,
                              color: _kFabBlue,
                              size: 22,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Search Bar ──────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: _kSearchBg,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                      ),
                      child: Row(
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 14),
                            child: Icon(Icons.search_rounded, color: _kSearchHint, size: 22),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              focusNode: _searchFocus,
                              style: const TextStyle(color: _kTextWhite, fontSize: 16),
                              decoration: const InputDecoration(
                                hintText: 'Search contacts',
                                hintStyle: TextStyle(color: _kSearchHint, fontSize: 16),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(vertical: 12),
                              ),
                              onChanged: (v) => _controller.rebuild(v),
                            ),
                          ),
                          if (_controller.searchQuery.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _searchCtrl.clear();
                                _controller.rebuild('');
                                _searchFocus.unfocus();
                              },
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 14),
                                child: Icon(Icons.close_rounded, color: _kSearchHint, size: 20),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // ── Contact List ────────────────────────────────────────
                  Expanded(
                    child: _controller.contacts == null
                        ? const Center(child: CircularProgressIndicator(color: _kBlueAccent))
                        : contactsList.isEmpty
                            ? _buildEmptyState()
                            : ListView.builder(
                                controller: _scrollCtrl,
                                physics: const BouncingScrollPhysics(),
                                padding: const EdgeInsets.only(left: 16, right: 36, bottom: 130),
                                itemCount: contactsList.length,
                                itemBuilder: (context, index) {
                                  final item = contactsList[index];

                                  // Letter Section Header
                                  if (item is String) {
                                    return SizedBox(
                                      height: _kHeaderHeight,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Padding(
                                          padding: const EdgeInsets.only(left: 6, top: 4),
                                          child: Text(
                                            item,
                                            style: const TextStyle(
                                              color: _kTextMuted,
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 1.0,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }

                                  // Contact Row
                                  final contact = item as Contact;
                                  final isFirst = index == 0 || contactsList[index - 1] is String;
                                  final isLast = index == contactsList.length - 1 || contactsList[index + 1] is String;

                                  return _buildContactCard(contact, isFirst: isFirst, isLast: isLast);
                                },
                              ),
                  ),
                ],
              ),

              // ── Right-Side Alphabet Bar ──────────────────────────────────
              if (_controller.searchQuery.isEmpty && contactsList.isNotEmpty)
                Positioned(
                  right: 2,
                  top: 130,
                  bottom: 110,
                  child: _buildAlphabetBar(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Contact Card (Grouped Container Style) ────────────────────────────────
  Widget _buildContactCard(Contact contact, {required bool isFirst, required bool isLast}) {
    final name = (contact.displayName ?? '').trim();
    final displayName = name.isNotEmpty ? name : 'Unknown';
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    final borderRadius = BorderRadius.vertical(
      top: isFirst ? const Radius.circular(28) : Radius.zero,
      bottom: isLast ? const Radius.circular(28) : Radius.zero,
    );

    return Container(
      margin: EdgeInsets.only(bottom: isLast ? _kSectionGap : 0),
      decoration: BoxDecoration(
        color: _kListContainerBg,
        borderRadius: borderRadius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: borderRadius,
            onLongPress: () => _showContactActionsSheet(contact),
            onTap: () {
              HapticFeedback.selectionClick();
              if (contact.phones.isNotEmpty) {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => ContactDetailsSheet(
                    name: displayName,
                    phone: contact.phones.first.number,
                  ),
                );
              }
            },
            child: SizedBox(
              height: _kContactItemHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    // Avatar with initial letter
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
                            color: _kTextWhite,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 14),

                    // Contact display name
                    Expanded(
                      child: Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _kTextWhite,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),

                    // Call Action Button
                    if (contact.phones.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          _handleCall(contact);
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
            ),
          ),
          if (!isLast)
            Container(
              margin: const EdgeInsets.only(left: 72, right: 16),
              height: 0.6,
              color: _kSeparator,
            ),
        ],
      ),
    );
  }

  // ── Alphabet Sidebar with Smooth Drag & Tap Tracking ─────────────────────
  Widget _buildAlphabetBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (details) {
            _isDraggingBar = true;
            _handleBarDrag(details.localPosition.dy, totalHeight);
          },
          onVerticalDragUpdate: (details) {
            _handleBarDrag(details.localPosition.dy, totalHeight);
          },
          onVerticalDragEnd: (_) {
            _isDraggingBar = false;
          },
          onTapDown: (details) {
            _handleBarDrag(details.localPosition.dy, totalHeight, isTap: true);
          },
          child: Container(
            width: 32,
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _kAlphabet.map((letter) {
                final isSelected = _activeLetter.toUpperCase() == letter;
                return SizedBox(
                  width: 32,
                  child: Text(
                    letter,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isSelected ? _kBlueAccent : _kAlphabetInactive,
                      fontSize: 10.5,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.person_search_outlined, size: 54, color: _kTextMuted),
          const SizedBox(height: 12),
          Text(
            _controller.searchQuery.isEmpty ? 'No contacts found' : 'No results found',
            style: const TextStyle(color: _kTextMuted, fontSize: 16),
          ),
        ],
      ),
    );
  }
}
