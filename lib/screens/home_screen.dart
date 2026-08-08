import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:animations/animations.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wavedialer/screens/dialpad_screen.dart';
import 'package:wavedialer/screens/contacts_screen.dart';
import 'package:wavedialer/screens/recents_screen.dart';
import 'package:wavedialer/screens/startup_screen.dart';
import 'package:wavedialer/screens/recordings_screen.dart';
import 'package:wavedialer/services/telecom_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<bool> _initialized = [false, true, false]; // Default to Recents (index 1) as initialized

  Widget _getScreen(int index) {
    switch (index) {
      case 0: return const RecordingsScreen();
      case 1: return const RecentsScreen();
      case 2: return const ContactsScreen();
      default: return const RecentsScreen();
    }
  }

  late List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      _initialized[0] ? _getScreen(0) : const SizedBox.shrink(),
      _initialized[1] ? _getScreen(1) : const SizedBox.shrink(),
      _initialized[2] ? _getScreen(2) : const SizedBox.shrink(),
    ];
    
    // Move heavy work after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestPermissions();
    });
  }

  int _currentIndex = 1;

  Future<void> _requestPermissions() async {
    await [
      Permission.contacts,
      Permission.phone,
      Permission.microphone,
      Permission.audio,
    ].request();

    // MANAGE_EXTERNAL_STORAGE must redirect to Settings on Android 11+
    if (!await Permission.manageExternalStorage.isGranted) {
      final status = await Permission.manageExternalStorage.request();
      if (!status.isGranted) {
        // Fallback for older Android — try legacy storage
        await Permission.storage.request();
      }
    }

    TelecomService.requestDefaultDialer();
    _checkRootAccess();
  }

  Future<void> _checkRootAccess() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('start_mode') ?? 'none';

    if (mode == 'shizuku' || mode == 'none') {
      debugPrint('ROOT ACCESS: Skipping check for $mode mode.');
      return;
    }

    // Delay root check significantly (3s) to prioritize UI stabilization
    await Future.delayed(const Duration(seconds: 3));

    try {
      // Use compute to run root check in a separate isolate
      final granted = await compute(_runRootCheckNative, null);
      
      if (!granted) {
        debugPrint('ROOT ACCESS: Denied or not available.');
        _showNoRootDialog();
      } else {
        debugPrint('ROOT ACCESS: Granted! Magisk/KernelSU active.');
      }
    } catch (e) {
      debugPrint('ROOT ACCESS: Error executing su command: $e');
      _showNoRootDialog();
    }
  }

  void _showNoRootDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Root Access Required'),
        content: const Text('To use the native Call Recording engine, Onyx Dialer requires Root access (Magisk/KernelSU). Please grant root access or you will have to manually record calls using another app.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Understood'),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => const _SettingsDialog(),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About Onyx Dialer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(
              radius: 32,
              child: Icon(Icons.call, size: 36),
            ),
            const SizedBox(height: 16),
            const Text('Onyx Dialer', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Text('Version 1.0.0', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            const Text(
              'A premium dialer with native root-based\ntwo-sided call recording.',
            ),
            const Divider(height: 28),
            const Text('Developer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 6),
            const Text('Billu Builder', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
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
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF1C1C1E),
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: IndexedStack(
          index: _currentIndex,
          children: _screens,
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DialpadScreen()),
          ),
          backgroundColor: const Color(0xFF34C759),
          elevation: 4,
          child: const Icon(Icons.dialpad_rounded, color: Colors.white, size: 26),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        bottomNavigationBar: _IosTabBar(
          currentIndex: _currentIndex,
          onTap: (i) {
            setState(() {
              _currentIndex = i;
              if (!_initialized[i]) {
                _initialized[i] = true;
                _screens[i] = _getScreen(i);
              }
            });
          },
        ),
      ),
    );
  }
}
// Custom iOS style tab bar

