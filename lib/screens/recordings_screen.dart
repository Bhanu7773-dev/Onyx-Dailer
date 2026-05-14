import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:intl/intl.dart';

class RecordingItem {
  final File file;
  final String number;
  final DateTime timestamp;
  Contact? contact;

  RecordingItem({
    required this.file,
    required this.number,
    required this.timestamp,
    this.contact,
  });
}

class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> with WidgetsBindingObserver {
  String _searchQuery = '';
  List<RecordingItem> _allRecordings = [];
  List<RecordingItem> _filteredRecordings = [];
  bool _isLoading = true;

  // Audio Player State
  final AudioPlayer _audioPlayer = AudioPlayer();
  RecordingItem? _currentlyPlaying;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

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
        _currentlyPlaying = null; // Reset so next tap does a fresh play
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _audioPlayer.dispose();
    super.dispose();
  }

  // Auto-reload when returning from a call (app resumes)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadRecordings();
    }
  }

  Future<void> _loadRecordings() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      final dir = Directory('/sdcard/Music/OnyxDialer');
      if (!await dir.exists()) {
        if (mounted) setState(() {
          _allRecordings = [];
          _filteredRecordings = [];
          _isLoading = false;
        });
        return;
      }

      final files = dir.listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.wav') || f.path.endsWith('.m4a'))
          .toList();
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

  Future<void> _playRecording(RecordingItem item) async {
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

  Future<void> _deleteRecording(RecordingItem item) async {
    // Stop playback if this file is playing
    if (_currentlyPlaying?.file.path == item.file.path) {
      await _audioPlayer.stop();
      setState(() {
        _currentlyPlaying = null;
        _isPlaying = false;
      });
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Recording'),
        content: Text(
          'Delete the recording for ${item.contact?.displayName ?? item.number}?\nThis cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await item.file.delete();
        setState(() {
          _allRecordings.remove(item);
          _filterRecordings();
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Recording deleted'), duration: Duration(seconds: 2)),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: $e')),
          );
        }
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
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: SearchBar(
                hintText: 'Search recordings',
                elevation: const WidgetStatePropertyAll(0),
                backgroundColor: WidgetStatePropertyAll(
                    theme.colorScheme.secondaryContainer.withValues(alpha: 0.5)),
                leading: const Padding(
                  padding: EdgeInsets.only(left: 8.0),
                  child: Icon(Icons.search),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                    _filterRecordings();
                  });
                },
              ),
            ),
            if (_isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_allRecordings.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.mic_none, size: 64, color: theme.colorScheme.outline),
                      const SizedBox(height: 12),
                      Text('No recordings yet', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text('Tap Record during a call to save audio',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline)),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _loadRecordings,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _filteredRecordings.length,
                    itemBuilder: (context, index) {
                      final item = _filteredRecordings[index];
                      final isPlayingThis =
                          _currentlyPlaying?.file.path == item.file.path;
                      final displayName =
                          item.contact?.displayName ?? item.number;
                      final dateStr =
                          DateFormat('MMM d, yyyy • h:mm a').format(item.timestamp);
                      final fileSizeMb =
                          (item.file.lengthSync() / 1024 / 1024).toStringAsFixed(2);

                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        elevation: 0,
                        color: isPlayingThis
                            ? theme.colorScheme.primaryContainer
                                .withValues(alpha: 0.4)
                            : theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.3),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        child: Column(
                          children: [
                            ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    theme.colorScheme.primaryContainer,
                                child: Icon(Icons.mic,
                                    color: theme.colorScheme.onPrimaryContainer),
                              ),
                              title: Text(displayName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              subtitle: Text('$dateStr • ${fileSizeMb}MB'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      isPlayingThis && _isPlaying
                                          ? Icons.pause_circle_filled
                                          : Icons.play_circle_fill,
                                      size: 34,
                                      color: theme.colorScheme.primary,
                                    ),
                                    onPressed: () => _playRecording(item),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: Colors.red),
                                    onPressed: () => _deleteRecording(item),
                                  ),
                                ],
                              ),
                              onTap: () => _playRecording(item),
                            ),
                            if (isPlayingThis)
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                child: Column(
                                  children: [
                                    Slider(
                                      value: _position.inMilliseconds.toDouble(),
                                      min: 0.0,
                                      max: _duration.inMilliseconds.toDouble() > 0
                                          ? _duration.inMilliseconds.toDouble()
                                          : 1.0,
                                      onChanged: (value) {
                                        _audioPlayer.seek(Duration(
                                            milliseconds: value.toInt()));
                                      },
                                    ),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(_formatDuration(_position),
                                            style: theme.textTheme.bodySmall),
                                        Text(_formatDuration(_duration),
                                            style: theme.textTheme.bodySmall),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
