// Pixel home screen
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavedialer/themes/pixel/dialpad_screen.dart';
import 'package:wavedialer/themes/pixel/contacts_screen.dart';
import 'package:wavedialer/themes/pixel/recents_screen.dart';
import 'package:wavedialer/themes/pixel/recordings_screen.dart';
import 'package:wavedialer/services/telecom_service.dart';

const _kBg = Color(0xFF0B0F14);
const _kBottomBarBg = Color(0xFF121820);
const _kBottomBarBorder = Color(0xFF1E2836);
const _kActivePillBg = Color(0xFF1E354F);
const _kActiveBlue = Color(0xFF8AB4F8);
const _kInactiveIcon = Color(0xFF8E9CAE);
const _kFabBg = Color(0xFF8AB4F8);
const _kFabIcon = Color(0xFF09182C);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<bool> _initialized = [false, true, false]; // Default Recents (index 1) active
  int _currentIndex = 1;

  Widget _getScreen(int index) {
    switch (index) {
      case 0:
        return const RecordingsScreen();
      case 1:
        return const RecentsScreen();
      case 2:
        return const ContactsScreen();
      default:
        return const RecentsScreen();
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

  void _onTabSelected(int index) {
    HapticFeedback.selectionClick();
    setState(() {
      _currentIndex = index;
      if (!_initialized[index]) {
        _initialized[index] = true;
        _screens[index] = _getScreen(index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: _kBg,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: _kBg,
        body: Stack(
          children: [
            // Body views
            IndexedStack(
              index: _currentIndex,
              children: _screens,
            ),

            // Floating Navigation Pill & FAB at bottom
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    // Floating Bottom Nav Capsule
                    _buildFloatingNavBar(),

                    const Spacer(),

                    // Floating Action Button (FAB)
                    _buildDialerFab(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Floating Navigation Pill ──────────────────────────────────────────────
  Widget _buildFloatingNavBar() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: _kBottomBarBg,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: _kBottomBarBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildNavTab(
            index: 0,
            icon: Icons.mic_none_rounded,
            activeIcon: Icons.mic_rounded,
            label: 'Recordings',
          ),
          const SizedBox(width: 4),
          _buildNavTab(
            index: 1,
            icon: Icons.access_time_rounded,
            activeIcon: Icons.access_time_filled_rounded,
            label: 'Recents',
          ),
          const SizedBox(width: 4),
          _buildNavTab(
            index: 2,
            icon: Icons.person_outline_rounded,
            activeIcon: Icons.person_rounded,
            label: 'Contacts',
          ),
        ],
      ),
    );
  }

  Widget _buildNavTab({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
  }) {
    final isSelected = _currentIndex == index;

    if (isSelected) {
      // Expanded active capsule with icon and label
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _onTabSelected(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: _kActivePillBg,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(activeIcon, color: _kActiveBlue, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: _kActiveBlue,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Inactive circular icon button
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _onTabSelected(index),
      child: Container(
        width: 48,
        height: 48,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: _kInactiveIcon, size: 22),
      ),
    );
  }

  // ── Floating Action Button (FAB) ──────────────────────────────────────────
  Widget _buildDialerFab() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DialpadScreen()),
        );
      },
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: _kFabBg,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: _kFabBg.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Center(
          child: Icon(
            Icons.dialpad_rounded,
            color: _kFabIcon,
            size: 28,
          ),
        ),
      ),
    );
  }
}
