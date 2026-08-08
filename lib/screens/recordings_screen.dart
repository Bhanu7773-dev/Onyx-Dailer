import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:intl/intl.dart';
import 'dart:ui';

const _bg           = Color(0xFF000000);
const _card         = Color(0xFF1C1C1E);
const _iosBlue      = Color(0xFF007AFF);
const _iosLabel     = Color(0xFFFFFFFF);
const _iosSecondary = Color(0xFF8E8E93);
const _iosTertiary  = Color(0xFF48484A);
const _iosSeparator    = Color(0xFF38383A);
const _iosRed       = Color(0xFFFF3B30);

class RecordingItem {
  final File file;
  final String number;
  final DateTime timestamp;
  Contact? contact;
  Duration? duration;

  RecordingItem({
    required this.file,
    required this.number,
    required this.timestamp,
    this.contact,
    this.duration,
  });
}

class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> with WidgetsBindingObserver {
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();
  List<RecordingItem> _allRecordings = [];
  List<RecordingItem> _filteredRecordings = [];
  bool _isLoading = true;

  // Audio Player State
  final AudioPlayer _audioPlayer = AudioPlayer();
  RecordingItem? _currentlyPlaying;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  RecordingItem? _expandedItem; // tracks which card is expanded

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadRecordings();

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
    });
    _audioPlayer.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _audioPlayer.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() {
        _isPlaying = false;
        _position = Duration.zero;
        _currentlyPlaying = null;
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchCtrl.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadRecordings();
    }
  }

  Future<void> _loadRecordings() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      final possiblePaths = [
        '/storage/emulated/0/Music/OnyxDialer',
        '/sdcard/Music/OnyxDialer',
      ];

      final List<File> files = [];
      for (final p in possiblePaths) {
        final dir = Directory(p);
        if (await dir.exists()) {
          final found = dir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.wav') || f.path.endsWith('.m4a'));
          for (final f in found) {
            final filename = f.path.split('/').last;
            if (!files.any((existing) => existing.path.split('/').last == filename)) {
              files.add(f);
            }
          }
        }
      }

      if (files.isEmpty) {
        if (mounted) setState(() {
          _allRecordings = [];
          _filteredRecordings = [];
          _isLoading = false;
        });
        return;
      }

      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

      final contacts = await FlutterContacts.getAll(properties: {ContactProperty.phone});

      final List<RecordingItem> items = [];
      for (final file in files) {
        final filename = file.path.split('/').last;
        final ext = filename.endsWith('.wav') ? '.wav' : '.m4a';
        final parts = filename.replaceAll(ext, '').split('_');

        String number = 'Unknown';
        DateTime timestamp = file.lastModifiedSync();

        if (parts.length >= 3) {
          number = parts[1];
          final timeMillis = int.tryParse(parts[2]);
          if (timeMillis != null) {
            timestamp = DateTime.fromMillisecondsSinceEpoch(timeMillis);
          }
        } else if (parts.length == 2) {
          number = parts[1];
        }

        Contact? matchedContact;
        for (final contact in contacts) {
          final hasMatch = contact.phones.any((p) {
            final cleanPhone = p.number.replaceAll(RegExp(r'\D'), '');
            final cleanNum = number.replaceAll(RegExp(r'\D'), '');
            return cleanPhone.isNotEmpty && cleanNum.isNotEmpty &&
                (cleanPhone.contains(cleanNum) || cleanNum.contains(cleanPhone));
          });
          if (hasMatch) { matchedContact = contact; break; }
        }

        items.add(RecordingItem(
          file: file,
          number: number,
          timestamp: timestamp,
          contact: matchedContact,
        ));
      }

      if (mounted) setState(() {
        _allRecordings = items;
        _filterRecordings();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading recordings: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filterRecordings() {
    if (_searchQuery.isEmpty) {
      _filteredRecordings = List.from(_allRecordings);
    } else {
      final query = _searchQuery.toLowerCase();
      _filteredRecordings = _allRecordings.where((item) {
        final nameMatch = item.contact?.displayName?.toLowerCase().contains(query) ?? false;
        final numMatch = item.number.contains(query);
        return nameMatch || numMatch;
      }).toList();
    }
  }

  Future<void> _playOrPause(RecordingItem item) async {
    HapticFeedback.lightImpact();
    if (_currentlyPlaying?.file.path == item.file.path) {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.resume();
      }
    } else {
      await _audioPlayer.stop();
      setState(() {
        _currentlyPlaying = item;
        _position = Duration.zero;
        _duration = Duration.zero;
      });
      await _audioPlayer.play(DeviceFileSource(item.file.path));
    }
  }

  Future<void> _toggleExpand(RecordingItem item) async {
    HapticFeedback.selectionClick();

    if (_expandedItem?.file.path != item.file.path) {
      if (item.duration == null) {
        try {
          final tempPlayer = AudioPlayer();
          await tempPlayer.setSourceDeviceFile(item.file.path);
          final d = await tempPlayer.getDuration();
          if (mounted && d != null) {
            setState(() {
              item.duration = d;
            });
          }
          await tempPlayer.dispose();
        } catch (_) {}
      }
    }

    if (mounted) {
      setState(() {
        if (_expandedItem?.file.path == item.file.path) {
          if (_currentlyPlaying?.file.path == item.file.path) {
            _audioPlayer.stop();
            _currentlyPlaying = null;
            _isPlaying = false;
          }
          _expandedItem = null;
        } else {
          _expandedItem = item;
        }
      });
    }
  }

  Future<void> _deleteRecording(RecordingItem item) async {
    HapticFeedback.mediumImpact();
    if (_currentlyPlaying?.file.path == item.file.path) {
      await _audioPlayer.stop();
      setState(() {
        _currentlyPlaying = null;
        _isPlaying = false;
      });
    }

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
      try {
        await item.file.delete();
        setState(() {
          _allRecordings.remove(item);
          _filterRecordings();
        });
      } catch (e) {
        debugPrint('Failed to delete: $e');
      }
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
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
                            setState(() {
                              _searchQuery = v;
                              _filterRecordings();
                            });
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
                      if (_searchQuery.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _searchCtrl.clear();
                            setState(() {
                              _searchQuery = '';
                              _filterRecordings();
                            });
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
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: _iosBlue))
                    : _allRecordings.isEmpty
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
                            onRefresh: _loadRecordings,
                            color: _iosBlue,
                            backgroundColor: _card,
                            child: ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 100),
                              itemCount: _filteredRecordings.length,
                              itemBuilder: (context, index) {
                                final item = _filteredRecordings[index];
                                final isExpanded = _expandedItem?.file.path == item.file.path;
                                final isPlayingThis = _currentlyPlaying?.file.path == item.file.path;
                                final isLast = index == _filteredRecordings.length - 1;
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
              onTap: () => _toggleExpand(item),
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
                          value: isPlayingThis ? _position.inMilliseconds.toDouble() : 0,
                          min: 0.0,
                          max: isPlayingThis && _duration.inMilliseconds > 0
                              ? _duration.inMilliseconds.toDouble()
                              : 1.0,
                          onChanged: isPlayingThis
                              ? (value) => _audioPlayer.seek(Duration(milliseconds: value.toInt()))
                              : null,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(isPlayingThis ? _formatDuration(_position) : '00:00',
                                style: const TextStyle(color: _iosSecondary, fontSize: 12)),
                            Text(
                                isPlayingThis
                                    ? '-${_formatDuration(_duration - _position)}'
                                    : (item.duration != null ? _formatDuration(item.duration!) : '--:--'),
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
                                final newPos = _position - const Duration(seconds: 15);
                                _audioPlayer.seek(newPos < Duration.zero ? Duration.zero : newPos);
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
                            onTap: () => _playOrPause(item),
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              child: Icon(
                                isPlayingThis && _isPlaying
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
                                final newPos = _position + const Duration(seconds: 15);
                                _audioPlayer.seek(newPos > _duration ? _duration : newPos);
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
                          const SizedBox(width: 48),
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
            _playOrPause(item);
          },
          isDefaultAction: true,
          trailingIcon: isPlayingThis && _isPlaying ? CupertinoIcons.pause : CupertinoIcons.play,
          child: Text(isPlayingThis && _isPlaying ? 'Pause' : 'Play'),
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
