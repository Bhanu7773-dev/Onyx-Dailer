import 'dart:io';
import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:intl/intl.dart';
import 'dart:ui';
import 'package:wavedialer/logic/recordings_controller.dart';

const _bg           = Color(0xFF000000);
const _card         = Color(0xFF1C1C1E);
const _iosBlue      = Color(0xFF007AFF);
const _iosLabel     = Color(0xFFFFFFFF);
const _iosSecondary = Color(0xFF8E8E93);
const _iosTertiary  = Color(0xFF48484A);
const _iosSeparator    = Color(0xFF38383A);
const _iosRed       = Color(0xFFFF3B30);



class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> with WidgetsBindingObserver {
  final RecordingsController _controller = RecordingsController();
  final TextEditingController _searchCtrl = TextEditingController();

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
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: CupertinoAlertDialog(
          title: const Text('Delete Recording'),
          content: Text('Delete the recording for ${item.contact?.displayName ?? item.number}?\nThis cannot be undone.'),
          actions: [
            CupertinoDialogAction(
              child: const Text('Cancel', style: TextStyle(color: _iosBlue)),
              onPressed: () => Navigator.pop(ctx, false),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      await _controller.deleteRecording(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: _bg,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 10),
                child: Text('Recordings',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      color: _iosLabel,
                      letterSpacing: -0.5,
                    )),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.search_rounded,
                            color: _iosSecondary, size: 18),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (v) {
                            _controller.rebuild(v);
                          },
                          style: const TextStyle(color: _iosLabel, fontSize: 15),
                          decoration: const InputDecoration(
                            hintText: 'Search recordings',
                            hintStyle: TextStyle(color: _iosSecondary, fontSize: 15),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 8),
                          ),
                          cursorColor: _iosBlue,
                        ),
                      ),
                      if (_controller.searchQuery.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _searchCtrl.clear();
                            _controller.rebuild('');
                            FocusScope.of(context).unfocus();
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Icon(Icons.cancel, color: _iosSecondary, size: 18),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              Expanded(
                child: _controller.isLoading
                    ? const Center(child: CircularProgressIndicator(color: _iosBlue))
                    : _controller.allRecordings.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(CupertinoIcons.mic_slash, size: 60, color: _iosTertiary),
                                SizedBox(height: 12),
                                Text(
                                  'No recordings yet',
                                  style: TextStyle(color: _iosSecondary, fontSize: 16),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _controller.loadRecordings,
                            color: _iosBlue,
                            backgroundColor: _card,
                            child: ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 100),
                              itemCount: _controller.filteredRecordings.length,
                              itemBuilder: (context, index) {
                                final item = _controller.filteredRecordings[index];
                                final isExpanded = _controller.expandedItem?.file.path == item.file.path;
                                final isPlayingThis = _controller.currentlyPlaying?.file.path == item.file.path;
                                final isLast = index == _controller.filteredRecordings.length - 1;
                                final isFirst = index == 0;
                                
                                return _buildRecordingItem(item, isExpanded, isPlayingThis, isFirst, isLast);
                              },
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecordingItem(RecordingItem item, bool isExpanded, bool isPlayingThis, bool isFirst, bool isLast) {
    final displayName = item.contact?.displayName ?? item.number;
    final dateStr = DateFormat('MMM d, yyyy • h:mm a').format(item.timestamp);
    final fileSizeMb = (item.file.lengthSync() / 1024 / 1024).toStringAsFixed(2);
    final initial = displayName.trim().isEmpty ? '#' : displayName.trim()[0].toUpperCase();

    final content = Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.vertical(
            top: isFirst ? const Radius.circular(13) : Radius.zero,
            bottom: isLast ? const Radius.circular(13) : Radius.zero,
          ),
        ),
        child: Column(
          children: [
            GestureDetector(
              onTap: () => _controller.toggleExpand(item),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: _iosTertiary,
                      child: Text(
                        initial,
                        style: const TextStyle(fontSize: 16, color: _iosLabel, fontWeight: FontWeight.w500),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(displayName,
                              style: const TextStyle(color: _iosLabel, fontSize: 17, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 2),
                          Text('$dateStr • ${fileSizeMb}MB',
                              style: const TextStyle(color: _iosSecondary, fontSize: 13)),
                        ],
                      ),
                    ),
                    Icon(
                      isExpanded ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down,
                      color: _iosSecondary,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),

            if (isExpanded)
              GestureDetector(
                onTap: () {}, 
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Column(
                    children: [
                      SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                          activeTrackColor: _iosBlue,
                          inactiveTrackColor: _iosTertiary,
                          thumbColor: _iosLabel,
                        ),
                        child: Slider(
                          value: isPlayingThis ? _controller.position.inMilliseconds.toDouble() : 0,
                          min: 0.0,
                          max: isPlayingThis && _controller.duration.inMilliseconds > 0
                              ? _controller.duration.inMilliseconds.toDouble()
                              : 1.0,
                          onChanged: isPlayingThis
                              ? (value) => _controller.audioPlayer.seek(Duration(milliseconds: value.toInt()))
                              : null,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(isPlayingThis ? _controller.formatDuration(_controller.position) : '00:00',
                                style: const TextStyle(color: _iosSecondary, fontSize: 12)),
                            Text(
                                isPlayingThis
                                    ? '-${_controller.formatDuration(_controller.duration - _controller.position)}'
                                    : (item.duration != null ? _controller.formatDuration(item.duration!) : '--:--'),
                                style: const TextStyle(color: _iosSecondary, fontSize: 12)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: () => _deleteRecording(item),
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              child: const Icon(CupertinoIcons.trash, color: _iosRed, size: 24),
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () {
                              if (isPlayingThis) {
                                final newPos = _controller.position - const Duration(seconds: 15);
                                _controller.audioPlayer.seek(newPos < Duration.zero ? Duration.zero : newPos);
                              }
                            },
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              child: Icon(CupertinoIcons.gobackward_15,
                                  color: isPlayingThis ? _iosLabel : _iosTertiary, size: 28),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => _controller.playOrPause(item),
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              child: Icon(
                                isPlayingThis && _controller.isPlaying
                                    ? CupertinoIcons.pause_circle_fill
                                    : CupertinoIcons.play_circle_fill,
                                color: _iosLabel,
                                size: 56,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              if (isPlayingThis) {
                                final newPos = _controller.position + const Duration(seconds: 15);
                                _controller.audioPlayer.seek(newPos > _controller.duration ? _controller.duration : newPos);
                              }
                            },
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              child: Icon(CupertinoIcons.goforward_15,
                                  color: isPlayingThis ? _iosLabel : _iosTertiary, size: 28),
                            ),
                          ),
                          const Spacer(),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

            if (!isLast)
              Container(
                margin: const EdgeInsets.only(left: 68),
                height: 0.5,
                color: _iosSeparator,
              ),
          ],
        ),
      ),
    );

    if (isExpanded) {
      return SizedBox(
        width: MediaQuery.of(context).size.width - 32,
        child: content,
      );
    }

    return CupertinoContextMenu(
      enableHapticFeedback: true,
      actions: <Widget>[
        CupertinoContextMenuAction(
          onPressed: () {
            Navigator.pop(context);
            _controller.playOrPause(item);
          },
          isDefaultAction: true,
          trailingIcon: isPlayingThis && _controller.isPlaying ? CupertinoIcons.pause : CupertinoIcons.play,
          child: Text(isPlayingThis && _controller.isPlaying ? 'Pause' : 'Play'),
        ),
        CupertinoContextMenuAction(
          onPressed: () {
            Navigator.pop(context);
            _deleteRecording(item);
          },
          isDestructiveAction: true,
          trailingIcon: CupertinoIcons.trash,
          child: const Text('Delete'),
        ),
      ],
      child: SizedBox(
        width: MediaQuery.of(context).size.width - 32,
        child: content,
      ),
    );
  }
}
