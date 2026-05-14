import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:animations/animations.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wavedialer/screens/dialpad_screen.dart';
import 'package:wavedialer/screens/contacts_screen.dart';
import 'package:wavedialer/screens/recents_screen.dart';
import 'package:wavedialer/screens/recordings_screen.dart';
import 'package:wavedialer/services/telecom_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 1; // Default to Recents

  final List<Widget> _screens = [
    const RecordingsScreen(),
    const RecentsScreen(),
    const ContactsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

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
    try {
      final result = await Process.run('su', ['-c', 'id']);
      if (result.exitCode != 0) {
        debugPrint('ROOT ACCESS: Denied or not available (Exit code: ${result.exitCode}).');
        _showNoRootDialog();
      } else {
        debugPrint('ROOT ACCESS: Granted! Magisk/KernelSU active. Details: ${result.stdout.toString().trim()}');
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
          onTap: (i) => setState(() => _currentIndex = i),
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
  bool? _isRooted;         // null = checking, true = granted, false = denied
  bool _autoRecord = false;

  @override
  void initState() {
    super.initState();
    _checkRoot();
    _loadPrefs();
  }

  Future<void> _checkRoot() async {
    try {
      final result = await Process.run('su', ['-c', 'id']);
      if (mounted) setState(() => _isRooted = result.exitCode == 0);
    } catch (_) {
      if (mounted) setState(() => _isRooted = false);
    }
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _autoRecord = prefs.getBool('auto_record') ?? false);
  }

  Future<void> _toggleAutoRecord(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_record', value);
    if (mounted) setState(() => _autoRecord = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget rootIndicator;
    if (_isRooted == null) {
      rootIndicator = const SizedBox(
        width: 16, height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else {
      rootIndicator = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12, height: 12,
            decoration: BoxDecoration(
              color: _isRooted! ? Colors.green : Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _isRooted! ? 'Granted (Magisk/KernelSU)' : 'Not available',
            style: TextStyle(
              color: _isRooted! ? Colors.green : Colors.red,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Text('Settings'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Root status section
          Text('Root Access', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          rootIndicator,
          const Divider(height: 28),

          // Recording settings
          Text('Recording', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(
            'Saves to: /sdcard/Music/OnyxDialer/',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-record calls'),
            subtitle: const Text('Starts recording automatically when a call connects'),
            value: _autoRecord,
            onChanged: _toggleAutoRecord,
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
