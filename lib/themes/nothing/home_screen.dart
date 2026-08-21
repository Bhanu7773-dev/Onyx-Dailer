import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavedialer/themes/nothing/dialpad_screen.dart';
import 'package:wavedialer/themes/nothing/contacts_screen.dart';
import 'package:wavedialer/themes/nothing/recents_screen.dart';
import 'package:wavedialer/themes/nothing/recordings_screen.dart';
import 'package:wavedialer/services/telecom_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<bool> _initialized = [false, true, false]; // Default Recents (index 1) as initialized

  Widget _getScreen(int index) {
    switch (index) {
      case 0: return const RecordingsScreen();
      case 1: return const RecentsScreen();
      case 2: return const ContactsScreen();
      default: return const RecentsScreen();
    }
  }

  late List<Widget> _screens;
  int _currentIndex = 1;

  @override
  void initState() {
    super.initState();
    _screens = [
      _initialized[0] ? _getScreen(0) : const SizedBox.shrink(),
      _initialized[1] ? _getScreen(1) : const SizedBox.shrink(),
      _initialized[2] ? _getScreen(2) : const SizedBox.shrink(),
    ];
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestPermissions();
      _prewarmShizuku();
    });
  }

  Future<void> _prewarmShizuku() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('start_mode') ?? 'none';
    if (mode == 'shizuku') {
      await TelecomService.prepareShizukuService();
    }
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.contacts,
      Permission.phone,
      Permission.microphone,
      Permission.audio,
    ].request();

    if (!await Permission.manageExternalStorage.isGranted) {
      final status = await Permission.manageExternalStorage.request();
      if (!status.isGranted) {
        await Permission.storage.request();
      }
    }

    TelecomService.requestDefaultDialer();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.black,
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
          onPressed: () async {
            final targetIndex = await Navigator.push<int>(
              context,
              MaterialPageRoute(builder: (_) => const DialpadScreen()),
            );
            if (targetIndex != null && mounted) {
              setState(() {
                _currentIndex = targetIndex;
                if (!_initialized[targetIndex]) {
                  _initialized[targetIndex] = true;
                  _screens[targetIndex] = _getScreen(targetIndex);
                }
              });
            }
          },
          backgroundColor: const Color(0xFFE5162A),
          elevation: 6,
          shape: const CircleBorder(),
          child: const Icon(Icons.dialpad_rounded, color: Colors.white, size: 26),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        bottomNavigationBar: _NothingTabBar(
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

class _NothingTabBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _NothingTabBar({required this.currentIndex, required this.onTap});

  static const _tabs = [
    (icon: Icons.mic_none_rounded, activeIcon: Icons.mic_rounded, label: 'RECORDINGS'),
    (icon: Icons.access_time_rounded, activeIcon: Icons.access_time_filled, label: 'RECENTS'),
    (icon: Icons.person_outline_rounded, activeIcon: Icons.person_rounded, label: 'CONTACTS'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF111111),
        border: Border(top: BorderSide(color: Color(0xFF222222), width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: List.generate(_tabs.length, (i) {
              final tab = _tabs[i];
              final isSelected = i == currentIndex;
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
                      Icon(
                        isSelected ? tab.activeIcon : tab.icon,
                        color: isSelected ? const Color(0xFFE5162A) : const Color(0xFF7E7E7E),
                        size: 22,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        tab.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          letterSpacing: 1.2,
                          fontFamily: 'NothingFont',
                          color: isSelected ? const Color(0xFFE5162A) : const Color(0xFF7E7E7E),
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
