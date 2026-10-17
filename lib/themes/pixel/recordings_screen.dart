import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:wavedialer/logic/recordings_controller.dart';
import 'package:wavedialer/services/telecom_service.dart';

const _kBg = Color(0xFF0C0E12);
const _kCardBg = Color(0xFF161D26);
const _kAvatarBg = Color(0xFF1E2632);
const _kBlueAccent = Color(0xFF8AB4F8);
const _kCoralRed = Color(0xFFFF7769);
const _kTextWhite = Color(0xFFFFFFFF);
const _kTextMuted = Color(0xFF8E9CAE);
const _kSeparator = Color(0xFF1E2530);
const _kControlBg = Color(0xFF1F2733);

class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> with WidgetsBindingObserver {
  final RecordingsController _controller = RecordingsController();
  final TextEditingController _searchCtrl = TextEditingController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.init();
    _controller.addListener(_onControllerChange);
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
      _controller.loadRecordings();
    }
  }

  void _onControllerChange() {
    if (mounted) setState(() {});
  }

  Future<void> _deleteRecording(RecordingItem item) async {
    HapticFeedback.mediumImpact();
    final displayName = item.contact?.displayName ?? item.number;
    final confirmed = await showDialog<bool>(
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
                child: const Icon(Icons.delete_outline_rounded, color: _kCoralRed, size: 26),
              ),
              const SizedBox(height: 14),
              const Text(
                'Delete Recording?',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          content: Text(
            'Delete the recording for $displayName?\nThis action cannot be undone.',
            style: const TextStyle(color: _kTextMuted, fontSize: 14, height: 1.4),
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
                    onPressed: () => Navigator.pop(ctx, false),
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
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      await _controller.deleteRecording(item);
    }
  }

  void _callContact(String number) {
    HapticFeedback.lightImpact();
    TelecomService.handleOutgoingCall(context, number);
  }

  double _computeTotalMb(List<RecordingItem> recordings) {
    double bytes = 0;
    for (final r in recordings) {
      try {
        if (r.file.existsSync()) {
          bytes += r.file.lengthSync();
        }
      } catch (_) {}
    }
    return bytes / (1024 * 1024);
  }

  String _latestDateStr(List<RecordingItem> recordings) {
    if (recordings.isEmpty) return 'None';
    final dt = recordings.first.timestamp;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDate = DateTime(dt.year, dt.month, dt.day);
    if (today == itemDate) return 'Today';
    if (today.subtract(const Duration(days: 1)) == itemDate) return 'Yesterday';
    return DateFormat('MMM d').format(dt);
  }

  String _formatFileSize(File file) {
    try {
      if (file.existsSync()) {
        final mb = file.lengthSync() / (1024 * 1024);
        if (mb >= 1.0) {
          return '${mb.toStringAsFixed(1)} MB';
        } else {
          final kb = file.lengthSync() / 1024;
          return '${kb.toStringAsFixed(0)} KB';
        }
      }
    } catch (_) {}
    return '0 KB';
  }

  @override
  Widget build(BuildContext context) {
    final all = _controller.allRecordings;
    final list = _controller.filteredRecordings;
    final totalMb = _computeTotalMb(all).toStringAsFixed(1);
    final latestDate = _latestDateStr(all);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: _kBg,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
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
                            border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                          ),
                          child: TextField(
                            controller: _searchCtrl,
                            autofocus: true,
                            style: const TextStyle(color: _kTextWhite, fontSize: 16),
                            decoration: InputDecoration(
                              hintText: 'Search recordings...',
                              hintStyle: const TextStyle(color: _kTextMuted),
                              prefixIcon: const Icon(Icons.search, color: _kTextMuted, size: 20),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.close, color: _kTextMuted, size: 18),
                                onPressed: () {
                                  setState(() {
                                    _searchCtrl.clear();
                                    _controller.rebuild('');
                                    _isSearching = false;
                                  });
                                },
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onChanged: (v) => _controller.rebuild(v),
                          ),
                        ),
                      )
                    else ...[
                      const Text(
                        'Recordings',
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
                        icon: const Icon(Icons.refresh_rounded, color: _kTextMuted, size: 24),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          _controller.loadRecordings();
                        },
                      ),
                    ],
                  ],
                ),
              ),

              // ── Scrollable Body ─────────────────────────────────────────
              Expanded(
                child: _controller.isLoading
                    ? const Center(child: CircularProgressIndicator(color: _kBlueAccent))
                    : RefreshIndicator(
                        onRefresh: _controller.loadRecordings,
                        color: _kBlueAccent,
                        backgroundColor: _kCardBg,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                          padding: const EdgeInsets.only(bottom: 120),
                          children: [
                            // ── Top Summary Analytics Card ────────────────
                            _buildAnalyticsCard(
                              totalCount: all.length,
                              totalMb: totalMb,
                              latestDate: latestDate,
                            ),

                            const SizedBox(height: 16),

                            // ── Recordings List Container ─────────────────
                            if (list.isEmpty)
                              _buildEmptyState()
                            else
                              _buildRecordingsContainer(list),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Hero Storage & Stats Card ─────────────────────────────────────────────
  Widget _buildAnalyticsCard({
    required int totalCount,
    required String totalMb,
    required String latestDate,
  }) {
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
              // Left: Title and total count
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CALL RECORDINGS',
                      style: TextStyle(
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
                          '$totalCount',
                          style: const TextStyle(
                            color: _kTextWhite,
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'recorded',
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

              // Right: Stats breakdown with dots
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLegendDot(color: _kBlueAccent, text: '$totalMb MB storage'),
                  const SizedBox(height: 6),
                  _buildLegendDot(color: const Color(0xFF34C759), text: 'Latest: $latestDate'),
                ],
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Horizontal wave progress accent
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(100),
              ),
              child: totalCount == 0
                  ? const SizedBox.shrink()
                  : Row(
                      children: [
                        Expanded(
                          flex: 7,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [_kBlueAccent, Color(0xFF6EA8FE)],
                              ),
                              borderRadius: BorderRadius.circular(100),
                            ),
                          ),
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          flex: 3,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
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

  // ── Recordings Grouped List Container ─────────────────────────────────────
  Widget _buildRecordingsContainer(List<RecordingItem> list) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: list.length,
        separatorBuilder: (_, _) => Container(
          margin: const EdgeInsets.only(left: 74, right: 16),
          height: 0.6,
          color: _kSeparator,
        ),
        itemBuilder: (context, index) {
          final item = list[index];
          final isExpanded = _controller.expandedItem?.file.path == item.file.path;
          final isPlayingThis = _controller.currentlyPlaying?.file.path == item.file.path;

          return _buildRecordingTile(item, isExpanded: isExpanded, isPlaying: isPlayingThis);
        },
      ),
    );
  }

  Widget _buildRecordingTile(
    RecordingItem item, {
    required bool isExpanded,
    required bool isPlaying,
  }) {
    final displayName = item.contact?.displayName ?? item.number;
    final initial = displayName.trim().isNotEmpty ? displayName.trim()[0].toUpperCase() : '#';
    final dateStr = DateFormat('MMM d • h:mm a').format(item.timestamp);
    final sizeStr = _formatFileSize(item.file);

    return Column(
      children: [
        // Main Item Header Row
        InkWell(
          onTap: () => _controller.toggleExpand(item),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // Avatar with Initial
                Container(
                  width: 46,
                  height: 46,
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

                // Contact Name & Date / File Size
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _kTextWhite,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            dateStr,
                            style: const TextStyle(color: _kTextMuted, fontSize: 13),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: 3,
                            height: 3,
                            decoration: const BoxDecoration(color: _kTextMuted, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            sizeStr,
                            style: const TextStyle(color: _kTextMuted, fontSize: 13),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Quick Play Circle Button
                GestureDetector(
                  onTap: () => _controller.playOrPause(item),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: isPlaying && _controller.isPlaying
                          ? _kBlueAccent
                          : _kAvatarBg,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isPlaying && _controller.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: isPlaying && _controller.isPlaying
                          ? const Color(0xFF09182C)
                          : _kBlueAccent,
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Expanded Audio Player Controls
        if (isExpanded)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1B2431),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isPlaying ? _kBlueAccent.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.04),
                ),
              ),
              child: Column(
                children: [
                  // Progress Slider
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                      activeTrackColor: _kBlueAccent,
                      inactiveTrackColor: Colors.white.withValues(alpha: 0.08),
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: isPlaying ? _controller.position.inMilliseconds.toDouble() : 0.0,
                      min: 0.0,
                      max: isPlaying && _controller.duration.inMilliseconds > 0
                          ? _controller.duration.inMilliseconds.toDouble()
                          : 1.0,
                      onChanged: isPlaying
                          ? (v) => _controller.audioPlayer.seek(Duration(milliseconds: v.toInt()))
                          : null,
                    ),
                  ),

                  // Duration text labels
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isPlaying ? _controller.formatDuration(_controller.position) : '00:00',
                          style: const TextStyle(color: _kTextMuted, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                        Text(
                          isPlaying
                              ? '-${_controller.formatDuration(_controller.duration - _controller.position)}'
                              : (item.duration != null ? _controller.formatDuration(item.duration!) : '--:--'),
                          style: const TextStyle(color: _kTextMuted, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Controls Row: Delete, Rewind, Play/Pause, Forward, Call
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Delete
                      GestureDetector(
                        onTap: () => _deleteRecording(item),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            color: _kControlBg,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.delete_outline_rounded,
                            color: _kCoralRed,
                            size: 22,
                          ),
                        ),
                      ),

                      // Rewind 10s
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          if (isPlaying) {
                            final newPos = _controller.position - const Duration(seconds: 10);
                            _controller.audioPlayer.seek(newPos < Duration.zero ? Duration.zero : newPos);
                          }
                        },
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            color: _kControlBg,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.replay_10_rounded,
                            color: isPlaying ? Colors.white : _kTextMuted,
                            size: 22,
                          ),
                        ),
                      ),

                      // Large Center Play / Pause
                      GestureDetector(
                        onTap: () => _controller.playOrPause(item),
                        child: Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: _kBlueAccent,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: _kBlueAccent.withValues(alpha: 0.35),
                                blurRadius: 18,
                                spreadRadius: 1,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(
                            isPlaying && _controller.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: const Color(0xFF09182C),
                            size: 34,
                          ),
                        ),
                      ),

                      // Forward 10s
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          if (isPlaying) {
                            final newPos = _controller.position + const Duration(seconds: 10);
                            _controller.audioPlayer.seek(newPos > _controller.duration ? _controller.duration : newPos);
                          }
                        },
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            color: _kControlBg,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.forward_10_rounded,
                            color: isPlaying ? Colors.white : _kTextMuted,
                            size: 22,
                          ),
                        ),
                      ),

                      // Call Contact Back
                      GestureDetector(
                        onTap: () => _callContact(item.number),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            color: _kControlBg,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.call_outlined,
                            color: _kBlueAccent,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.mic_none_rounded, size: 52, color: _kTextMuted),
            const SizedBox(height: 16),
            Text(
              _controller.searchQuery.isEmpty ? 'No recordings yet' : 'No matching recordings',
              style: const TextStyle(color: _kTextWhite, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              _controller.searchQuery.isEmpty
                  ? 'Call recordings made during phone calls will appear here automatically.'
                  : 'Try searching with a different contact name or phone number.',
              style: const TextStyle(color: _kTextMuted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
