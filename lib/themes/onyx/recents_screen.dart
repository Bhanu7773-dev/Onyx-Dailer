import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:call_log/call_log.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wavedialer/themes/onyx/settings_screen.dart';
import 'package:wavedialer/services/telecom_service.dart';
import 'package:wavedialer/logic/recents_controller.dart';
import 'package:wavedialer/widgets/contact_details_sheet.dart';
import 'package:wavedialer/widgets/contact_dialogs.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'dart:ui';


const _iosBlue = Color(0xFF007AFF);
const _iosRed = Color(0xFFFF3B30);
const _iosBg = Color(0xFF000000);
const _iosCard = Color(0xFF1C1C1E);
const _iosSeparator = Color(0xFF38383A);
const _iosLabel = Color(0xFFFFFFFF);
const _iosSecondary = Color(0xFF8E8E93);
const _iosTertiary = Color(0xFF48484A);

class RecentsScreen extends StatefulWidget {
  const RecentsScreen({super.key});

  @override
  State<RecentsScreen> createState() => _RecentsScreenState();
}

class _RecentsScreenState extends State<RecentsScreen> with WidgetsBindingObserver {
  final RecentsController _controller = RecentsController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_onControllerChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 1), () {
        _controller.fetchCallLogs();
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onControllerChange);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.fetchCallLogs();
    }
  }

  void _onControllerChange() {
    if (mounted) setState(() {});
  }

  void _showSettingsSheet() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    ).then((_) => _controller.fetchCallLogs());
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
    await _controller.dial(context, number);
  }

  Future<void> _openDetails(CallLogEntry log) async {
    final name = (log.name?.isNotEmpty == true) ? log.name! : log.number ?? 'Unknown';
    if (log.number == null || log.number!.isEmpty) return;
    await showContactDetails(
      context,
      name: name,
      phone: log.number!,
    );
    await _controller.fetchCallLogs();
  }

  Future<void> _handleEdit(String? number) async {
    if (number == null) return;
    final contacts = await FlutterContacts.getAll(filter: ContactFilter.phone(number));
    if (contacts.isNotEmpty) {
      ContactDialogs.showEditContact(context, contacts.first, onDone: _controller.fetchCallLogs);
    } else {
      ContactDialogs.showNewContact(context, initialPhone: number, onDone: _controller.fetchCallLogs);
    }
  }

  Future<void> _handleBlock(String? number, String? name) async {
    if (number == null) return;
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

    final blocked = _controller.isNumberBlocked(number);
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: CupertinoAlertDialog(
          title: Text(blocked ? 'Unblock Number' : 'Block Number'),
          content: Text(blocked 
            ? 'Allow calls from ${name ?? number} again?'
            : 'Block ${name ?? number}? You will no longer receive calls from this number.'),
          actions: [
            CupertinoDialogAction(
              child: const Text('Cancel', style: TextStyle(color: _iosBlue)),
              onPressed: () => Navigator.pop(ctx, false),
            ),
            CupertinoDialogAction(
              isDestructiveAction: !blocked,
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(blocked ? 'Unblock' : 'Block'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      await _controller.blockNumber(number, blocked);
    }
  }

  void _deleteLog(CallLogEntry log) {
    _controller.deleteLog(log);
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _controller.getGroupedLogs(_controller.filteredLogs);
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
                      _filterChip('All',      Icons.call_rounded,          CallFilter.all),
                      const SizedBox(width: 8),
                      _filterChip('Incoming', Icons.call_received_rounded,  CallFilter.incoming),
                      const SizedBox(width: 8),
                      _filterChip('Outgoing', Icons.call_made_rounded,      CallFilter.outgoing),
                      const SizedBox(width: 8),
                      _filterChip('Missed',   Icons.call_missed_rounded,    CallFilter.missed),
                      const SizedBox(width: 20),
                    ],
                  ),
                ),
              ),

              // List
              Expanded(
                child: _controller.callLogs == null
                    ? const Center(child: CircularProgressIndicator(color: _iosBlue))
                    : sectionKeys.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.call_outlined, size: 60, color: _iosTertiary),
                                const SizedBox(height: 12),
                                Text(
                                  _controller.filter == CallFilter.missed ? 'No missed calls' :
                                  _controller.filter == CallFilter.incoming ? 'No incoming calls' :
                                  _controller.filter == CallFilter.outgoing ? 'No outgoing calls' :
                                  'No recent calls',
                                  style: const TextStyle(color: _iosSecondary, fontSize: 17),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            color: _iosBlue,
                            backgroundColor: _iosCard,
                            onRefresh: _controller.fetchCallLogs,
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

  Widget _filterChip(String label, IconData icon, CallFilter f) {
    final selected = _controller.filter == f;
    final chipColor = f == CallFilter.missed ? _iosRed
        : f == CallFilter.incoming ? _iosBlue
        : f == CallFilter.outgoing ? const Color(0xFF34C759)
        : _iosBlue;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _controller.setFilter(f);
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
    final missed = _controller.isMissed(log.callType);
    final blocked = _controller.isNumberBlocked(log.number);
    
    String name = (log.name?.isNotEmpty == true) ? log.name! : log.number ?? 'Unknown';
    if (log.name == null || log.name!.isEmpty) {
      if (blocked) name = 'Blocked';
    }

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
            _handleEdit(log.number);
          },
          trailingIcon: CupertinoIcons.pencil,
          child: const Text('Edit'),
        ),
        CupertinoContextMenuAction(
          onPressed: () {
            Navigator.pop(context);
            _handleBlock(log.number, log.name);
          },
          trailingIcon: blocked ? CupertinoIcons.checkmark_circle : CupertinoIcons.slash_circle,
          child: Text(blocked ? 'Unblock' : 'Block'),
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
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              color: nameColor,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w500)),
                                    ),
                                    if (blocked)
                                      const Padding(
                                        padding: EdgeInsets.only(left: 6),
                                        child: Icon(CupertinoIcons.slash_circle_fill, color: _iosRed, size: 12),
                                      ),
                                  ],
                                ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(_controller.callTypeIcon(log.callType),
                                      size: 11, color: missed ? _iosRed : _iosSecondary),
                                  const SizedBox(width: 4),
                                  Text(
                                    _controller.callTypeLabel(log.callType),
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
                          _controller.formatTime(log.timestamp),
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

