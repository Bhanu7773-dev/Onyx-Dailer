import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:call_log/call_log.dart';
import 'package:intl/intl.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:wavedialer/services/telecom_service.dart';

enum CallFilter { all, incoming, outgoing, missed }

class RecentsController extends ChangeNotifier {
  List<CallLogEntry>? _callLogs;
  CallFilter _filter = CallFilter.all;
  Set<String> _blockedNumbers = {};

  List<CallLogEntry>? get callLogs => _callLogs;
  CallFilter get filter => _filter;
  Set<String> get blockedNumbers => _blockedNumbers;
  bool get isLoading => _callLogs == null;

  void clearAllLogs() {
    _callLogs?.clear();
    notifyListeners();
  }

  void setFilter(CallFilter f) {
    _filter = f;
    notifyListeners();
  }

  Future<void> fetchCallLogs() async {
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));

    final futures = await Future.wait([
      CallLog.query(dateFrom: thirtyDaysAgo.millisecondsSinceEpoch),
      FlutterContacts.blockedNumbers.isAvailable(),
    ]);

    final entries = futures[0] as Iterable<CallLogEntry>;
    final isBlockedAvailable = futures[1] as bool;

    Set<String> blockedNums = {};
    if (isBlockedAvailable) {
      try {
        final blocked = await FlutterContacts.blockedNumbers.getAll();
        blockedNums = blocked.map((p) => p.number.replaceAll(RegExp(r'\D'), '')).toSet();
      } catch (_) {}
    }

    _callLogs = List<CallLogEntry>.from(entries);
    _blockedNumbers = blockedNums;
    notifyListeners();
  }

  bool isNumberBlocked(String? number) {
    if (number == null) return false;
    final clean = number.replaceAll(RegExp(r'\D'), '');
    return _blockedNumbers.contains(clean);
  }

  bool isMissed(CallType? t) =>
      t == CallType.missed || t == CallType.rejected;

  List<CallLogEntry> get filteredLogs {
    if (_callLogs == null) return [];
    switch (_filter) {
      case CallFilter.all:
        return _callLogs!;
      case CallFilter.incoming:
        return _callLogs!.where((e) => e.callType == CallType.incoming).toList();
      case CallFilter.outgoing:
        return _callLogs!.where((e) => e.callType == CallType.outgoing).toList();
      case CallFilter.missed:
        return _callLogs!.where((e) => isMissed(e.callType)).toList();
    }
  }

  Map<String, List<CallLogEntry>> getGroupedLogs(List<CallLogEntry> logs) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final Map<String, List<CallLogEntry>> groups = {};
    for (final log in logs) {
      final dt = DateTime.fromMillisecondsSinceEpoch(log.timestamp ?? 0);
      final day = DateTime(dt.year, dt.month, dt.day);

      String label;
      if (day == today) {
        label = 'Today';
      } else if (day == yesterday) {
        label = 'Yesterday';
      } else if (now.difference(day).inDays < 7) {
        label = DateFormat('EEEE').format(dt);
      } else {
        label = DateFormat('MMMM d, y').format(dt);
      }
      groups.putIfAbsent(label, () => []).add(log);
    }
    return groups;
  }

  String formatTime(int? ms) {
    if (ms == null) return '';
    return DateFormat('h:mm a').format(DateTime.fromMillisecondsSinceEpoch(ms));
  }

  String callTypeLabel(CallType? t) {
    switch (t) {
      case CallType.incoming:
        return 'Incoming';
      case CallType.outgoing:
        return 'Outgoing';
      case CallType.missed:
        return 'Missed';
      case CallType.rejected:
        return 'Declined';
      default:
        return 'Unknown';
    }
  }

  IconData callTypeIcon(CallType? t) {
    switch (t) {
      case CallType.incoming:
        return Icons.call_received_rounded;
      case CallType.outgoing:
        return Icons.call_made_rounded;
      case CallType.missed:
      case CallType.rejected:
        return Icons.call_missed_rounded;
      default:
        return Icons.call;
    }
  }

  Future<void> dial(BuildContext context, String? number) async {
    if (number == null || number.isEmpty) return;
    HapticFeedback.lightImpact();
    await TelecomService.handleOutgoingCall(context, number);
    await fetchCallLogs();
  }

  Future<void> blockNumber(String number, bool currentlyBlocked) async {
    try {
      if (currentlyBlocked) {
        await FlutterContacts.blockedNumbers.unblock(number);
      } else {
        await FlutterContacts.blockedNumbers.block(number);
      }
      await fetchCallLogs();
    } catch (e) {
      debugPrint('Failed to update blocked status: $e');
    }
  }

  void deleteLog(CallLogEntry log) {
    HapticFeedback.mediumImpact();
    _callLogs?.removeWhere((e) => e.timestamp == log.timestamp && e.number == log.number);
    notifyListeners();
  }
}
