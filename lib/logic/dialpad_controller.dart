import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wavedialer/services/telecom_service.dart';

class DialpadController extends ChangeNotifier {
  String _number = '';
  List<Contact> _allContacts = [];
  List<Contact> _suggestedContacts = [];

  String get number => _number;
  List<Contact> get suggestedContacts => _suggestedContacts;

  void init() {
    fetchContacts();
  }

  Future<void> fetchContacts() async {
    if (await Permission.contacts.isGranted) {
      final contacts = await FlutterContacts.getAll(properties: {ContactProperty.phone});
      _allContacts = contacts;
      notifyListeners();
    }
  }

  String _nameToT9(String name) {
    const map = {
      'A': '2', 'B': '2', 'C': '2', 'D': '3', 'E': '3', 'F': '3',
      'G': '4', 'H': '4', 'I': '4', 'J': '5', 'K': '5', 'L': '5',
      'M': '6', 'N': '6', 'O': '6', 'P': '7', 'Q': '7', 'R': '7', 'S': '7',
      'T': '8', 'U': '8', 'V': '8', 'W': '9', 'X': '9', 'Y': '9', 'Z': '9',
    };
    return name.toUpperCase().split('').map((c) => map[c] ?? '').join();
  }

  void _updateSuggestions() {
    if (_number.isEmpty) {
      _suggestedContacts = [];
      notifyListeners();
      return;
    }
    _suggestedContacts = _allContacts.where((c) {
      final t9 = _nameToT9(c.displayName ?? '');
      final phoneMatch = c.phones.any((p) =>
          p.number.replaceAll(RegExp(r'\D'), '').contains(_number));
      return t9.contains(_number) || phoneMatch;
    }).toList();
    notifyListeners();
  }

  Future<void> press(String digit, [BuildContext? context]) async {
    HapticFeedback.lightImpact();
    TelecomService.playLocalDtmf(digit);
    _number += digit;
    _updateSuggestions();

    // Check if the input is a complete secret code (e.g. *#*#4636#*#*, *#06#, etc.)
    final isFullStarHashPattern = RegExp(r'^\*#\*#[0-9a-zA-Z]+#\*#\*$').hasMatch(_number);
    final isSingleStarHashPattern = RegExp(r'^\*#[0-9a-zA-Z]+#$').hasMatch(_number);

    if (isFullStarHashPattern || isSingleStarHashPattern) {
      final codeToRun = _number;
      final res = await TelecomService.handleSecretCode(codeToRun);
      if (res['handled'] == true) {
        _number = '';
        _suggestedContacts = [];
        notifyListeners();

        if (res['type'] == 'imei' && context != null && context.mounted) {
          final info = res['info'] as String? ?? 'IMEI information unavailable';
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF181818),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Device Information', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              content: Text(info, style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.4)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK', style: TextStyle(color: Color(0xFFE5162A), fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }
      }
    }
  }

  void delete() {
    if (_number.isNotEmpty) {
      HapticFeedback.lightImpact();
      _number = _number.substring(0, _number.length - 1);
      _updateSuggestions();
    }
  }

  void clearAll() {
    HapticFeedback.mediumImpact();
    _number = '';
    _suggestedContacts = [];
    notifyListeners();
  }

  Future<void> call(BuildContext context, [String? num]) async {
    final target = num ?? _number;
    if (target.isEmpty) return;

    // Check if target is a secret code
    final isFullStarHashPattern = RegExp(r'^\*#\*#[0-9a-zA-Z]+#\*#\*$').hasMatch(target);
    final isSingleStarHashPattern = RegExp(r'^\*#[0-9a-zA-Z]+#$').hasMatch(target);

    if (isFullStarHashPattern || isSingleStarHashPattern) {
      final res = await TelecomService.handleSecretCode(target);
      if (res['handled'] == true) {
        _number = '';
        _suggestedContacts = [];
        notifyListeners();
        if (res['type'] == 'imei' && context.mounted) {
          final info = res['info'] as String? ?? 'IMEI information unavailable';
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF181818),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Device Information', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              content: Text(info, style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.4)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK', style: TextStyle(color: Color(0xFFE5162A), fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }
        return;
      }
    }

    HapticFeedback.heavyImpact();
    await TelecomService.handleOutgoingCall(context, target);
  }
}
