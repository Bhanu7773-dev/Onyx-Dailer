import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:audioplayers/audioplayers.dart';

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

class RecordingsController extends ChangeNotifier {
  String _searchQuery = '';
  List<RecordingItem> _allRecordings = [];
  List<RecordingItem> _filteredRecordings = [];
  bool _isLoading = true;

  final AudioPlayer _audioPlayer = AudioPlayer();
  RecordingItem? _currentlyPlaying;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  RecordingItem? _expandedItem;

  StreamSubscription<FileSystemEvent>? _dirWatcher;

  String get searchQuery => _searchQuery;
  List<RecordingItem> get allRecordings => _allRecordings;
  List<RecordingItem> get filteredRecordings => _filteredRecordings;
  bool get isLoading => _isLoading;
  AudioPlayer get audioPlayer => _audioPlayer;
  RecordingItem? get currentlyPlaying => _currentlyPlaying;
  bool get isPlaying => _isPlaying;
  Duration get duration => _duration;
  Duration get position => _position;
  RecordingItem? get expandedItem => _expandedItem;

  void init() {
    loadRecordings();
    _startDirectoryWatch();

    _audioPlayer.onPlayerStateChanged.listen((state) {
      _isPlaying = state == PlayerState.playing;
      notifyListeners();
    });
    _audioPlayer.onDurationChanged.listen((d) {
      _duration = d;
      notifyListeners();
    });
    _audioPlayer.onPositionChanged.listen((p) {
      _position = p;
      notifyListeners();
    });
    _audioPlayer.onPlayerComplete.listen((_) {
      _isPlaying = false;
      _position = Duration.zero;
      _currentlyPlaying = null;
      notifyListeners();
    });
  }

  void _startDirectoryWatch() {
    try {
      final dir = Directory('/storage/emulated/0/Recordings/OnyxDialer');
      if (dir.existsSync()) {
        _dirWatcher = dir.watch().listen((_) {
          loadRecordings();
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _dirWatcher?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  String _normalizeDigits(String value) => value.replaceAll(RegExp(r'\D'), '');

  Contact? _matchBestContact(List<Contact> contacts, String number) {
    final cleanNum = _normalizeDigits(number);
    if (cleanNum.length < 7) return null;

    Contact? bestContact;
    var bestScore = -1;

    for (final contact in contacts) {
      for (final phone in contact.phones) {
        final cleanPhone = _normalizeDigits(phone.number);
        if (cleanPhone.length < 7) continue;

        final minLen = cleanPhone.length < cleanNum.length ? cleanPhone.length : cleanNum.length;
        var suffixMatch = 0;
        for (var i = 1; i <= minLen; i++) {
          if (cleanPhone[cleanPhone.length - i] == cleanNum[cleanNum.length - i]) {
            suffixMatch++;
          } else {
            break;
          }
        }

        if (suffixMatch > bestScore) {
          bestScore = suffixMatch;
          bestContact = contact;
        }
      }
    }

    return bestScore >= 7 ? bestContact : null;
  }

  Future<void> loadRecordings() async {
    _isLoading = true;
    notifyListeners();

    try {
      final possiblePaths = [
        '/storage/emulated/0/Recordings/OnyxDialer',
        '/sdcard/Recordings/OnyxDialer',
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
        _allRecordings = [];
        _filteredRecordings = [];
        _isLoading = false;
        notifyListeners();
        return;
      }

      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

      final contacts = await FlutterContacts.getAll(properties: {ContactProperty.phone});

      final List<RecordingItem> items = [];
      for (final file in files) {
        final filename = file.path.split('/').last;
        final ext = filename.endsWith('.wav') ? '.wav' : '.m4a';
        final stem = filename.substring(0, filename.length - ext.length);
        final separatorIndex = stem.lastIndexOf('_');

        String number = 'Unknown';
        DateTime timestamp = file.lastModifiedSync();

        if (separatorIndex > 0) {
          final rawNumber = stem.substring(0, separatorIndex);
          final rawTimestamp = stem.substring(separatorIndex + 1);

          number = rawNumber.startsWith('Call_') ? rawNumber.substring(5) : rawNumber;
          final timeMillis = int.tryParse(rawTimestamp);
          if (timeMillis != null) {
            timestamp = DateTime.fromMillisecondsSinceEpoch(timeMillis);
          }
        }

        final matchedContact = _matchBestContact(contacts, number);

        items.add(RecordingItem(
          file: file,
          number: number,
          timestamp: timestamp,
          contact: matchedContact,
        ));
      }

      _allRecordings = items;
      _filterRecordings();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading recordings: $e');
      _isLoading = false;
      notifyListeners();
    }
  }

  void rebuild(String query) {
    _searchQuery = query;
    _filterRecordings();
    notifyListeners();
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

  Future<void> playOrPause(RecordingItem item) async {
    HapticFeedback.lightImpact();
    if (_currentlyPlaying?.file.path == item.file.path) {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.resume();
      }
    } else {
      await _audioPlayer.stop();
      _currentlyPlaying = item;
      _position = Duration.zero;
      _duration = Duration.zero;
      notifyListeners();
      await _audioPlayer.play(DeviceFileSource(item.file.path));
    }
    notifyListeners();
  }

  Future<void> toggleExpand(RecordingItem item) async {
    HapticFeedback.selectionClick();

    if (_expandedItem?.file.path != item.file.path) {
      if (item.duration == null) {
        try {
          final tempPlayer = AudioPlayer();
          await tempPlayer.setSourceDeviceFile(item.file.path);
          final d = await tempPlayer.getDuration();
          if (d != null) {
            item.duration = d;
          }
          await tempPlayer.dispose();
        } catch (_) {}
      }
    }

    if (_expandedItem?.file.path == item.file.path) {
      if (_currentlyPlaying?.file.path == item.file.path) {
        await _audioPlayer.stop();
        _currentlyPlaying = null;
        _isPlaying = false;
      }
      _expandedItem = null;
    } else {
      _expandedItem = item;
    }
    notifyListeners();
  }

  Future<void> deleteRecording(RecordingItem item) async {
    if (_currentlyPlaying?.file.path == item.file.path) {
      await _audioPlayer.stop();
      _currentlyPlaying = null;
      _isPlaying = false;
    }

    try {
      await item.file.delete();
      _allRecordings.remove(item);
      _filterRecordings();
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to delete: $e');
    }
  }

  String formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
