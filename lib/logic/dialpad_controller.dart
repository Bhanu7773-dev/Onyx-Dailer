import 'package:call_log/call_log.dart';
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

  Contact? get matchedContact =>
      _suggestedContacts.isNotEmpty ? _suggestedContacts.first : null;

  void init() {
    fetchContacts();
  }

  Future<void> fetchContacts() async {
    if (await Permission.contacts.isGranted) {
      try {
        final contacts = await FlutterContacts.getAll(properties: {
          ContactProperty.phone,
          ContactProperty.photoThumbnail,
        });
        _allContacts = contacts;
        _updateSuggestions();
        notifyListeners();
      } catch (e) {
        debugPrint('DialpadController.fetchContacts error: $e');
      }
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

    final cleanQuery = _number.replaceAll(RegExp(r'\D'), '');

    _suggestedContacts = _allContacts.where((c) {
      final name = c.displayName ?? '';
      final t9 = _nameToT9(name);

      // T9 match (matches digits typed against contact name)
      final t9Match = cleanQuery.isNotEmpty && t9.contains(cleanQuery);

      // Direct name match (e.g. if query has text)
      final nameMatch = name.toLowerCase().contains(_number.toLowerCase());

      // Phone number match
      final phoneMatch = c.phones.any((p) {
        final cleanPhone = p.number.replaceAll(RegExp(r'\D'), '');
        if (cleanPhone.isEmpty) return false;
        if (cleanQuery.isEmpty) return false;

        // Substring either direction
        if (cleanPhone.contains(cleanQuery) || cleanQuery.contains(cleanPhone)) {
          return true;
        }

        // Suffix match for country codes (e.g. +91 9876543210 vs 9876543210)
        final minLen = cleanPhone.length < cleanQuery.length ? cleanPhone.length : cleanQuery.length;
        if (minLen >= 7) {
          final checkLen = minLen >= 10 ? 10 : (minLen >= 8 ? 8 : 7);
          final pSuffix = cleanPhone.substring(cleanPhone.length - checkLen);
          final qSuffix = cleanQuery.substring(cleanQuery.length - checkLen);
          if (pSuffix == qSuffix) return true;
        }

        return false;
      });

      return t9Match || nameMatch || phoneMatch;
    }).toList();

    // Sort exact phone/suffix matches first
    if (cleanQuery.isNotEmpty) {
      _suggestedContacts.sort((a, b) {
        bool isExact(Contact c) => c.phones.any((p) {
          final cp = p.number.replaceAll(RegExp(r'\D'), '');
          return cp == cleanQuery ||
              (cleanQuery.length >= 10 && cp.endsWith(cleanQuery.substring(cleanQuery.length - 10))) ||
              (cp.length >= 10 && cleanQuery.endsWith(cp.substring(cp.length - 10)));
        });
        final aExact = isExact(a);
        final bExact = isExact(b);
        if (aExact && !bExact) return -1;
        if (!aExact && bExact) return 1;
        return 0;
      });
    }

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

  Future<bool> fillLastCalledNumber() async {
    try {
      if (_allContacts.isEmpty) {
        await fetchContacts();
      }

      final entries = await CallLog.query();
      if (entries.isEmpty) return false;

      // Prefer the most recent outgoing call first
      CallLogEntry? targetEntry;
      for (final entry in entries) {
        final num = entry.number;
        if (entry.callType == CallType.outgoing && num != null && num.trim().isNotEmpty) {
          targetEntry = entry;
          break;
        }
      }

      // If no outgoing call found, fallback to the most recent call of any type
      if (targetEntry == null) {
        for (final entry in entries) {
          final num = entry.number;
          if (num != null && num.trim().isNotEmpty) {
            targetEntry = entry;
            break;
          }
        }
      }

      if (targetEntry != null && targetEntry.number != null) {
        _number = targetEntry.number!.trim();
        _updateSuggestions();

        // If no contact was matched from contacts book, check if CallLog recorded a name
        if (_suggestedContacts.isEmpty) {
          final logName = targetEntry.name?.trim();
          if (logName != null && logName.isNotEmpty && logName != _number) {
            _suggestedContacts = [
              Contact(
                displayName: logName,
                phones: [Phone(number: _number)],
              ),
            ];
            notifyListeners();
          }
        }

        HapticFeedback.lightImpact();
        return true;
      }
    } catch (e) {
      debugPrint('Failed to fill last called number: $e');
    }
    return false;
  }

  Future<bool> call(BuildContext context, [String? num, String? simId]) async {
    final target = num ?? _number;
    if (target.isEmpty) {
      await fillLastCalledNumber();
      return false;
    }

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
        return false;
      }
    }

    HapticFeedback.heavyImpact();
    if (simId != null) {
      await TelecomService.makeCall(target, simId: simId);
    } else if (context.mounted) {
      await TelecomService.handleOutgoingCall(context, target);
    }
    return true;
  }
}
