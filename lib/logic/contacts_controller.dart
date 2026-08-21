import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavedialer/services/telecom_service.dart';

class ContactsController extends ChangeNotifier {
  List<Contact>? _contacts;
  String _searchQuery = '';
  Set<String> _blockedNumbers = {};
  Set<String> _favouriteIds = {};
  bool _favouritesOnly = false;

  List<dynamic> _flat = [];
  Map<String, int> _letterIndex = {};
  List<String> _letters = [];

  List<Contact>? get contacts => _contacts;
  String get searchQuery => _searchQuery;
  List<dynamic> get flat => _flat;
  Map<String, int> get letterIndex => _letterIndex;
  List<String> get letters => _letters;
  bool get favouritesOnly => _favouritesOnly;

  Future<void> fetchContacts() async {
    final prefs = await SharedPreferences.getInstance();
    _favouriteIds = (prefs.getStringList('favourite_contact_ids') ?? []).toSet();

    if (await Permission.contacts.isGranted) {
      final results = await Future.wait([
        FlutterContacts.getAll(properties: {ContactProperty.phone, ContactProperty.photoThumbnail}),
        FlutterContacts.blockedNumbers.isAvailable(),
      ]);

      final contacts = results[0] as List<Contact>;
      final isBlockedAvailable = results[1] as bool;

      final validContacts = contacts.where((c) => c.phones.isNotEmpty).toList();

      validContacts.sort((a, b) =>
          (a.displayName ?? '').toLowerCase().compareTo((b.displayName ?? '').toLowerCase()));

      Set<String> blockedNums = {};
      if (isBlockedAvailable) {
        try {
          final blocked = await FlutterContacts.blockedNumbers.getAll();
          blockedNums = blocked.map((p) => p.number.replaceAll(RegExp(r'\D'), '')).toSet();
        } catch (_) {}
      }

      _contacts = validContacts;
      _blockedNumbers = blockedNums;
      rebuild(_searchQuery, favouritesOnly: _favouritesOnly);
    } else {
      _contacts = [];
      _flat = [];
      _letterIndex = {};
      _letters = [];
      notifyListeners();
    }
  }

  bool isContactBlocked(Contact contact) {
    return contact.phones.any((p) {
      final clean = p.number.replaceAll(RegExp(r'\D'), '');
      return _blockedNumbers.contains(clean);
    });
  }

  bool isFavourite(Contact contact) {
    if (contact.id != null && _favouriteIds.contains(contact.id)) return true;
    return false;
  }

  Future<void> toggleFavourite(Contact contact) async {
    final id = contact.id;
    if (id == null) return;
    if (_favouriteIds.contains(id)) {
      _favouriteIds.remove(id);
    } else {
      _favouriteIds.add(id);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favourite_contact_ids', _favouriteIds.toList());
    rebuild(_searchQuery, favouritesOnly: _favouritesOnly);
  }

  String _letterOf(Contact c) {
    final name = (c.displayName ?? '').trim();
    final ch = name.isNotEmpty ? name[0].toUpperCase() : '#';
    return RegExp(r'[A-Z]').hasMatch(ch) ? ch : '#';
  }

  void rebuild(String query, {bool? favouritesOnly}) {
    _searchQuery = query;
    if (favouritesOnly != null) {
      _favouritesOnly = favouritesOnly;
    }
    if (_contacts == null) return;

    List<Contact> filtered = _contacts!;

    if (_favouritesOnly) {
      filtered = filtered.where((c) => isFavourite(c)).toList();
    }

    if (query.isNotEmpty) {
      final q = query.toLowerCase();
      final pq = query.replaceAll(RegExp(r'\D'), '');
      filtered = filtered.where((c) {
        final nm = (c.displayName ?? '').toLowerCase().contains(q);
        final ph = pq.isNotEmpty &&
            c.phones.any((p) =>
                p.number.replaceAll(RegExp(r'\D'), '').contains(pq));
        return nm || ph;
      }).toList();
    }

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
    notifyListeners();
  }

  Future<void> dial(BuildContext context, String number) async {
    HapticFeedback.lightImpact();
    await TelecomService.handleOutgoingCall(context, number);
  }
}
