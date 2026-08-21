import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavedialer/themes/onyx/home_screen.dart';
import 'dart:io';
import 'package:shizuku_api/shizuku_api.dart';
import 'package:permission_handler/permission_handler.dart';

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  bool _isChecking = false;
  final _shizuku = ShizukuApi();

  Future<void> _setMode(String mode) async {
    setState(() => _isChecking = true);
    
    // 1. Request Basic Permissions first
    final status = await [
      Permission.contacts,
      Permission.phone,
      Permission.microphone,
      Permission.notification,
      Permission.systemAlertWindow,
      Permission.ignoreBatteryOptimizations,
    ].request();

    if (status[Permission.contacts] != PermissionStatus.granted ||
        status[Permission.phone] != PermissionStatus.granted) {
      _showError('Contacts and Phone permissions are required for the dialer to work.');
      setState(() => _isChecking = false);
      return;
    }

    // 2. Handle specific mode permissions
    if (mode == 'root') {
      try {
        final result = await Process.run('su', ['-c', 'id']);
        if (result.exitCode != 0) {
          _showError('Root access denied. Please grant permission in Magisk/KernelSU.');
          setState(() => _isChecking = false);
          return;
        }
      } catch (e) {
        _showError('Root not found on this device.');
        setState(() => _isChecking = false);
        return;
      }
    } else if (mode == 'shizuku') {
      final isRunning = await _shizuku.pingBinder() ?? false;
      if (!isRunning) {
        _showError('Shizuku is not running. Please start it first.');
        setState(() => _isChecking = false);
        return;
      }
      
      final hasPerm = await _shizuku.checkPermission() ?? false;
      if (!hasPerm) {
        final granted = await _shizuku.requestPermission() ?? false;
        if (!granted) {
          _showError('Shizuku permission denied.');
          setState(() => _isChecking = false);
          return;
        }
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('start_mode', mode);
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    const iosBlue = Color(0xFF007AFF);
    const iosCard = Color(0xFF1C1C1E);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 60),
                const Icon(Icons.shield_rounded, size: 80, color: iosBlue),
                const SizedBox(height: 24),
                const Text(
                  'Welcome to Onyx',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Select your preferred engine for\nadvanced call features.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const Spacer(),
                
                if (_isChecking)
                  const Center(child: CircularProgressIndicator(color: iosBlue))
                else ...[
                _buildOption(
                  icon: Icons.bolt_rounded,
                  title: 'Root Mode',
                  subtitle: 'Best for native recording & system control',
                  onTap: () => _setMode('root'),
                ),
                const SizedBox(height: 16),
                _buildOption(
                  icon: Icons.layers_rounded,
                  title: 'Shizuku Mode',
                  subtitle: 'Advanced features without root access',
                  onTap: () => _setMode('shizuku'),
                ),
                const SizedBox(height: 16),
                _buildOption(
                  icon: Icons.no_encryption_gmailerrorred_rounded,
                  title: 'Basic Mode',
                  subtitle: 'Standard dialer without recording',
                  onTap: () => _setMode('none'),
                ),
              ],
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    ),
  );
}

  Widget _buildOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF007AFF).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: const Color(0xFF007AFF), size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(fontSize: 14, color: Colors.grey)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey, size: 16),
          ],
        ),
      ),
    );
  }
}
