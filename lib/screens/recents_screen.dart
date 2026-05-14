import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:call_log/call_log.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wavedialer/screens/call_screen.dart';
import 'package:wavedialer/services/telecom_service.dart';
import 'package:wavedialer/widgets/contact_details_sheet.dart';

// iOS Color Constants
const _iosBlue = Color(0xFF007AFF);
const _iosRed = Color(0xFFFF3B30);
const _iosBg = Color(0xFF000000);
const _iosCard = Color(0xFF1C1C1E);
const _iosSeparator = Color(0xFF38383A);
const _iosLabel = Color(0xFFFFFFFF);
const _iosSecondary = Color(0xFF8E8E93);
const _iosTertiary = Color(0xFF48484A);

// Filter Enum
enum _Filter { all, incoming, outgoing, missed }

class RecentsScreen extends StatefulWidget {
  const RecentsScreen({super.key});

  @override
  State<RecentsScreen> createState() => _RecentsScreenState();
}

class _RecentsScreenState extends State<RecentsScreen> with WidgetsBindingObserver {
  List<CallLogEntry>? _callLogs;
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchCallLogs();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchCallLogs();
    }
  }

  Future<void> _fetchCallLogs() async {
    final entries = await CallLog.get();
    if (mounted) {
      setState(() => _callLogs = List<CallLogEntry>.from(entries));
    }
  }

  bool _isMissed(CallType? t) =>
      t == CallType.missed || t == CallType.rejected;

  List<CallLogEntry> get _filtered {
    if (_callLogs == null) return [];
    switch (_filter) {
      case _Filter.all:      return _callLogs!;
      case _Filter.incoming: return _callLogs!.where((e) => e.callType == CallType.incoming).toList();
      case _Filter.outgoing: return _callLogs!.where((e) => e.callType == CallType.outgoing).toList();
      case _Filter.missed:   return _callLogs!.where((e) => _isMissed(e.callType)).toList();
    }
  }

  // Group entries by date label
  Map<String, List<CallLogEntry>> _grouped(List<CallLogEntry> logs) {
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
        label = DateFormat('EEEE').format(dt); // Monday, Tuesday…
      } else {
        label = DateFormat('MMMM d, y').format(dt);
      }
      groups.putIfAbsent(label, () => []).add(log);
    }
    return groups;
  }

  String _formatTime(int? ms) {
    if (ms == null) return '';
    return DateFormat('h:mm a').format(DateTime.fromMillisecondsSinceEpoch(ms));
  }

  String _callTypeLabel(CallType? t) {
    switch (t) {
      case CallType.incoming: return 'Incoming';
      case CallType.outgoing: return 'Outgoing';
      case CallType.missed:   return 'Missed';
      case CallType.rejected: return 'Declined';
      default: return 'Unknown';
    }
  }

  IconData _callTypeIcon(CallType? t) {
    switch (t) {
      case CallType.incoming: return Icons.call_received_rounded;
      case CallType.outgoing: return Icons.call_made_rounded;
      case CallType.missed:
      case CallType.rejected: return Icons.call_missed_rounded;
      default: return Icons.call;
    }
  }

  void _showSettingsSheet() {
    showDialog(
      context: context,
      builder: (context) => const _SettingsDialog(),
    );
  }

  void _showAboutSheet() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text('About Onyx Dialer',
            style: TextStyle(color: _iosLabel)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(radius: 32, child: Icon(Icons.call, size: 36)),
            const SizedBox(height: 16),
            const Text('Onyx Dialer',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _iosLabel)),
            const Text('Version 1.0.0', style: TextStyle(color: _iosSecondary)),
            const SizedBox(height: 12),
            const Text('A premium dialer with native root-based\ntwo-sided call recording.',
                style: TextStyle(color: _iosLabel)),
            const Divider(color: _iosSeparator, height: 28),
            const Text('Developer',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: _iosSecondary)),
            const SizedBox(height: 6),
            const Text('Billu Builder',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: _iosLabel)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => launchUrl(
                Uri.parse('https://t.me/fitx_updates'),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.send),
              label: const Text('Join Telegram Channel'),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0088CC)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: _iosBlue)),
          ),
        ],
      ),
    );
  }

  Future<void> _dial(String? number) async {
    if (number == null || number.isEmpty) return;
    HapticFeedback.lightImpact();
    TelecomService.makeCall(number);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CallScreen(initialNumber: number)),
    );
    _fetchCallLogs();
  }

  Future<void> _openDetails(CallLogEntry log) async {
    final name = (log.name?.isNotEmpty == true) ? log.name! : log.number ?? 'Unknown';
    if (log.number == null || log.number!.isEmpty) return;
    await showContactDetails(
      context,
      name: name,
      phone: log.number!,
    );
    _fetchCallLogs();
  }

  Future<void> _deleteLog(CallLogEntry log) async {
    HapticFeedback.mediumImpact();
    // For now, we remove it from the local list. 
    // Since we are a root app, we could potentially delete from system provider here.
    setState(() {
      _callLogs?.removeWhere((e) => e.timestamp == log.timestamp && e.number == log.number);
    });
    
    // Optional: Try system delete if root is available
    try {
      final id = log.timestamp; // We use timestamp as a pseudo-id if real id is missing
      if (id != null) {
        // This is a placeholder for actual system deletion logic if needed
        debugPrint('Attempting to delete log entry at $id');
      }
    } catch (e) {
      debugPrint('System delete failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped(_filtered);
    final sectionKeys = grouped.keys.toList();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _iosBg,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Large Title and Three-dots
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 4, 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Expanded(
                      child: Text(
                        'Recents',
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          color: _iosLabel,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: _iosSecondary),
                      color: const Color(0xFF2C2C2E),
                      onSelected: (value) {
                        if (value == 'settings') _showSettingsSheet();
                        if (value == 'about') _showAboutSheet();
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'settings',
                          child: Row(children: [
                            Icon(Icons.settings_outlined, color: _iosLabel),
                            SizedBox(width: 12),
                            Text('Settings', style: TextStyle(color: _iosLabel)),
                          ]),
                        ),
                        const PopupMenuItem(
                          value: 'about',
                          child: Row(children: [
                            Icon(Icons.info_outline, color: _iosLabel),
                            SizedBox(width: 12),
                            Text('About', style: TextStyle(color: _iosLabel)),
                          ]),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Filter Chips
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 0, 12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip('All',      Icons.call_rounded,          _Filter.all),
                      const SizedBox(width: 8),
                      _filterChip('Incoming', Icons.call_received_rounded,  _Filter.incoming),
                      const SizedBox(width: 8),
                      _filterChip('Outgoing', Icons.call_made_rounded,      _Filter.outgoing),
                      const SizedBox(width: 8),
                      _filterChip('Missed',   Icons.call_missed_rounded,    _Filter.missed),
                      const SizedBox(width: 20),
                    ],
                  ),
                ),
              ),

              // List
              Expanded(
                child: _callLogs == null
                    ? const Center(child: CircularProgressIndicator(color: _iosBlue))
                    : sectionKeys.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.call_outlined, size: 60, color: _iosTertiary),
                                const SizedBox(height: 12),
                                Text(
                                  _filter == _Filter.missed ? 'No missed calls' :
                                  _filter == _Filter.incoming ? 'No incoming calls' :
                                  _filter == _Filter.outgoing ? 'No outgoing calls' :
                                  'No recent calls',
                                  style: const TextStyle(color: _iosSecondary, fontSize: 17),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            color: _iosBlue,
                            backgroundColor: _iosCard,
                            onRefresh: _fetchCallLogs,
                            child: ListView.builder(
                              padding: const EdgeInsets.only(bottom: 100),
                              itemCount: sectionKeys.length,
                              itemBuilder: (context, i) =>
                                  _buildSection(sectionKeys[i], grouped[sectionKeys[i]]!),
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterChip(String label, IconData icon, _Filter f) {
    final selected = _filter == f;
    final chipColor = f == _Filter.missed ? _iosRed
        : f == _Filter.incoming ? _iosBlue
        : f == _Filter.outgoing ? const Color(0xFF34C759)
        : _iosBlue;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _filter = f);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? chipColor.withValues(alpha: 0.2) : _iosCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? chipColor : _iosSeparator,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: selected ? chipColor : _iosSecondary),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: selected ? chipColor : _iosSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: _iosSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _buildSection(String label, List<CallLogEntry> entries) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(label),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: _iosCard,
            borderRadius: BorderRadius.circular(13),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Column(
              children: List.generate(entries.length, (i) {
                final isLast = i == entries.length - 1;
                return _callRow(entries[i], isLast: isLast);
              }),
            ),
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _callRow(CallLogEntry log, {required bool isLast}) {
    final missed = _isMissed(log.callType);
    final name = (log.name?.isNotEmpty == true) ? log.name! : log.number ?? 'Unknown';
    final nameColor = missed ? _iosRed : _iosLabel;
    final initial = name.substring(0, 1).toUpperCase();

    return CupertinoContextMenu(
      enableHapticFeedback: true,
      actions: <Widget>[
        CupertinoContextMenuAction(
          onPressed: () {
            Navigator.pop(context);
            _dial(log.number);
          },
          isDefaultAction: true,
          trailingIcon: CupertinoIcons.phone,
          child: const Text('Call'),
        ),
        CupertinoContextMenuAction(
          onPressed: () {
            Navigator.pop(context);
            _deleteLog(log);
          },
          isDestructiveAction: true,
          trailingIcon: CupertinoIcons.trash,
          child: const Text('Delete'),
        ),
      ],
      child: SizedBox(
        width: MediaQuery.of(context).size.width - 32,
        child: GestureDetector(
          onTap: () => _dial(log.number),
          child: Material(
          color: Colors.transparent,
          child: Container(
            color: _iosCard,
            padding: const EdgeInsets.fromLTRB(14, 0, 0, 0),
            child: Row(
              children: [
                // Grey avatar — iOS style
                GestureDetector(
                  onTap: () => _openDetails(log),
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: _iosTertiary,
                    child: Text(
                      initial,
                      style: const TextStyle(
                        fontSize: 18,
                        color: _iosLabel,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Name + subtitle
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      border: isLast
                          ? null
                          : const Border(bottom: BorderSide(color: _iosSeparator, width: 0.4)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name,
                                  style: TextStyle(
                                      color: nameColor,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500)),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(_callTypeIcon(log.callType),
                                      size: 11, color: missed ? _iosRed : _iosSecondary),
                                  const SizedBox(width: 4),
                                  Text(
                                    _callTypeLabel(log.callType),
                                    style: TextStyle(
                                        color: missed ? _iosRed : _iosSecondary,
                                        fontSize: 12),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Time
                        Text(
                          _formatTime(log.timestamp),
                          style: const TextStyle(color: _iosSecondary, fontSize: 13),
                        ),
                        const SizedBox(width: 6),

                        // Info button
                        GestureDetector(
                          onTap: () => _openDetails(log),
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            width: 56, height: 56,
                            color: Colors.transparent,
                            alignment: Alignment.center,
                            child: const Icon(Icons.info_outline_rounded,
                                color: _iosBlue, size: 22),
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

// Settings Dialog

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog();
  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  bool? _isRooted;
  bool _autoRecord = false;

  @override
  void initState() {
    super.initState();
    _checkRoot();
    _loadPrefs();
  }

  Future<void> _checkRoot() async {
    try {
      final result = await Process.run('su', ['-c', 'id']);
      if (mounted) setState(() => _isRooted = result.exitCode == 0);
    } catch (_) {
      if (mounted) setState(() => _isRooted = false);
    }
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _autoRecord = prefs.getBool('auto_record') ?? false);
  }

  Future<void> _toggleAutoRecord(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_record', value);
    if (mounted) setState(() => _autoRecord = value);
  }

  @override
  Widget build(BuildContext context) {
    Widget rootIndicator;
    if (_isRooted == null) {
      rootIndicator = const SizedBox(
        width: 16, height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: _iosBlue),
      );
    } else {
      rootIndicator = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12, height: 12,
            decoration: BoxDecoration(
              color: _isRooted! ? const Color(0xFF34C759) : _iosRed,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _isRooted! ? 'Granted (Magisk/KernelSU)' : 'Not available',
            style: TextStyle(
              color: _isRooted! ? const Color(0xFF34C759) : _iosRed,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    return AlertDialog(
      backgroundColor: _iosCard,
      title: const Text('Settings', style: TextStyle(color: _iosLabel)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Root Access',
              style: TextStyle(color: _iosSecondary, fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          rootIndicator,
          const Divider(color: _iosSeparator, height: 28),
          const Text('Recording',
              style: TextStyle(color: _iosSecondary, fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          const Text('Saves to: /sdcard/Music/OnyxDialer/',
              style: TextStyle(color: _iosTertiary, fontSize: 12)),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-record calls', style: TextStyle(color: _iosLabel)),
            subtitle: const Text('Starts recording when a call connects',
                style: TextStyle(color: _iosSecondary, fontSize: 12)),
            value: _autoRecord,
            activeThumbColor: _iosBlue,
            onChanged: _toggleAutoRecord,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close', style: TextStyle(color: _iosBlue)),
        ),
      ],
    );
  }
}
