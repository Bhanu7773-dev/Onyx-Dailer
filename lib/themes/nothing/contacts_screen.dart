import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:wavedialer/logic/contacts_controller.dart';
import 'package:wavedialer/logic/profile_service.dart';
import 'package:wavedialer/themes/nothing/nothing_dialogs.dart';
import 'package:wavedialer/widgets/contact_details_sheet.dart';

// Nothing UI Colors
const _bg = Color(0xFF000000);
const _nCard = Color(0xFF1A1A1A);
const _nSearchBg = Color(0xFF1C1C1E);
const _nLabel = Color(0xFFFFFFFF);
const _nSecondary = Color(0xFF7E7E7E);
const _nDivider = Color(0xFF1F1F1F);
const _nRed = Color(0xFFE5162A);

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
  bool _filterFavouritesOnly = false;
  Uint8List? _myAvatar;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChange);
    _loadProfileAvatar();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.fetchContacts();
    });
  }

  Future<void> _loadProfileAvatar() async {
    final avatar = await ProfileService.getProfileAvatar();
    if (mounted && avatar != null) {
      setState(() => _myAvatar = avatar);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    _searchFocus.dispose();
    _controller.removeListener(_onControllerChange);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChange() {
    if (mounted) setState(() {});
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
    HapticFeedback.mediumImpact();
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: CupertinoActionSheet(
          title: Text(
            'CALL ${(contact.displayName ?? '').toUpperCase()}',
            style: const TextStyle(
              color: _nLabel,
              letterSpacing: 1.5,
              fontFamily: 'NothingFont',
              fontWeight: FontWeight.bold,
            ),
          ),
          message: const Text('Select a number to call', style: TextStyle(color: _nSecondary)),
          actions: contact.phones.map((p) {
            String label = p.label.label.name.toLowerCase();
            if (label == 'custom' && p.label.customLabel != null) label = p.label.customLabel!;
            return CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                _dial(p.number);
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (label.isNotEmpty && label != 'mobile')
                    Text('$label: ', style: const TextStyle(color: _nSecondary, fontSize: 14)),
                  Text(p.number, style: const TextStyle(color: _nRed, fontWeight: FontWeight.bold, fontFamily: 'NothingFont')),
                ],
              ),
            );
          }).toList(),
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx),
            isDefaultAction: true,
            child: const Text('CANCEL', style: TextStyle(color: _nLabel, fontFamily: 'NothingFont')),
          ),
        ),
      ),
    );
  }

  void _showContactOptions(Contact contact) {
    HapticFeedback.heavyImpact();
    final isBlocked = _controller.isContactBlocked(contact);
    final isFav = _controller.isFavourite(contact);
    final phone = contact.phones.isNotEmpty ? contact.phones.first.number : null;

    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: CupertinoActionSheet(
          title: Text(
            (contact.displayName ?? 'Contact').toUpperCase(),
            style: const TextStyle(
              color: _nLabel,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
              fontSize: 16,
              fontFamily: 'NothingFont',
            ),
          ),
          message: phone != null
              ? Text(phone, style: const TextStyle(color: _nSecondary, fontSize: 13))
              : null,
          actions: [
            if (phone != null)
              CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.pop(ctx);
                  _handleCall(contact);
                },
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.call_rounded, color: _nLabel, size: 20),
                    SizedBox(width: 10),
                    Text('Call', style: TextStyle(color: _nLabel, fontFamily: 'NothingFont')),
                  ],
                ),
              ),
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                _controller.toggleFavourite(contact);
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(isFav ? Icons.star : Icons.star_border, color: _nRed, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    isFav ? 'Remove from Favourites' : 'Add to Favourites',
                    style: const TextStyle(color: _nLabel, fontFamily: 'NothingFont'),
                  ),
                ],
              ),
            ),
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                _showEditContactDialog(contact);
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.pencil, color: _nLabel, size: 20),
                  SizedBox(width: 10),
                  Text('Edit Contact', style: TextStyle(color: _nLabel, fontFamily: 'NothingFont')),
                ],
              ),
            ),
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                _blockContact(contact);
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(isBlocked ? CupertinoIcons.checkmark_circle : CupertinoIcons.slash_circle, color: _nLabel, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    isBlocked ? 'Unblock Contact' : 'Block Contact',
                    style: const TextStyle(color: _nLabel, fontFamily: 'NothingFont'),
                  ),
                ],
              ),
            ),
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(ctx);
                _deleteContact(contact);
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.trash, color: _nRed, size: 20),
                  SizedBox(width: 10),
                  Text('Delete Contact', style: TextStyle(color: _nRed, fontFamily: 'NothingFont')),
                ],
              ),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: _nSecondary, fontFamily: 'NothingFont')),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteContact(Contact contact) async {
    final confirmed = await NothingDialogs.showConfirmDialog(
      context: context,
      title: 'Delete Contact',
      message: 'Are you sure you want to delete ${contact.displayName}?\nThis cannot be undone.',
      confirmLabel: 'DELETE',
      isDestructive: true,
    );

    if (confirmed == true && contact.id != null) {
      await FlutterContacts.delete(contact.id!);
      await _controller.fetchContacts();
    }
  }

  void _showNewContactDialog() {
    NothingDialogs.showNewContact(context, onDone: _controller.fetchContacts);
  }

  void _showEditContactDialog(Contact contact) {
    NothingDialogs.showEditContact(context, contact, onDone: _controller.fetchContacts);
  }

  Future<void> _blockContact(Contact contact) async {
    _searchFocus.unfocus();
    final isBlocked = _controller.isContactBlocked(contact);
    final confirmed = await NothingDialogs.showConfirmDialog(
      context: context,
      title: isBlocked ? 'Unblock Contact' : 'Block Contact',
      message: isBlocked 
        ? 'Allow calls from ${contact.displayName} again?' 
        : 'Reject calls and messages from ${contact.displayName}?',
      confirmLabel: isBlocked ? 'UNBLOCK' : 'BLOCK',
      isDestructive: !isBlocked,
    );

    if (confirmed == true) {
      try {
        final numbers = contact.phones.map((p) => p.number).toList();
        if (isBlocked) {
          await FlutterContacts.blockedNumbers.unblockAll(numbers);
        } else {
          await FlutterContacts.blockedNumbers.blockAll(numbers);
        }
        await _controller.fetchContacts();
      } catch (e) {
        debugPrint('Failed to update blocked status: $e');
      }
    }
  }

  void _scrollToLetter(String letter) {
    final idx = _controller.letterIndex[letter];
    if (idx != null) {
      final offset = idx * 60.0;
      _scrollCtrl.animateTo(
        offset.clamp(0.0, _scrollCtrl.position.maxScrollExtent),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final contactsCount = _controller.contacts?.length ?? 0;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top Bar: Back icon + CONTACTS title + Profile Avatar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: _nLabel, size: 24),
                    onPressed: () {
                      if (Navigator.canPop(context)) {
                        Navigator.pop(context);
                      }
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'CONTACTS',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: _nLabel,
                      letterSpacing: 3.5,
                      fontFamily: 'NothingFont',
                    ),
                  ),
                  const Spacer(),
                  // User Profile Avatar (Tap to open Settings / About menu)
                  GestureDetector(
                    onTap: () => NothingDialogs.showProfileMenu(context, onAvatarChanged: _loadProfileAvatar),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _nSecondary.withValues(alpha: 0.4), width: 1.5),
                        color: const Color(0xFF222222),
                      ),
                      child: ClipOval(
                        child: _myAvatar != null
                            ? Image.memory(_myAvatar!, fit: BoxFit.cover)
                            : const Icon(Icons.person_outline, color: _nLabel, size: 22),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Search Bar with Red '+' Add Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: _nSearchBg,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: const Color(0xFF282828), width: 1),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: _nSecondary, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        focusNode: _searchFocus,
                        onChanged: (q) => _controller.rebuild(q, favouritesOnly: _filterFavouritesOnly),
                        style: const TextStyle(color: _nLabel, fontSize: 15, letterSpacing: 1, fontFamily: 'NothingFont'),
                        cursorColor: _nRed,
                        decoration: const InputDecoration(
                          hintText: 'SEARCH',
                          hintStyle: TextStyle(
                            color: _nSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 2,
                            fontFamily: 'NothingFont',
                          ),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                    if (_searchCtrl.text.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _searchCtrl.clear();
                          _controller.rebuild('', favouritesOnly: _filterFavouritesOnly);
                        },
                        child: const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(Icons.close, color: _nSecondary, size: 18),
                        ),
                      ),
                    // Red Circular Add Contact Button
                    GestureDetector(
                      onTap: _showNewContactDialog,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(
                          color: _nRed,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.add, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Subheader: Current Section + Favourite Pill + Total Count Badge
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
              child: Row(
                children: [
                  const Text(
                    'A',
                    style: TextStyle(
                      color: _nSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'NothingFont',
                    ),
                  ),
                  const Spacer(),
                  // Favourite button pill (Filters list on tap)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _filterFavouritesOnly = !_filterFavouritesOnly;
                        _controller.rebuild(_searchCtrl.text, favouritesOnly: _filterFavouritesOnly);
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: _filterFavouritesOnly ? _nRed.withValues(alpha: 0.18) : const Color(0xFF141414),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _filterFavouritesOnly ? _nRed : const Color(0xFF2C2C2C),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _filterFavouritesOnly ? Icons.star_rounded : Icons.star_outline_rounded,
                            color: _filterFavouritesOnly ? _nRed : _nSecondary,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Favourite',
                            style: TextStyle(
                              color: _filterFavouritesOnly ? _nRed : _nSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'NothingFont',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Total Count Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141414),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF2C2C2C), width: 1),
                    ),
                    child: Text(
                      'Total: $contactsCount',
                      style: const TextStyle(
                        color: _nSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'NothingFont',
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Contact List
            Expanded(
              child: _controller.contacts == null
                  ? const Center(child: CircularProgressIndicator(color: _nRed, strokeWidth: 2))
                  : _controller.flat.isEmpty
                      ? Center(
                          child: Text(
                            _filterFavouritesOnly
                                ? 'NO FAVOURITE CONTACTS'
                                : (_searchCtrl.text.isNotEmpty ? 'NO CONTACTS FOUND' : 'NO CONTACTS'),
                            style: const TextStyle(
                              color: _nSecondary,
                              letterSpacing: 2,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'NothingFont',
                            ),
                          ),
                        )
                      : Stack(
                          children: [
                            ListView.separated(
                              controller: _scrollCtrl,
                              padding: const EdgeInsets.fromLTRB(16, 4, 32, 90),
                              itemCount: _controller.flat.length,
                              separatorBuilder: (ctx, i) {
                                if (_controller.flat[i] is String) return const SizedBox.shrink();
                                return const Divider(color: _nDivider, height: 1, indent: 56);
                              },
                              itemBuilder: (ctx, i) {
                                final item = _controller.flat[i];
                                if (item is String) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 14, bottom: 6),
                                    child: Text(
                                      item,
                                      style: const TextStyle(
                                        color: _nSecondary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        fontFamily: 'NothingFont',
                                      ),
                                    ),
                                  );
                                }

                                final contact = item as Contact;
                                final name = (contact.displayName ?? 'Unknown').toUpperCase();
                                final phone = contact.phones.isNotEmpty ? contact.phones.first.number : null;
                                final initial = (contact.displayName != null && contact.displayName!.isNotEmpty)
                                    ? contact.displayName![0].toUpperCase()
                                    : '#';
                                final isFav = _controller.isFavourite(contact);

                                return Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () => _handleCall(contact),
                                    onLongPress: () => _showContactOptions(contact),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      height: 56,
                                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                                      child: Row(
                                        children: [
                                          // Rounded Stadium Avatar
                                          GestureDetector(
                                            onTap: phone != null
                                                ? () => showContactDetails(
                                                      context,
                                                      name: name,
                                                      phone: phone,
                                                      avatarColor: _nCard,
                                                      avatarTextColor: _nLabel,
                                                    )
                                                : null,
                                            child: Container(
                                              width: 42,
                                              height: 42,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF202020),
                                                borderRadius: BorderRadius.circular(14),
                                                border: Border.all(color: const Color(0xFF2C2C2C), width: 1),
                                              ),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(14),
                                                child: contact.photo?.thumbnail != null
                                                    ? Image.memory(
                                                        contact.photo!.thumbnail!,
                                                        fit: BoxFit.cover,
                                                      )
                                                    : Center(
                                                        child: Text(
                                                          initial,
                                                          style: const TextStyle(
                                                            color: _nLabel,
                                                            fontWeight: FontWeight.w700,
                                                            fontSize: 16,
                                                            fontFamily: 'NothingFont',
                                                          ),
                                                        ),
                                                      ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Text(
                                              name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: _nLabel,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: 1.2,
                                                fontFamily: 'NothingFont',
                                              ),
                                            ),
                                          ),
                                          // Quick Favourite Star Toggle
                                          IconButton(
                                            icon: Icon(
                                              isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                                              color: isFav ? _nRed : const Color(0xFF444444),
                                              size: 20,
                                            ),
                                            onPressed: () => _controller.toggleFavourite(contact),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),

                            // Fast Scroll Letter / Dot Indicator on Right Edge
                            Positioned(
                              right: 6,
                              top: 10,
                              bottom: 90,
                              child: Container(
                                width: 16,
                                alignment: Alignment.center,
                                child: SingleChildScrollView(
                                  physics: const NeverScrollableScrollPhysics(),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: _controller.letters.map((letter) {
                                      final isTop = _controller.letters.indexOf(letter) == 0;
                                      return GestureDetector(
                                        onTap: () => _scrollToLetter(letter),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 3.5),
                                          child: Container(
                                            width: 4.5,
                                            height: 4.5,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: isTop ? _nRed : const Color(0xFF555555),
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