class _IosTabBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _IosTabBar({required this.currentIndex, required this.onTap});

  static const _tabs = [
    (icon: Icons.mic_none_rounded,       activeIcon: Icons.mic_rounded,        label: 'Recordings'),
    (icon: Icons.access_time_rounded,    activeIcon: Icons.access_time_filled, label: 'Recents'),
    (icon: Icons.person_outline_rounded, activeIcon: Icons.person_rounded,     label: 'Contacts'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        border: Border(top: BorderSide(color: Color(0xFF38383A), width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: List.generate(_tabs.length, (i) {
              final tab = _tabs[i];
              final selected = currentIndex == i;
              const activeColor = Color(0xFF007AFF);
              const inactiveColor = Color(0xFF8E8E93);

              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onTap(i);
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 150),
                        child: Icon(
                          selected ? tab.activeIcon : tab.icon,
                          key: ValueKey(selected),
                          size: 26,
                          color: selected ? activeColor : inactiveColor,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        tab.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: selected ? activeColor : inactiveColor,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

// Settings dialog implementation

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog();

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  String _startMode = 'none';
  bool _autoRecord = false;
  bool? _isRooted;
  String? _defaultSim;
  List<Map<String, String>> _simCards = [];

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _loadSimCards();
  }

  Future<void> _loadSimCards() async {
    final sims = await TelecomService.getSimCards();
    if (mounted) {
      setState(() {
        _simCards = sims;
        // If there's only one SIM, lock the default to it
        if (_simCards.length == 1) {
          _setDefaultSim(_simCards.first['id']!);
        }
      });
    }
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _startMode = prefs.getString('start_mode') ?? 'none';
        _autoRecord = prefs.getBool('auto_record') ?? false;
        _defaultSim = prefs.getString('default_sim') ?? 'ask';
      });
    }
    if (_startMode == 'root') {
      _checkRoot();
    }
  }

  Future<void> _checkRoot() async {
    try {
      final result = await Process.run('su', ['-c', 'id']);
      if (mounted) setState(() => _isRooted = result.exitCode == 0);
    } catch (_) {
      if (mounted) setState(() => _isRooted = false);
    }
  }

  Future<void> _resetSetup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('start_mode');
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const StartupScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _toggleAutoRecord(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_record', value);
    if (mounted) setState(() => _autoRecord = value);
  }

  Future<void> _setDefaultSim(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('default_sim', value);
    if (mounted) setState(() => _defaultSim = value);
  }

  void _showSimSelectionSheet() {
    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) => CupertinoActionSheet(
        title: const Text('Default Calling SIM'),
        message: const Text('Select the SIM card to use for outgoing calls.'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              _setDefaultSim('ask');
              Navigator.pop(context);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Ask Every Time'),
                if (_defaultSim == 'ask') const Icon(CupertinoIcons.check_mark, size: 18),
              ],
            ),
          ),
          ..._simCards.map((sim) => CupertinoActionSheetAction(
                onPressed: () {
                  _setDefaultSim(sim['id']!);
                  Navigator.pop(context);
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(sim['label'] ?? 'Unknown SIM'),
                    if (_defaultSim == sim['id']) const Icon(CupertinoIcons.check_mark, size: 18),
                  ],
                ),
              )),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    String engineTitle = 'Basic Mode';
    Color engineColor = Colors.grey;
    IconData engineIcon = Icons.info_outline_rounded;

    if (_startMode == 'root') {
      engineTitle = 'Root Engine';
      engineColor = (_isRooted == true) ? Colors.green : Colors.red;
      engineIcon = Icons.bolt_rounded;
    } else if (_startMode == 'shizuku') {
      engineTitle = 'Shizuku Engine';
      engineColor = Colors.blue;
      engineIcon = Icons.layers_rounded;
    }

    return AlertDialog(
      backgroundColor: const Color(0xFF1C1C1E),
      title: const Text('Settings', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Active Engine', style: theme.textTheme.labelLarge?.copyWith(color: Colors.grey)),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(engineIcon, color: engineColor, size: 20),
              const SizedBox(width: 8),
              Text(
                engineTitle,
                style: TextStyle(color: engineColor, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              if (_startMode == 'root' && _isRooted == false)
                const Text(' (Access Denied)', style: TextStyle(color: Colors.red, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _resetSetup,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey,
              side: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            child: const Text('Change Setup Mode'),
          ),
          const Divider(height: 32, color: Colors.white10),

          Text('Recording', style: theme.textTheme.labelLarge?.copyWith(color: Colors.grey)),
          const SizedBox(height: 4),
          Text(
            'Saves to: /storage/emulated/0/Music/OnyxDialer/',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-record calls', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Starts recording on connect', style: TextStyle(color: Colors.grey, fontSize: 12)),
            value: _autoRecord,
            onChanged: _toggleAutoRecord,
            activeColor: const Color(0xFF007AFF),
          ),
          const Divider(height: 32, color: Colors.white10),

          Text('Calling Options', style: theme.textTheme.labelLarge?.copyWith(color: Colors.grey)),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Default Calling SIM', 
              style: TextStyle(color: _simCards.length <= 1 ? Colors.white38 : Colors.white)
            ),
            subtitle: Text(
              _defaultSim == 'ask'
                  ? 'Ask Every Time'
                  : (_simCards.firstWhere((sim) => sim['id'] == _defaultSim, orElse: () => {'label': 'Unknown'})['label'] ?? 'Unknown'),
              style: TextStyle(color: _simCards.length <= 1 ? Colors.white24 : Colors.grey, fontSize: 12),
            ),
            trailing: _simCards.length <= 1 
                ? null 
                : const Icon(CupertinoIcons.chevron_up_chevron_down, color: Colors.grey, size: 20),
            onTap: _simCards.length <= 1 ? null : _showSimSelectionSheet,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

// Top-level function for compute()
Future<bool> _runRootCheckNative(dynamic _) async {
  try {
    final result = await Process.run('su', ['-c', 'id']);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}
