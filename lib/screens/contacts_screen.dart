import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wavedialer/screens/call_screen.dart';
import 'package:wavedialer/services/telecom_service.dart';

// ── iOS colours ────────────────────────────────────────────────────────────
const _bg           = Color(0xFF000000);
const _card         = Color(0xFF1C1C1E);
const _iosBlue      = Color(0xFF007AFF);
const _iosGreen     = Color(0xFF34C759);
const _iosLabel     = Color(0xFFFFFFFF);
const _iosSecondary = Color(0xFF8E8E93);
const _iosTertiary  = Color(0xFF48484A);
const _separator    = Color(0xFF38383A);

// Estimated heights for offset calculation
const double _kHeaderH  = 48.0;   // letter section header
const double _kContactH = 52.0;   // each contact row

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});
  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<Contact>? _contacts;
  String _searchQuery = '';

  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  // Flat list: String = section header, Contact = row
  List<dynamic> _flat = [];
  // letter → flat index of its header
  Map<String, int> _letterIndex = {};
  List<String> _letters = [];

  @override
  void initState() {
    super.initState();
    _fetchContacts();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  Future<void> _fetchContacts() async {
    if (await Permission.contacts.isGranted) {
      final contacts = await FlutterContacts.getAll(
          properties: {ContactProperty.phone});
      
      // Only keep contacts that actually have a phone number
      final validContacts = contacts.where((c) => c.phones.isNotEmpty).toList();

      validContacts.sort((a, b) =>
          (a.displayName ?? '').toLowerCase()
              .compareTo((b.displayName ?? '').toLowerCase()));
      if (mounted) {
        setState(() {
          _contacts = validContacts;
          _rebuild('');
        });
      }
    } else {
      if (mounted) setState(() { _contacts = []; _flat = []; });
    }
  }

  String _letterOf(Contact c) {
    final ch = (c.displayName?.trim() ?? '')[0].toUpperCase();
    return RegExp(r'[A-Z]').hasMatch(ch) ? ch : '#';
  }

  void _rebuild(String query) {
    if (_contacts == null) return;

    List<Contact> filtered = _contacts!;
    if (query.isNotEmpty) {
      final q = query.toLowerCase();
      final pq = query.replaceAll(RegExp(r'\D'), '');
      filtered = _contacts!.where((c) {
        final nm = (c.displayName ?? '').toLowerCase().contains(q);
        final ph = pq.isNotEmpty &&
            c.phones.any((p) =>
                p.number.replaceAll(RegExp(r'\D'), '').contains(pq));
        return nm || ph;
      }).toList();
    }

    // Group
    final Map<String, List<Contact>> grouped = {};
    for (final c in filtered) {
      grouped.putIfAbsent(_letterOf(c), () => []).add(c);
    }

    final letters = grouped.keys.toList()
      ..sort((a, b) {
        if (a == '#') return 1;
        if (b == '#') return -1;
        return a.compareTo(b);
      });

    final flat = <dynamic>[];
    final letterIdx = <String, int>{};
    for (final l in letters) {
      letterIdx[l] = flat.length;
      flat.add(l);
      flat.addAll(grouped[l]!);
    }

    _flat = flat;
    _letterIndex = letterIdx;
    _letters = letters;
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  void _dial(String number) {
    HapticFeedback.lightImpact();
    TelecomService.makeCall(number);
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => CallScreen(initialNumber: number)));
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
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Large title ────────────────────────────────────────────
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 10),
                child: Text('Contacts',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      color: _iosLabel,
                      letterSpacing: -0.5,
                    )),
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
                          onChanged: (v) {
                            setState(() {
                              _searchQuery = v;
                              _rebuild(v);
                            });
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
                      if (_searchQuery.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _searchCtrl.clear();
                            setState(() {
                              _searchQuery = '';
                              _rebuild('');
                            });
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
                child: _contacts == null
                    ? const Center(
                        child: CircularProgressIndicator(color: _iosBlue))
                    : _flat.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.person_search_outlined,
                                    size: 60, color: _iosTertiary),
                                const SizedBox(height: 12),
                                Text(
                                  _searchQuery.isEmpty
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
                            itemCount: _flat.length,
                            itemBuilder: (ctx, i) {
                              final item = _flat[i];
                              if (item is String) {
                                return _sectionHeader(item);
                              }
                              final contact = item as Contact;
                              // Is this the last in its section?
                              final isLast = i == _flat.length - 1 ||
                                  _flat[i + 1] is String;
                              // Is first in section?
                              final isFirst = i == 0 ||
                                  _flat[i - 1] is String;
                              return _contactRow(
                                  contact, isFirst, isLast);
                            },
                          ),
              ),
            ],
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

    return GestureDetector(
      onTap: phone != null ? () => _dial(phone) : null,
      child: Container(
        height: _kContactH,
        decoration: BoxDecoration(
          color: _card,
          borderRadius: borderRadius,
        ),
        padding: const EdgeInsets.fromLTRB(14, 0, 0, 0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: _iosTertiary,
              child: Text(initial,
                  style: const TextStyle(
                      fontSize: 15,
                      color: _iosLabel,
                      fontWeight: FontWeight.w500)),
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
                      child: Text(name,
                          style: const TextStyle(
                              color: _iosLabel,
                              fontSize: 16,
                              fontWeight: FontWeight.w400)),
                    ),
                    if (phone != null)
                      GestureDetector(
                        onTap: () => _dial(phone),
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
    );
  }
}
