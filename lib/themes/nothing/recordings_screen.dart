import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:wavedialer/logic/recordings_controller.dart';
import 'package:wavedialer/logic/profile_service.dart';
import 'package:wavedialer/themes/nothing/nothing_dialogs.dart';

// Nothing UI Colors
const _bg = Color(0xFF000000);
const _nCard = Color(0xFF161616);
const _nSearchBg = Color(0xFF1C1C1E);
const _nLabel = Color(0xFFFFFFFF);
const _nSecondary = Color(0xFF7E7E7E);
const _nDivider = Color(0xFF222222);
const _nRed = Color(0xFFE5162A);

class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> with WidgetsBindingObserver {
  final RecordingsController _controller = RecordingsController();
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Uint8List? _myAvatar;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.init();
    _controller.addListener(_onControllerChange);
    _loadProfileAvatar();
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
      _controller.loadRecordings();
      _loadProfileAvatar();
    }
  }

  void _onControllerChange() {
    if (mounted) setState(() {});
  }

  Future<void> _deleteRecording(RecordingItem item) async {
    HapticFeedback.mediumImpact();
    final displayName = item.contact?.displayName ?? item.number;
    final confirmed = await NothingDialogs.showConfirmDialog(
      context: context,
      title: 'Delete Recording',
      message: 'Delete the call recording for $displayName?\nThis cannot be undone.',
      confirmLabel: 'DELETE',
      isDestructive: true,
    );

    if (confirmed == true) {
      await _controller.deleteRecording(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _controller.filteredRecordings.length;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top Bar: Back icon + RECORDINGS title + Profile Avatar
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
                    'RECORDINGS',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: _nLabel,
                      letterSpacing: 3.5,
                      fontFamily: 'NothingFont',
                    ),
                  ),
                  const Spacer(),
                  // User Profile Avatar (Tap to open Settings / About)
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

            // Search Bar
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
                        onChanged: (v) => _controller.rebuild(v),
                        style: const TextStyle(color: _nLabel, fontSize: 15, letterSpacing: 1, fontFamily: 'NothingFont'),
                        cursorColor: _nRed,
                        decoration: const InputDecoration(
                          hintText: 'SEARCH RECORDINGS',
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
                          _controller.rebuild('');
                          _searchFocus.unfocus();
                        },
                        child: const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(Icons.close, color: _nSecondary, size: 18),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Subheader: Total Count Badge
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Row(
                children: [
                  const Text(
                    'CALL LOG AUDIO',
                    style: TextStyle(
                      color: _nSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      fontFamily: 'NothingFont',
                    ),
                  ),
                  const Spacer(),
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

            // Recordings List
            Expanded(
              child: _controller.isLoading
                  ? const Center(child: CircularProgressIndicator(color: _nRed, strokeWidth: 2))
                  : _controller.allRecordings.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.mic_none_rounded, size: 48, color: _nSecondary),
                              SizedBox(height: 12),
                              Text(
                                'NO RECORDINGS YET',
                                style: TextStyle(
                                  color: _nSecondary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                  fontFamily: 'NothingFont',
                                ),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _controller.loadRecordings,
                          color: _nRed,
                          backgroundColor: _nCard,
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                            itemCount: _controller.filteredRecordings.length,
                            itemBuilder: (context, index) {
                              final item = _controller.filteredRecordings[index];
                              final isExpanded = _controller.expandedItem?.file.path == item.file.path;
                              final isPlayingThis = _controller.currentlyPlaying?.file.path == item.file.path;

                              return _buildRecordingCard(item, isExpanded, isPlayingThis);
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingCard(RecordingItem item, bool isExpanded, bool isPlayingThis) {
    final displayName = (item.contact?.displayName ?? item.number).toUpperCase();
    final dateStr = DateFormat('MMM d, yyyy • hh:mm a').format(item.timestamp);
    final fileSizeMb = (item.file.lengthSync() / 1024 / 1024).toStringAsFixed(2);
    final initial = displayName.trim().isEmpty ? '#' : displayName.trim()[0];

    final currentPos = isPlayingThis ? _controller.position : Duration.zero;
    final totalDur = isPlayingThis && _controller.duration > Duration.zero
        ? _controller.duration
        : (item.duration ?? const Duration(seconds: 1));

    final progress = totalDur.inMilliseconds > 0
        ? (currentPos.inMilliseconds / totalDur.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _nCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isExpanded ? _nRed.withValues(alpha: 0.5) : const Color(0xFF242424),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Header Row
          InkWell(
            onTap: () => _controller.toggleExpand(item),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  // Stadium Avatar
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: isPlayingThis ? _nRed.withValues(alpha: 0.15) : const Color(0xFF222222),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isPlayingThis ? _nRed : const Color(0xFF303030),
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        initial,
                        style: TextStyle(
                          color: isPlayingThis ? _nRed : _nLabel,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'NothingFont',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isPlayingThis ? _nRed : _nLabel,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                            fontFamily: 'NothingFont',
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$dateStr • ${fileSizeMb}MB',
                          style: const TextStyle(
                            color: _nSecondary,
                            fontSize: 11,
                            fontFamily: 'NothingFont',
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: _nSecondary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

          // Audio Player Controls (When Expanded)
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  const Divider(color: _nDivider, height: 1),
                  const SizedBox(height: 14),

                  // Custom Nothing Seek Bar (Solid Red Filled Line + Grey Dotted Unfilled Line)
                  NothingSeekBar(
                    progress: progress,
                    onSeek: (newPercent) {
                      if (isPlayingThis && totalDur.inMilliseconds > 0) {
                        final seekMs = (newPercent * totalDur.inMilliseconds).toInt();
                        _controller.audioPlayer.seek(Duration(milliseconds: seekMs));
                      }
                    },
                  ),
                  const SizedBox(height: 6),

                  // Time Readouts in NothingFont
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isPlayingThis ? _controller.formatDuration(_controller.position) : '00:00',
                          style: const TextStyle(color: _nSecondary, fontSize: 11, fontFamily: 'NothingFont'),
                        ),
                        Text(
                          isPlayingThis
                              ? '-${_controller.formatDuration(_controller.duration - _controller.position)}'
                              : (item.duration != null ? _controller.formatDuration(item.duration!) : '--:--'),
                          style: const TextStyle(color: _nSecondary, fontSize: 11, fontFamily: 'NothingFont'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Playback Controls Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Delete Recording Button
                      IconButton(
                        onPressed: () => _deleteRecording(item),
                        icon: const Icon(Icons.delete_outline_rounded, color: _nRed, size: 22),
                      ),
                      const Spacer(),

                      // Rewind 15s
                      IconButton(
                        onPressed: () {
                          if (isPlayingThis) {
                            final newPos = _controller.position - const Duration(seconds: 15);
                            _controller.audioPlayer.seek(newPos < Duration.zero ? Duration.zero : newPos);
                          }
                        },
                        icon: const Icon(Icons.replay_10_rounded, color: _nLabel, size: 28),
                      ),
                      const SizedBox(width: 8),

                      // Large Nothing Play/Pause Button
                      GestureDetector(
                        onTap: () => _controller.playOrPause(item),
                        child: Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: isPlayingThis && _controller.isPlaying ? _nRed : _nLabel,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Icon(
                              isPlayingThis && _controller.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: isPlayingThis && _controller.isPlaying ? Colors.white : Colors.black,
                              size: 32,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Forward 15s
                      IconButton(
                        onPressed: () {
                          if (isPlayingThis) {
                            final newPos = _controller.position + const Duration(seconds: 15);
                            _controller.audioPlayer.seek(newPos > _controller.duration ? _controller.duration : newPos);
                          }
                        },
                        icon: const Icon(Icons.forward_10_rounded, color: _nLabel, size: 28),
                      ),
                      const Spacer(),

                      // Empty spacer to balance delete button
                      const SizedBox(width: 48),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Custom Nothing UI Seek Bar:
/// - Filled portion: Solid crisp Red Line (No dots)
/// - Unfilled front portion: Grey Dots
class NothingSeekBar extends StatelessWidget {
  final double progress; // 0.0 to 1.0
  final ValueChanged<double>? onSeek;

  const NothingSeekBar({
    super.key,
    required this.progress,
    this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            final dx = details.localPosition.dx.clamp(0.0, width);
            onSeek?.call(dx / width);
          },
          onHorizontalDragUpdate: (details) {
            final dx = details.localPosition.dx.clamp(0.0, width);
            onSeek?.call(dx / width);
          },
          child: SizedBox(
            height: 22,
            width: double.infinity,
            child: CustomPaint(
              painter: _NothingSeekBarPainter(progress.clamp(0.0, 1.0)),
            ),
          ),
        );
      },
    );
  }
}

class _NothingSeekBarPainter extends CustomPainter {
  final double progress;

  _NothingSeekBarPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final totalWidth = size.width;
    final currentX = progress * totalWidth;

    // 1. Draw Stationary Grey Dots on fixed grid positions across the seekbar
    final dotPaint = Paint()
      ..color = const Color(0xFF555555)
      ..style = PaintingStyle.fill;

    const dotSpacing = 7.0;
    const dotRadius = 1.5;

    // Fixed absolute positions along the seekbar
    for (double x = 0.0; x <= totalWidth; x += dotSpacing) {
      // Only draw the dot if it is ahead of the solid red fill (stationary at its place)
      if (x > currentX + 3.0) {
        canvas.drawCircle(Offset(x, centerY), dotRadius, dotPaint);
      }
    }

    // 2. Draw Filled Solid Red Line (0 -> currentX)
    if (currentX > 0) {
      final solidPaint = Paint()
        ..color = const Color(0xFFE5162A)
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      canvas.drawLine(Offset(0, centerY), Offset(currentX, centerY), solidPaint);

      // 3. Draw Active Red Thumb with inner white dot
      final thumbPaint = Paint()
        ..color = const Color(0xFFE5162A)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(currentX, centerY), 5.0, thumbPaint);

      final innerThumb = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(currentX, centerY), 2.0, innerThumb);
    }
  }

  @override
  bool shouldRepaint(covariant _NothingSeekBarPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
