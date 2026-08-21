import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:call_log/call_log.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:intl/intl.dart';
import 'package:wavedialer/logic/recents_controller.dart';
import 'package:wavedialer/logic/profile_service.dart';
import 'package:wavedialer/services/telecom_service.dart';
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

class RecentsScreen extends StatefulWidget {
  const RecentsScreen({super.key});

  @override
  State<RecentsScreen> createState() => _RecentsScreenState();
}

class _RecentsScreenState extends State<RecentsScreen> with WidgetsBindingObserver {
  final RecentsController _controller = RecentsController();
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  
  Uint8List? _myAvatar;
  bool _missedOnly = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_onControllerChange);
    _loadProfileAvatar();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.fetchCallLogs();
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
    WidgetsBinding.instance.removeObserver(this);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _controller.removeListener(_onControllerChange);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.fetchCallLogs();
      _loadProfileAvatar();
    }
  }

  void _onControllerChange() {
    if (mounted) setState(() {});
  }

  void _dial(String number) {
    _searchFocus.unfocus();
    HapticFeedback.lightImpact();
    TelecomService.handleOutgoingCall(context, number);
  }

  void _showLogOptions(CallLogEntry log, String displayName, String? photoUrl) {
    HapticFeedback.heavyImpact();
    final number = log.number ?? '';
    final isBlocked = _controller.isNumberBlocked(number);
    final hasContact = log.name != null && log.name!.trim().isNotEmpty;

    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: CupertinoActionSheet(
          title: Text(
            displayName.toUpperCase(),
            style: const TextStyle(
              color: _nLabel,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
              fontSize: 16,
              fontFamily: 'NothingFont',
            ),
          ),
          message: number.isNotEmpty
              ? Text(number, style: const TextStyle(color: _nSecondary, fontSize: 13))
              : null,
          actions: [
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                _dial(number);
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
            if (!hasContact && number.isNotEmpty)
              CupertinoActionSheetAction(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final c = Contact(phones: [Phone(number: number)]);
                  await FlutterContacts.native.showCreator(contact: c);
                  _controller.fetchCallLogs();
                },
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.person_add_outlined, color: _nLabel, size: 20),
                    SizedBox(width: 10),
                    Text('Add to Contacts', style: TextStyle(color: _nLabel, fontFamily: 'NothingFont')),
                  ],
                ),
              ),
            if (number.isNotEmpty)
              CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.pop(ctx);
                  showContactDetails(
                    context,
                    name: displayName,
                    phone: number,
                    avatarColor: _nCard,
                    avatarTextColor: _nLabel,
                  );
                },
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.info_outline_rounded, color: _nLabel, size: 20),
                    SizedBox(width: 10),
                    Text('View Details', style: TextStyle(color: _nLabel, fontFamily: 'NothingFont')),
                  ],
                ),
              ),
            if (number.isNotEmpty)
              CupertinoActionSheetAction(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final confirmed = await NothingDialogs.showConfirmDialog(
                    context: context,
                    title: isBlocked ? 'Unblock Number' : 'Block Number',
                    message: isBlocked
                        ? 'Allow calls from $number again?'
                        : 'Reject incoming calls and messages from $number?',
                    confirmLabel: isBlocked ? 'UNBLOCK' : 'BLOCK',
                    isDestructive: !isBlocked,
                  );
                  if (confirmed == true) {
                    await _controller.blockNumber(number, isBlocked);
                  }
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(isBlocked ? CupertinoIcons.checkmark_circle : CupertinoIcons.slash_circle, color: _nLabel, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      isBlocked ? 'Unblock Number' : 'Block Number',
                      style: const TextStyle(color: _nLabel, fontFamily: 'NothingFont'),
                    ),
                  ],
                ),
              ),
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () async {
                Navigator.pop(ctx);
                final confirmed = await NothingDialogs.showConfirmDialog(
                  context: context,
                  title: 'Delete Call Log',
                  message: 'Remove this call record from your history?',
                  confirmLabel: 'DELETE',
                  isDestructive: true,
                );
                if (confirmed == true) {
                  _controller.deleteLog(log);
                }
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.trash, color: _nRed, size: 20),
                  SizedBox(width: 10),
                  Text('Delete Log', style: TextStyle(color: _nRed, fontFamily: 'NothingFont')),
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

  void _clearAllLogs() async {
    final confirmed = await NothingDialogs.showConfirmDialog(
      context: context,
      title: 'Clear Call History',
      message: 'Are you sure you want to clear your entire call history?\nThis cannot be undone.',
      confirmLabel: 'CLEAR ALL',
      isDestructive: true,
    );
    if (confirmed == true) {
      _controller.clearAllLogs();
    }
  }

  Widget _getCallTypeIcon(CallType? type) {
    switch (type) {
      case CallType.incoming:
        return const Icon(Icons.call_received_rounded, size: 14, color: _nSecondary);
      case CallType.outgoing:
        return const Icon(Icons.call_made_rounded, size: 14, color: _nSecondary);
      case CallType.missed:
        return const Icon(Icons.call_missed_rounded, size: 14, color: _nRed);
      case CallType.rejected:
        return const Icon(Icons.call_missed_outgoing_rounded, size: 14, color: _nRed);
      case CallType.blocked:
        return const Icon(Icons.block_rounded, size: 14, color: _nSecondary);
      default:
        return const Icon(Icons.call_rounded, size: 14, color: _nSecondary);
    }
  }

  String _formatTimestamp(int? timestamp) {
    if (timestamp == null) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return DateFormat('hh:mm a').format(dt);
    } else if (now.difference(dt).inDays < 7) {
      return DateFormat('EEE, hh:mm a').format(dt);
    } else {
      return DateFormat('MMM d, hh:mm a').format(dt);
    }
  }

  @override
  Widget build(BuildContext context) {
    var logs = _controller.callLogs ?? [];
    if (_missedOnly) {
      logs = logs.where((l) => l.callType == CallType.missed || l.callType == CallType.rejected).toList();
    }
    if (_searchCtrl.text.isNotEmpty) {
      final q = _searchCtrl.text.toLowerCase();
      logs = logs.where((l) {
        final name = (l.name ?? '').toLowerCase();
        final number = (l.number ?? '').toLowerCase();
        return name.contains(q) || number.contains(q);
      }).toList();
    }

    final count = logs.length;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top Bar: Back/Menu + RECENTS + Google Profile Avatar
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
                    'RECENTS',
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

            // Search Bar with Clear History Action Button
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
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(color: _nLabel, fontSize: 15, letterSpacing: 1, fontFamily: 'NothingFont'),
                        cursorColor: _nRed,
                        decoration: const InputDecoration(
                          hintText: 'SEARCH RECENTS',
                          hintStyle: TextStyle(
                            color: _nSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.5,
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
                          setState(() {});
                        },
                        child: const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(Icons.close, color: _nSecondary, size: 18),
                        ),
                      ),
                    // Trash button to Clear History
                    GestureDetector(
                      onTap: _clearAllLogs,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(
                          color: Color(0xFF262626),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(CupertinoIcons.trash, color: _nSecondary, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Subheader: Filter Pill (All / Missed) + Total Count Badge
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
              child: Row(
                children: [
                  // ALL filter pill
                  GestureDetector(
                    onTap: () => setState(() => _missedOnly = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: !_missedOnly ? _nRed.withValues(alpha: 0.18) : const Color(0xFF141414),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: !_missedOnly ? _nRed : const Color(0xFF2C2C2C),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        'ALL',
                        style: TextStyle(
                          color: !_missedOnly ? _nRed : _nSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'NothingFont',
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // MISSED filter pill
                  GestureDetector(
                    onTap: () => setState(() => _missedOnly = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: _missedOnly ? _nRed.withValues(alpha: 0.18) : const Color(0xFF141414),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _missedOnly ? _nRed : const Color(0xFF2C2C2C),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        'MISSED',
                        style: TextStyle(
                          color: _missedOnly ? _nRed : _nSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'NothingFont',
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Total Count Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141414),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF2C2C2C), width: 1),
                    ),
                    child: Text(
                      'Total: $count',
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

            // Call Logs List
            Expanded(
              child: _controller.isLoading
                  ? const Center(child: CircularProgressIndicator(color: _nRed, strokeWidth: 2))
                  : logs.isEmpty
                      ? Center(
                          child: Text(
                            _missedOnly ? 'NO MISSED CALLS' : 'NO CALL HISTORY',
                            style: const TextStyle(
                              color: _nSecondary,
                              letterSpacing: 2,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'NothingFont',
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                          itemCount: logs.length,
                          separatorBuilder: (ctx, i) => const Divider(color: _nDivider, height: 1, indent: 56),
                          itemBuilder: (ctx, i) {
                            final log = logs[i];
                            final name = (log.name != null && log.name!.trim().isNotEmpty)
                                ? log.name!.toUpperCase()
                                : (log.number ?? 'UNKNOWN');
                            final number = log.number ?? '';
                            final isMissed = log.callType == CallType.missed || log.callType == CallType.rejected;
                            final initial = (name.isNotEmpty && RegExp(r'[A-Za-z]').hasMatch(name[0]))
                                ? name[0].toUpperCase()
                                : '#';

                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => _dial(number),
                                onLongPress: () => _showLogOptions(log, name, null),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  height: 60,
                                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                                  child: Row(
                                    children: [
                                      // Stadium Avatar
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF202020),
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(color: const Color(0xFF2C2C2C), width: 1),
                                        ),
                                        child: Center(
                                          child: Text(
                                            initial,
                                            style: TextStyle(
                                              color: isMissed ? _nRed : _nLabel,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 16,
                                              fontFamily: 'NothingFont',
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: isMissed ? _nRed : _nLabel,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: 1.2,
                                                fontFamily: 'NothingFont',
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Row(
                                              children: [
                                                _getCallTypeIcon(log.callType),
                                                const SizedBox(width: 6),
                                                Text(
                                                  _formatTimestamp(log.timestamp),
                                                  style: const TextStyle(
                                                    color: _nSecondary,
                                                    fontSize: 12,
                                                    fontFamily: 'NothingFont',
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Quick Call Button
                                      IconButton(
                                        icon: const Icon(Icons.call_outlined, color: _nSecondary, size: 20),
                                        onPressed: () => _dial(number),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
