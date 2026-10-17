import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:call_log/call_log.dart';
import 'package:intl/intl.dart';
import 'package:wavedialer/logic/recents_controller.dart';
import 'package:wavedialer/widgets/contact_details_sheet.dart';
import 'package:wavedialer/themes/pixel/settings_screen.dart';

// ── Pixel Material 3 Expressive Palette ───────────────────────────────────────
const _kBg = Color(0xFF0B0F14);
const _kCardBg = Color(0xFF11161D);
const _kListContainerBg = Color(0xFF10151C);
const _kAvatarBg = Color(0xFF1C232E);
const _kButtonBg = Color(0xFF1A222D);

const _kBlueAccent = Color(0xFF5B9DFF);
const _kCoralRed = Color(0xFFFF7769);
const _kTerracotta = Color(0xFFB57367);
const _kTextWhite = Color(0xFFFFFFFF);
const _kTextMuted = Color(0xFF8E9CAE);
const _kPillUnselected = Color(0xFF151B24);
const _kSeparator = Color(0xFF1E2836);

class RecentsScreen extends StatefulWidget {
  const RecentsScreen({super.key});

  @override
  State<RecentsScreen> createState() => _RecentsScreenState();
}

class _RecentsScreenState extends State<RecentsScreen> with WidgetsBindingObserver {
  final RecentsController _controller = RecentsController();
  final TextEditingController _searchCtrl = TextEditingController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_onControllerChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.fetchCallLogs();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchCtrl.dispose();
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

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    ).then((_) => _controller.fetchCallLogs());
  }

  void _showOverflowMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _kCardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: _kSeparator,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  _openSettings();
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: _kAvatarBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.settings_outlined, color: _kBlueAccent, size: 22),
                      SizedBox(width: 14),
                      Text('Settings', style: TextStyle(color: _kTextWhite, fontSize: 16, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmClearHistory();
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: _kAvatarBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.delete_sweep_outlined, color: _kCoralRed, size: 22),
                      SizedBox(width: 14),
                      Text('Clear Call History', style: TextStyle(color: _kCoralRed, fontSize: 16, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmClearHistory() {
    showDialog(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: AlertDialog(
          backgroundColor: _kCardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          title: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _kCoralRed.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_sweep_rounded, color: _kCoralRed, size: 26),
              ),
              const SizedBox(height: 14),
              const Text(
                'Clear Call History?',
                style: TextStyle(color: _kTextWhite, fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          content: const Text(
            'This will remove all recent call logs from the view.',
            style: TextStyle(color: _kTextMuted, fontSize: 14, height: 1.4),
            textAlign: TextAlign.center,
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel', style: TextStyle(color: _kTextMuted, fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _kCoralRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _controller.clearAllLogs();
                    },
                    child: const Text('Clear All', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Calculate day summary analytics (counts for outgoing, missed, declined)
  ({String label, int total, int outgoing, int missed, int declined}) _computeAnalytics(List<CallLogEntry> allLogs) {
    if (allLogs.isEmpty) {
      return (label: 'TODAY', total: 0, outgoing: 0, missed: 0, declined: 0);
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    // Try to find logs for today first, if empty check yesterday, else latest day
    List<CallLogEntry> dayLogs = allLogs.where((log) {
      final dt = DateTime.fromMillisecondsSinceEpoch(log.timestamp ?? 0);
      final day = DateTime(dt.year, dt.month, dt.day);
      return day == today;
    }).toList();

    String label = 'TODAY';

    if (dayLogs.isEmpty) {
      dayLogs = allLogs.where((log) {
        final dt = DateTime.fromMillisecondsSinceEpoch(log.timestamp ?? 0);
        final day = DateTime(dt.year, dt.month, dt.day);
        return day == yesterday;
      }).toList();
      label = 'YESTERDAY';
    }

    if (dayLogs.isEmpty) {
      // Take the most recent day from allLogs
      final firstLog = allLogs.first;
      final dt = DateTime.fromMillisecondsSinceEpoch(firstLog.timestamp ?? 0);
      final targetDay = DateTime(dt.year, dt.month, dt.day);
      dayLogs = allLogs.where((log) {
        final d = DateTime.fromMillisecondsSinceEpoch(log.timestamp ?? 0);
        return DateTime(d.year, d.month, d.day) == targetDay;
      }).toList();
      label = DateFormat('MMMM d').format(dt).toUpperCase();
    }

    int outgoing = 0;
    int missed = 0;
    int declined = 0;

    for (final l in dayLogs) {
      if (l.callType == CallType.outgoing) {
        outgoing++;
      } else if (l.callType == CallType.missed) {
        missed++;
      } else if (l.callType == CallType.rejected || l.callType == CallType.blocked) {
        declined++;
      }
    }

    return (
      label: label,
      total: dayLogs.length,
      outgoing: outgoing,
      missed: missed,
      declined: declined,
    );
  }

  @override
  Widget build(BuildContext context) {
    final allLogs = _controller.filteredLogs;
    final query = _searchCtrl.text.trim().toLowerCase();
    final logs = query.isEmpty
        ? allLogs
        : allLogs.where((l) {
            final name = (l.name ?? '').toLowerCase();
            final num = (l.number ?? '').toLowerCase();
            return name.contains(query) || num.contains(query);
          }).toList();

    final analytics = _computeAnalytics(_controller.callLogs ?? []);

    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top Header ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
              child: Row(
                children: [
                  if (_isSearching)
                    Expanded(
                      child: Container(
                        height: 46,
                        decoration: BoxDecoration(
                          color: _kCardBg,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: TextField(
                          controller: _searchCtrl,
                          autofocus: true,
                          style: const TextStyle(color: _kTextWhite, fontSize: 16),
                          decoration: InputDecoration(
                            hintText: 'Search calls...',
                            hintStyle: const TextStyle(color: _kTextMuted),
                            prefixIcon: const Icon(Icons.search, color: _kTextMuted, size: 20),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.close, color: _kTextMuted, size: 18),
                              onPressed: () {
                                setState(() {
                                  _searchCtrl.clear();
                                  _isSearching = false;
                                });
                              },
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    )
                  else ...[
                    const Text(
                      'Recents',
                      style: TextStyle(
                        color: _kTextWhite,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.search, color: _kTextMuted, size: 26),
                      onPressed: () => setState(() => _isSearching = true),
                    ),
                    IconButton(
                      icon: const Icon(Icons.more_vert, color: _kTextMuted, size: 24),
                      onPressed: _showOverflowMenu,
                    ),
                  ],
                ],
              ),
            ),

            // ── Scrollable Body ─────────────────────────────────────────
            Expanded(
              child: _controller.isLoading
                  ? const Center(child: CircularProgressIndicator(color: _kBlueAccent))
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 120),
                      children: [
                        // ── Top Analytics Card ──────────────────────────
                        _buildAnalyticsCard(analytics),

                        const SizedBox(height: 18),

                        // ── Filter Pills Row ────────────────────────────
                        _buildFilterPills(),

                        const SizedBox(height: 16),

                        // ── Call Log Grouped Container ──────────────────
                        if (logs.isEmpty)
                          _buildEmptyState()
                        else
                          _buildCallListContainer(logs),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Analytics Summary Card (YESTERDAY / 8 calls) ──────────────────────────
  Widget _buildAnalyticsCard(({String label, int total, int outgoing, int missed, int declined}) data) {
    final int safeTotal = data.total > 0 ? data.total : 1;
    final double outWeight = data.outgoing / safeTotal;
    final double missedWeight = data.missed / safeTotal;
    final double decWeight = data.declined / safeTotal;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: Title and total calls count
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.label,
                      style: const TextStyle(
                        color: _kTextMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '${data.total}',
                          style: const TextStyle(
                            color: _kTextWhite,
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'calls',
                          style: TextStyle(
                            color: _kTextMuted,
                            fontSize: 18,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Right: Stats breakdown list with colored dots
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLegendDot(color: _kBlueAccent, text: '${data.outgoing} outgoing'),
                  const SizedBox(height: 6),
                  _buildLegendDot(color: _kCoralRed, text: '${data.missed} missed'),
                  const SizedBox(height: 6),
                  _buildLegendDot(color: _kTerracotta, text: '${data.declined} declined'),
                ],
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Horizontal segmented progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: SizedBox(
              height: 7,
              child: data.total == 0
                  ? Container(color: Colors.white10)
                  : Row(
                      children: [
                        if (data.outgoing > 0)
                          Expanded(
                            flex: (outWeight * 1000).toInt(),
                            child: Container(
                              margin: const EdgeInsets.only(right: 3),
                              decoration: BoxDecoration(
                                color: _kBlueAccent,
                                borderRadius: BorderRadius.circular(100),
                              ),
                            ),
                          ),
                        if (data.missed > 0)
                          Expanded(
                            flex: (missedWeight * 1000).toInt(),
                            child: Container(
                              margin: const EdgeInsets.only(right: 3),
                              decoration: BoxDecoration(
                                color: _kCoralRed,
                                borderRadius: BorderRadius.circular(100),
                              ),
                            ),
                          ),
                        if (data.declined > 0)
                          Expanded(
                            flex: (decWeight * 1000).toInt(),
                            child: Container(
                              decoration: BoxDecoration(
                                color: _kTerracotta,
                                borderRadius: BorderRadius.circular(100),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendDot({required Color color, required String text}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            color: _kTextMuted,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ── Filter Chips Row ──────────────────────────────────────────────────────
  Widget _buildFilterPills() {
    final filters = [
      (label: 'All', filter: CallFilter.all),
      (label: 'Incoming', filter: CallFilter.incoming),
      (label: 'Outgoing', filter: CallFilter.outgoing),
      (label: 'Missed', filter: CallFilter.missed),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: filters.map((item) {
          final isSelected = _controller.filter == item.filter;
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                _controller.setFilter(item.filter);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : _kPillUnselected,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(
                  item.label,
                  style: TextStyle(
                    color: isSelected ? Colors.black : _kTextMuted,
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Call List Grouped Container ───────────────────────────────────────────
  Widget _buildCallListContainer(List<CallLogEntry> logs) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: _kListContainerBg,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: logs.length,
        separatorBuilder: (_, _) => const SizedBox(height: 2),
        itemBuilder: (context, index) {
          final log = logs[index];
          return _buildCallItem(log);
        },
      ),
    );
  }

  Widget _buildCallItem(CallLogEntry log) {
    final displayName = (log.name != null && log.name!.isNotEmpty)
        ? log.name!
        : (log.number != null && log.number!.isNotEmpty ? log.number! : 'Unknown');

    final isMissed = log.callType == CallType.missed;
    final isDeclined = log.callType == CallType.rejected || log.callType == CallType.blocked;
    final isOutgoing = log.callType == CallType.outgoing;

    // Subtitle arrow & color
    Color typeColor;
    String typeText;
    IconData typeIcon;

    if (isMissed) {
      typeColor = _kCoralRed;
      typeText = 'Missed';
      typeIcon = Icons.south_west_rounded;
    } else if (isDeclined) {
      typeColor = _kTerracotta;
      typeText = 'Declined';
      typeIcon = Icons.south_west_rounded;
    } else if (isOutgoing) {
      typeColor = _kTextMuted;
      typeText = 'Outgoing';
      typeIcon = Icons.north_east_rounded;
    } else {
      typeColor = _kTextMuted;
      typeText = 'Incoming';
      typeIcon = Icons.south_west_rounded;
    }

    // Avatar Initial
    final initial = displayName.trim().isNotEmpty
        ? displayName.trim().substring(0, 1).toUpperCase()
        : '?';

    final timeStr = _controller.formatTime(log.timestamp);

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        if (log.number != null && log.number!.isNotEmpty) {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => ContactDetailsSheet(
              name: displayName,
              phone: log.number!,
            ),
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Circular Avatar with Initial
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: _kAvatarBg,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: _kTextWhite,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(width: 14),

            // Contact Name & Call Type
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      // Coral name for missed calls, white for others
                      color: isMissed ? _kCoralRed : _kTextWhite,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(typeIcon, size: 14, color: typeColor),
                      const SizedBox(width: 4),
                      Text(
                        typeText,
                        style: TextStyle(
                          color: typeColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Timestamp
            Text(
              timeStr,
              style: const TextStyle(
                color: _kTextMuted,
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),

            const SizedBox(width: 14),

            // Call Action Button
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _controller.dial(context, log.number);
              },
              child: Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: _kButtonBg,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.call_outlined,
                  color: _kTextWhite,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: _kListContainerBg,
        borderRadius: BorderRadius.circular(28),
      ),
      child: const Center(
        child: Column(
          children: [
            Icon(Icons.history_rounded, size: 48, color: _kTextMuted),
            SizedBox(height: 16),
            Text(
              'No recent calls found',
              style: TextStyle(color: _kTextWhite, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 6),
            Text(
              'Calls you make or receive will appear here.',
              style: TextStyle(color: _kTextMuted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
