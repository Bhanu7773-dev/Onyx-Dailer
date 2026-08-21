import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wavedialer/services/telecom_service.dart';
import 'package:wavedialer/widgets/contact_details_sheet.dart';
import 'package:wavedialer/widgets/contact_dialogs.dart';
import 'dart:ui';
import 'package:wavedialer/logic/contacts_controller.dart';


const _bg           = Color(0xFF000000);
const _card         = Color(0xFF1C1C1E);
const _iosBlue      = Color(0xFF007AFF);
const _iosGreen     = Color(0xFF34C759);
const _iosLabel     = Color(0xFFFFFFFF);
const _iosSecondary = Color(0xFF8E8E93);
const _iosTertiary  = Color(0xFF48484A);
const _separator    = Color(0xFF38383A);
const _iosRed       = Color(0xFFFF3B30);

const double _kHeaderH  = 48.0;
const double _kContactH = 52.0;

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

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.fetchContacts();
    });
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

  // ── Actions ───────────────────────────────────────────────────────────────

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
          title: Text('Call ${contact.displayName}', style: const TextStyle(color: _iosLabel)),
          message: const Text('Select a number to call', style: TextStyle(color: _iosSecondary)),
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
                    Text('$label: ', style: const TextStyle(color: _iosSecondary, fontSize: 14)),
                  Text(p.number, style: const TextStyle(color: _iosBlue)),
                ],
              ),
            );
          }).toList(),
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx),
            isDefaultAction: true,
            child: const Text('Cancel', style: TextStyle(color: _iosBlue)),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteContact(Contact contact) async {
    HapticFeedback.mediumImpact();
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: CupertinoAlertDialog(
          title: const Text('Delete Contact'),
          content: Text('Are you sure you want to delete ${contact.displayName} from your device?\nThis cannot be undone.'),
          actions: [
            CupertinoDialogAction(
              child: const Text('Cancel', style: TextStyle(color: _iosBlue)),
              onPressed: () => Navigator.pop(ctx, false),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      try {
        if (contact.id != null) {
          await FlutterContacts.delete(contact.id!);
          await _controller.fetchContacts();
        }
      } catch (e) {
        debugPrint('Failed to delete contact: $e');
      }
    }
  }

  void _showNewContactDialog() {
    ContactDialogs.showNewContact(context, onDone: _controller.fetchContacts);
  }

  void _showEditContactDialog(Contact contact) {
    ContactDialogs.showEditContact(context, contact, onDone: _controller.fetchContacts);
  }

  Future<void> _blockContact(Contact contact) async {
    _searchFocus.unfocus();
    HapticFeedback.mediumImpact();
    
    final isAvailable = await FlutterContacts.blockedNumbers.isAvailable();
    if (!isAvailable) {
      showCupertinoDialog(
        context: context,
        builder: (ctx) => BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: CupertinoAlertDialog(
            title: const Text('System Requirement'),
            content: const Text('To block numbers, OnyxDialer must be set as your default phone app.'),
            actions: [
              CupertinoDialogAction(
                child: const Text('Cancel', style: TextStyle(color: _iosBlue)),
                onPressed: () => Navigator.pop(ctx),
              ),
              CupertinoDialogAction(
                child: const Text('Open Settings'),
                onPressed: () {
                  Navigator.pop(ctx);
                  TelecomService.requestDefaultDialer();
                },
              ),
            ],
          ),
        ),
      );
      return;
    }

    final isBlocked = _controller.isContactBlocked(contact);
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: CupertinoAlertDialog(
          title: Text(isBlocked ? 'Unblock Contact' : 'Block Contact'),
          content: Text(isBlocked 
            ? 'Allow calls and messages from ${contact.displayName} again?'
            : 'Are you sure you want to block all numbers for ${contact.displayName}? You will no longer receive calls from them.'),
          actions: [
            CupertinoDialogAction(
              child: const Text('Cancel', style: TextStyle(color: _iosBlue)),
              onPressed: () => Navigator.pop(ctx, false),
            ),
            CupertinoDialogAction(
              isDestructiveAction: !isBlocked,
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(isBlocked ? 'Unblock' : 'Block'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      try {
        final numbers = contact.phones.map((p) => p.number).toList();
        if (isBlocked) {
          await FlutterContacts.blockedNumbers.unblockAll(numbers);
        } else {
          await FlutterContacts.blockedNumbers.blockAll(numbers);
        }
        await _controller.fetchContacts(); // Refresh blocked status
      } catch (e) {
        debugPrint('Failed to update blocked status: $e');
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF1C1C1E),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _bg,
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Large title ────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Contacts',
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          color: _iosLabel,
                          letterSpacing: -0.5,
                        )),
                    GestureDetector(
                      onTap: _showNewContactDialog,
                      child: const Icon(CupertinoIcons.add, color: _iosBlue, size: 28),
                    ),
                  ],
                ),
              ),

              // ── Search bar ─────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.search_rounded,
                            color: _iosSecondary, size: 18),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          focusNode: _searchFocus,
                          onTapOutside: (_) => _searchFocus.unfocus(),
                          onChanged: (v) {
                            _controller.rebuild(v);
                          },
                          style:
                              const TextStyle(color: _iosLabel, fontSize: 15),
                          decoration: const InputDecoration(
                            hintText: 'Search',
                            hintStyle:
                                TextStyle(color: _iosSecondary, fontSize: 15),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding:
                                EdgeInsets.symmetric(vertical: 8),
                          ),
                          cursorColor: _iosBlue,
                        ),
                      ),
                      if (_controller.searchQuery.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _searchCtrl.clear();
                            _controller.rebuild('');
                            FocusScope.of(context).unfocus();
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Icon(Icons.cancel,
                                color: _iosSecondary, size: 18),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // ── List ───────────────────────────────────────────────────
              Expanded(
                child: _controller.contacts == null
                    ? const Center(
                        child: CircularProgressIndicator(color: _iosBlue))
                    : _controller.flat.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.person_search_outlined,
                                    size: 60, color: _iosTertiary),
                                const SizedBox(height: 12),
                                Text(
                                  _controller.searchQuery.isEmpty
                                      ? 'No contacts'
                                      : 'No results',
                                  style: const TextStyle(
                                      color: _iosSecondary, fontSize: 16),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.only(
                                left: 16, right: 16, bottom: 100),
                            itemCount: _controller.flat.length,
                            itemBuilder: (ctx, i) {
                              final item = _controller.flat[i];
                              if (item is String) {
                                  return _sectionHeader(item);
                              }
                              final contact = item as Contact;
                              // Is this the last in its section?
                              final isLast = i == _controller.flat.length - 1 ||
                                  _controller.flat[i + 1] is String;
                              // Is first in section?
                              final isFirst = i == 0 ||
                                  _controller.flat[i - 1] is String;
                              return _contactRow(
                                  contact, isFirst, isLast);
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

  Widget _sectionHeader(String letter) {
    return SizedBox(
      height: _kHeaderH,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 18, 16, 4),
        child: Text(
          letter,
          style: const TextStyle(
            color: _iosSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _contactRow(Contact contact, bool isFirst, bool isLast) {
    final phone =
        contact.phones.isNotEmpty ? contact.phones.first.number : null;
    final name = contact.displayName ?? 'Unknown';
    final initial = name.trim().isEmpty ? '#' : name[0].toUpperCase();

    final borderRadius = BorderRadius.vertical(
      top: isFirst ? const Radius.circular(13) : Radius.zero,
      bottom: isLast ? const Radius.circular(13) : Radius.zero,
    );

    return CupertinoContextMenu(
      enableHapticFeedback: true,
      actions: <Widget>[
        CupertinoContextMenuAction(
          onPressed: () {
            Navigator.pop(context);
            _handleCall(contact);
          },
          trailingIcon: CupertinoIcons.phone,
          child: const Text('Call'),
        ),
        CupertinoContextMenuAction(
          onPressed: () {
            Navigator.pop(context);
            _showEditContactDialog(contact);
          },
          trailingIcon: CupertinoIcons.pencil,
          child: const Text('Edit'),
        ),
        CupertinoContextMenuAction(
          onPressed: () {
            Navigator.pop(context);
            _blockContact(contact);
          },
          trailingIcon: _controller.isContactBlocked(contact) ? CupertinoIcons.checkmark_circle : CupertinoIcons.slash_circle,
          child: Text(_controller.isContactBlocked(contact) ? 'Unblock' : 'Block'),
        ),
        CupertinoContextMenuAction(
          onPressed: () {
            Navigator.pop(context);
            _deleteContact(contact);
          },
          isDestructiveAction: true,
          trailingIcon: CupertinoIcons.trash,
          child: const Text('Delete'),
        ),
      ],
      child: SizedBox(
        width: MediaQuery.of(context).size.width - 32,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: () => _handleCall(contact),
            child: Container(
              height: _kContactH,
              decoration: BoxDecoration(
                color: _card,
                borderRadius: borderRadius,
              ),
              padding: const EdgeInsets.fromLTRB(14, 0, 0, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: phone != null ? () => showContactDetails(context, name: name, phone: phone, avatarColor: _iosTertiary, avatarTextColor: _iosLabel) : null,
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: _iosTertiary,
                      backgroundImage: contact.photo?.thumbnail != null
                          ? MemoryImage(contact.photo!.thumbnail!)
                          : null,
                      child: contact.photo?.thumbnail == null
                          ? Text(initial,
                              style: const TextStyle(
                                  fontSize: 15,
                                  color: _iosLabel,
                                  fontWeight: FontWeight.w500))
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: isLast
                            ? null
                            : const Border(
                                bottom:
                                    BorderSide(color: _separator, width: 0.4)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: _iosLabel,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w400)),
                                ),
                                if (_controller.isContactBlocked(contact))
                                  const Padding(
                                    padding: EdgeInsets.only(left: 6),
                                    child: Icon(CupertinoIcons.slash_circle_fill, color: _iosRed, size: 14),
                                  ),
                              ],
                            ),
                          ),
                          if (contact.phones.isNotEmpty)
                            GestureDetector(
                              onTap: () => _handleCall(contact),
                              child: Container(
                                width: 44,
                                height: 44,
                                alignment: Alignment.center,
                                child: const Icon(Icons.call_rounded,
                                    color: _iosGreen, size: 20),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
