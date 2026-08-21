import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:proximity_sensor/proximity_sensor.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavedialer/services/telecom_service.dart';

class CallController extends ChangeNotifier {
  int _callState = 0;
  String _number = '';
  String? _name;
  bool _showKeypad = false;
  bool _isSpeakerOn = false;
  bool _isMuted = false;
  bool _isHold = false;
  bool _isRecording = false;
  String _dtmfInput = '';
  int _callCount = 1;
  bool _isSpam = false;

  StreamSubscription? _subscription;
  StreamSubscription<int>? _proximitySub;
  Timer? _timer;
  int _seconds = 0;
  bool _isNear = false;
  bool _blockProximity = false;

  int get callState => _callState;
  String get number => _number;
  String? get name => _name;
  bool get showKeypad => _showKeypad;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get isMuted => _isMuted;
  bool get isHold => _isHold;
  bool get isRecording => _isRecording;
  String get dtmfInput => _dtmfInput;
  int get callCount => _callCount;
  bool get isSpam => _isSpam;
  int get seconds => _seconds;
  bool get isNear => _isNear;

  void init({
    required String initialNumber,
    required int initialState,
    String? initialName,
    int initialSeconds = 0,
  }) {
    _number = initialNumber;
    _callState = initialState;
    _name = initialName;
    _seconds = initialSeconds;

    if (_name == null || _name!.isEmpty) {
      resolveContactName();
    }

    checkSpam();
    initProximity();

    // If already in active call (e.g. answered from notification), start timer right away
    if (_callState == 4 && _timer == null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _seconds++;
        notifyListeners();
      });
      maybeAutoRecord();
    }

    _subscription = TelecomService.callStateStream.listen((data) {
      updateCallCount();

      final incomingNumber = (data['number'] as String?) ?? 'Unknown';
      final newState = data['state'] as int;

      if (data['elapsedSeconds'] != null) {
        final syncedSec = data['elapsedSeconds'] as int;
        if (syncedSec > _seconds) {
          _seconds = syncedSec;
        }
      }

      if (newState == 7 && incomingNumber != _number) {
        debugPrint('CallController: Other call disconnected, auto-unholding...');
        Future.delayed(const Duration(milliseconds: 500), () {
          if (_isHold) {
            TelecomService.setHold(false);
            _isHold = false;
            notifyListeners();
          }
        });
        return;
      }

      if (_callState == 7 && newState != 7) {
        _timer?.cancel();
      }

      _callState = newState;

      if (data['name'] != null && (data['name'] as String).isNotEmpty) {
        _name = data['name'] as String;
      }

      if (incomingNumber != 'Unknown' && incomingNumber != _number) {
        _number = incomingNumber;
        checkSpam();
        if (_name == null) {
          resolveContactName();
        }
      }

      if (_callState == 4 && _timer == null) {
        _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
          _seconds++;
          notifyListeners();
        });
        maybeAutoRecord();
      }

      if (_callState == 7) {
        _proximitySub?.cancel();
        _proximitySub = null;
        _isNear = false;
        ProximitySensor.setProximityScreenOff(false);
        if (_isRecording) {
          TelecomService.stopRecording();
          _isRecording = false;
        }
        _timer?.cancel();
      }

      notifyListeners();
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _proximitySub?.cancel();
    _proximitySub = null;
    _timer?.cancel();
    _timer = null;
    _isNear = false;
    ProximitySensor.setProximityScreenOff(false);
    super.dispose();
  }

  Future<void> resolveContactName() async {
    if (await Permission.contacts.isGranted) {
      final contacts = await FlutterContacts.getAll(properties: {ContactProperty.phone});
      final cleanQuery = _number.replaceAll(RegExp(r'\D'), '');

      if (cleanQuery.length < 5) return;

      for (var contact in contacts) {
        for (var phone in contact.phones) {
          final cleanPhone = phone.number.replaceAll(RegExp(r'\D'), '');

          if (cleanPhone.isNotEmpty &&
              (cleanPhone.endsWith(cleanQuery) || cleanQuery.endsWith(cleanPhone))) {
            _name = contact.displayName;
            notifyListeners();
            return;
          }
        }
      }
    }
  }

  Future<void> checkSpam() async {
    final prefs = await SharedPreferences.getInstance();
    final spamProtection = prefs.getBool('spam_protection') ?? false;
    if (spamProtection) {
      final cleanNum = _number.replaceAll(RegExp(r'\D'), '');

      if (cleanNum == '9999999999') {
        _isSpam = true;
        notifyListeners();
        return;
      }

      if (cleanNum.startsWith('140') || cleanNum.startsWith('91140')) {
        _isSpam = true;
        notifyListeners();
        return;
      }

      if (cleanNum.startsWith('800') || cleanNum.startsWith('888') || cleanNum.startsWith('877') ||
          cleanNum.startsWith('866') || cleanNum.startsWith('855') || cleanNum.startsWith('844') ||
          cleanNum.startsWith('833') || cleanNum.startsWith('900')) {
        _isSpam = true;
        notifyListeners();
        return;
      }

      final ukNumber = cleanNum.startsWith('44') ? '0${cleanNum.substring(2)}' : cleanNum;
      if (ukNumber.startsWith('070') || ukNumber.startsWith('090') || ukNumber.startsWith('091') || ukNumber.startsWith('098')) {
        _isSpam = true;
        notifyListeners();
        return;
      }

      final auNumber = cleanNum.startsWith('61') ? '0${cleanNum.substring(2)}' : cleanNum;
      if (auNumber.startsWith('0190') || auNumber.startsWith('190')) {
        _isSpam = true;
        notifyListeners();
        return;
      }

      final deNumber = cleanNum.startsWith('49') ? '0${cleanNum.substring(2)}' : cleanNum;
      if (deNumber.startsWith('0900')) {
        _isSpam = true;
        notifyListeners();
        return;
      }

      final frNumber = cleanNum.startsWith('33') ? '0${cleanNum.substring(2)}' : cleanNum;
      if (frNumber.startsWith('089')) {
        _isSpam = true;
        notifyListeners();
        return;
      }

      final egNumber = cleanNum.startsWith('20') ? '0${cleanNum.substring(2)}' : cleanNum;
      if (egNumber.startsWith('0900') || RegExp(r'^9\d{3,4}$').hasMatch(cleanNum)) {
        _isSpam = true;
        notifyListeners();
        return;
      }

      final saNumber = cleanNum.startsWith('966') ? '0${cleanNum.substring(3)}' : cleanNum;
      if (saNumber.startsWith('0700') || saNumber.startsWith('700')) {
        _isSpam = true;
        notifyListeners();
        return;
      }

      final aeNumber = cleanNum.startsWith('971') ? '0${cleanNum.substring(3)}' : cleanNum;
      if (aeNumber.startsWith('0600') || aeNumber.startsWith('600')) {
        _isSpam = true;
        notifyListeners();
        return;
      }

      final ruNumber = cleanNum.startsWith('7') ? cleanNum.substring(1) : cleanNum;
      if (ruNumber.startsWith('800') || ruNumber.startsWith('803') || ruNumber.startsWith('809')) {
        _isSpam = true;
        notifyListeners();
        return;
      }

      final bdNumber = cleanNum.startsWith('880') ? '0${cleanNum.substring(3)}' : cleanNum;
      if (bdNumber.startsWith('096')) {
        _isSpam = true;
        notifyListeners();
        return;
      }

      final pkNumber = cleanNum.startsWith('92') ? '0${cleanNum.substring(2)}' : cleanNum;
      if (pkNumber.startsWith('0900')) {
        _isSpam = true;
        notifyListeners();
        return;
      }

      final cnNumber = cleanNum.startsWith('86') ? cleanNum.substring(2) : cleanNum;
      if (cnNumber.startsWith('95') || cnNumber.startsWith('400')) {
        _isSpam = true;
        notifyListeners();
        return;
      }

      if (cleanNum.startsWith('800') || cleanNum.startsWith('0800') || cleanNum.startsWith('1800') ||
          cleanNum.startsWith('91800') || cleanNum.startsWith('910800')) {
        _isSpam = true;
        notifyListeners();
        return;
      }
    }
    _isSpam = false;
    notifyListeners();
  }

  Future<void> initProximity() async {
    final prefs = await SharedPreferences.getInstance();
    _blockProximity = prefs.getBool('block_proximity') ?? false;

    if (!_blockProximity && _callState != 7 && !_isSpeakerOn) {
      ProximitySensor.setProximityScreenOff(true);
      _proximitySub?.cancel();
      _proximitySub = ProximitySensor.events.listen((event) {
        if (_callState != 7 && !_isSpeakerOn) {
          _isNear = (event > 0);
          notifyListeners();
        }
      });
    }
  }

  Future<void> updateCallCount() async {
    final info = await TelecomService.getCallInfo();
    final count = (info['count'] as int?) ?? 1;
    final isConf = (info['isConference'] as bool?) ?? false;
    final isHolding = (info['isHolding'] as bool?) ?? false;

    _callCount = count;
    if (isConf) {
      _name = 'Conference Call';
      _isHold = false;
    } else if (!isHolding && _isHold) {
      _isHold = false;
    }
    notifyListeners();
  }

  void onDigitPressed(String digit) {
    _dtmfInput += digit;
    TelecomService.playLocalDtmf(digit);
    notifyListeners();
  }

  String formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> maybeAutoRecord() async {
    final prefs = await SharedPreferences.getInstance();
    final autoRecord = prefs.getBool('auto_record') ?? false;
    if (autoRecord && !_isRecording) {
      toggleRecording();
    }
  }

  Future<void> toggleRecording() async {
    _isRecording = !_isRecording;
    notifyListeners();
    if (_isRecording) {
      final safeNumber = _number.replaceAll(RegExp(r'[^0-9+]'), '');
      final fileName = 'Call_${safeNumber}_${DateTime.now().millisecondsSinceEpoch}.wav';
      final dir = Directory('/storage/emulated/0/Recordings/OnyxDialer');
      if (!(await dir.exists())) await dir.create(recursive: true);
      TelecomService.startRecording('${dir.path}/$fileName');
    } else {
      TelecomService.stopRecording();
    }
  }

  void toggleKeypad() {
    _showKeypad = !_showKeypad;
    notifyListeners();
  }

  void toggleSpeaker() {
    _isSpeakerOn = !_isSpeakerOn;
    TelecomService.setSpeaker(_isSpeakerOn);
    if (_isSpeakerOn) {
      _isNear = false;
      ProximitySensor.setProximityScreenOff(false);
    } else if (!_blockProximity && _callState != 7) {
      ProximitySensor.setProximityScreenOff(true);
    }
    notifyListeners();
  }

  void toggleMute() {
    _isMuted = !_isMuted;
    TelecomService.setMuted(_isMuted);
    notifyListeners();
  }

  void toggleHold() {
    _isHold = !_isHold;
    TelecomService.setHold(_isHold);
    notifyListeners();
  }

  void addCall() {
    notifyListeners();
  }

  void mergeCall() {
    TelecomService.mergeCall();
    notifyListeners();
  }

  void swapCall() {
    TelecomService.swapCall();
    notifyListeners();
  }

  String getMetadataString() {
    switch (_callState) {
      case 2:
        return 'I N C O M I N G  C A L L';
      case 1:
      case 9:
        return 'O U T G O I N G  C A L L';
      case 4:
        return 'A C T I V E  C A L L';
      default:
        return 'O N Y X  D I A L E R';
    }
  }

  String getStateString() {
    if (_isHold || _callState == 3) return 'On Hold';
    switch (_callState) {
      case 1:
      case 9:
        return 'calling...';
      case 2:
        return 'Incoming Call';
      case 4:
        return formatDuration(_seconds);
      case 7:
        return 'Call Ended';
      case 10:
        return 'Disconnecting...';
      default:
        return 'connecting...';
    }
  }
}
