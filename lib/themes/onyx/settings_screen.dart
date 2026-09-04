import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavedialer/services/telecom_service.dart';
import 'package:wavedialer/services/ota_update_service.dart';
import 'package:wavedialer/logic/theme_controller.dart';

const _iosBlue = Color(0xFF007AFF);
const _iosRed = Color(0xFFFF3B30);
const _iosBg = Color(0xFF000000);
const _iosCard = Color(0xFF1C1C1E);
const _iosSeparator = Color(0xFF38383A);
const _iosLabel = Color(0xFFFFFFFF);
const _iosSecondary = Color(0xFF8E8E93);

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? _isRooted;
  bool _autoRecord = false;
  bool _blockProximity = false;
  bool _spamProtection = false;

  String _defaultSim = 'ask';
  String _appTheme = 'onyx';
  String _currentVersion = '1.0.1';
  bool _isCheckingUpdate = false;
  UpdateInfo? _availableUpdate;
  List<Map<String, String>> _simCards = [];

  @override
  void initState() {
    super.initState();
    _checkRoot();
    _loadPrefs();
    _loadSimCards();
    _loadVersion();
    _checkUpdateQuietly();
  }

  Future<void> _loadVersion() async {
    final ver = await OtaUpdateService.instance.getCurrentVersion();
    if (mounted) setState(() => _currentVersion = ver);
  }

  Future<void> _checkUpdateQuietly() async {
    final update = await OtaUpdateService.instance.checkForUpdate();
    if (mounted && update != null) {
      setState(() => _availableUpdate = update);
    }
  }

  Future<void> _checkUpdateManually() async {
    setState(() => _isCheckingUpdate = true);
    final update = await OtaUpdateService.instance.checkForUpdate();
    if (!mounted) return;
    setState(() {
      _isCheckingUpdate = false;
      _availableUpdate = update;
    });

    if (update != null && update.isNewer) {
      OtaUpdateService.instance.showUpdateModal(context, update);
    } else if (update != null) {
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Software Up to Date'),
          content: Text('\nYour Onyx Dialer is running the latest version ($_currentVersion).'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } else {
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Update Check Failed'),
          content: const Text('\nUnable to check for updates. Please verify your internet connection.'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _loadSimCards() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final sims = await TelecomService.getSimCards();
    if (mounted) {
      final savedSim = prefs.getString('default_sim') ?? 'ask';
      final validIds = sims.map((s) => s['id']).toSet();
      setState(() {
        _simCards = sims;
        if (sims.length == 1) {
          // Single SIM: auto-select it
          _defaultSim = sims.first['id']!;
          prefs.setString('default_sim', _defaultSim);
        } else if (sims.length >= 2) {
          // Dual SIM: use saved pref if valid, otherwise 'ask'
          if (savedSim == 'ask' || validIds.contains(savedSim)) {
            _defaultSim = savedSim;
          } else {
            _defaultSim = 'ask';
            prefs.setString('default_sim', 'ask');
          }
        }
      });
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

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _autoRecord = prefs.getBool('auto_record') ?? false;
        _blockProximity = prefs.getBool('block_proximity') ?? false;
        _spamProtection = prefs.getBool('spam_protection') ?? false;
        _defaultSim = prefs.getString('default_sim') ?? 'ask';
        _appTheme = prefs.getString('selected_layout_theme') ?? 'onyx';
      });
    }
  }



  Future<void> _toggleAutoRecord(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_record', value);
    if (mounted) setState(() => _autoRecord = value);
  }

  Future<void> _toggleBlockProximity(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('block_proximity', value);
    if (mounted) setState(() => _blockProximity = value);
  }

  Future<void> _toggleSpamProtection(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('spam_protection', value);
    if (mounted) setState(() => _spamProtection = value);
  }

  Future<void> _setDefaultSim(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('default_sim', value);
    if (mounted) setState(() => _defaultSim = value);
  }

  Future<void> _setAppTheme(String value) async {
    await ThemeController.instance.setTheme(value);
    if (mounted) setState(() => _appTheme = value);
  }

  void _showThemeSelectionSheet() {
    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) => CupertinoActionSheet(
        title: const Text('Select Theme'),
        message: const Text('Choose a visual layout theme for the application.'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              _setAppTheme('onyx');
              Navigator.pop(context);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Onyx (Default)'),
                if (_appTheme == 'onyx') const Icon(CupertinoIcons.check_mark, size: 18),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              _setAppTheme('nothing');
              Navigator.pop(context);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Nothing UI'),
                if (_appTheme == 'nothing') const Icon(CupertinoIcons.check_mark, size: 18),
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _showSimSelectionSheet() {
    if (_simCards.length < 2) return; // Only show when dual SIM
    final availableSims = _simCards;

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
          ...availableSims.map((sim) => CupertinoActionSheetAction(
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
    Widget rootIndicator;
    if (_isRooted == null) {
      rootIndicator = const SizedBox(
        width: 16, height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: _iosBlue),
      );
    } else {
      rootIndicator = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10, height: 10,
            decoration: BoxDecoration(
              color: _isRooted! ? const Color(0xFF34C759) : _iosRed,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _isRooted! ? 'Granted' : 'Not Available',
            style: TextStyle(
              color: _isRooted! ? const Color(0xFF34C759) : _iosRed,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: _iosBg,
      appBar: AppBar(
        backgroundColor: _iosBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back, color: _iosBlue),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(color: _iosLabel, fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        children: [
          // Section 1: System Info
          _buildSectionHeader('SYSTEM INFO'),
          _buildSettingCard([
            _buildListTile(
              title: 'Root Status',
              trailing: rootIndicator,
            ),
          ]),

          // Section 2: Call Recording
          _buildSectionHeader('CALL RECORDING'),
          _buildSettingCard([
            _buildSwitchTile(
              title: 'Auto-record calls',
              subtitle: 'Starts recording automatically on connect',
              value: _autoRecord,
              onChanged: _toggleAutoRecord,
            ),
            const Divider(color: _iosSeparator, height: 1, indent: 16),
            _buildListTile(
              title: 'Storage Directory',
              subtitle: '/storage/emulated/0/Recordings/OnyxDialer/',
            ),
          ]),

          // Section 3: Smart Protections
          _buildSectionHeader('PROTECTION & SENSORS'),
          _buildSettingCard([
            _buildSwitchTile(
              title: 'Spam Protection',
              subtitle: 'Identify and flag suspected spam calls locally',
              value: _spamProtection,
              onChanged: _toggleSpamProtection,
            ),
            const Divider(color: _iosSeparator, height: 1, indent: 16),
            _buildSwitchTile(
              title: 'Block proximity sensor',
              subtitle: 'Keeps screen active during calls near ear',
              value: _blockProximity,
              onChanged: _toggleBlockProximity,
            ),
          ]),

          // Section 4: Calling Settings
          _buildSectionHeader('CARRIER & SIM'),
          _buildSettingCard([
            _buildListTile(
              title: 'Default Calling SIM',
              subtitle: _simCards.length >= 2
                  ? (_defaultSim == 'ask'
                      ? 'Ask Every Time'
                      : (_simCards.firstWhere(
                          (sim) => sim['id'] == _defaultSim,
                          orElse: () => {'label': 'SIM 1'},
                        )['label'] ?? 'SIM 1'))
                  : (_simCards.isNotEmpty
                      ? (_simCards.first['label'] ?? 'SIM 1')
                      : 'No SIM detected'),
              trailing: _simCards.length >= 2
                  ? const Icon(CupertinoIcons.chevron_up_chevron_down, color: _iosSecondary, size: 16)
                  : null,
              onTap: _simCards.length >= 2 ? _showSimSelectionSheet : null,
            ),
          ]),

          // Section 5: Appearance & Themes
          _buildSectionHeader('APPEARANCE & THEMES'),
          _buildSettingCard([
            _buildListTile(
              title: 'App Theme',
              subtitle: _appTheme == 'onyx'
                  ? 'Onyx (Default)'
                  : _appTheme == 'nothing'
                      ? 'Nothing UI'
                      : _appTheme.toUpperCase(),
              trailing: const Icon(CupertinoIcons.chevron_up_chevron_down, color: _iosSecondary, size: 16),
              onTap: _showThemeSelectionSheet,
            ),
          ]),

          // Section 6: Software Updates
          _buildSectionHeader('SOFTWARE UPDATES'),
          _buildSettingCard([
            _buildListTile(
              title: 'Check for Updates',
              subtitle: _isCheckingUpdate
                  ? 'Checking GitHub releases...'
                  : (_availableUpdate != null && _availableUpdate!.isNewer
                      ? 'Update ${_availableUpdate!.latestTag} available'
                      : 'Version $_currentVersion (Up to date)'),
              trailing: _isCheckingUpdate
                  ? const CupertinoActivityIndicator()
                  : (_availableUpdate != null && _availableUpdate!.isNewer
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _iosBlue,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'UPDATE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      : const Icon(CupertinoIcons.arrow_clockwise, color: _iosSecondary, size: 18)),
              onTap: _isCheckingUpdate ? null : _checkUpdateManually,
            ),
          ]),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 20, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: _iosSecondary,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSettingCard(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: _iosCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildListTile({
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      title: Text(title, style: const TextStyle(color: _iosLabel, fontSize: 16)),
      subtitle: subtitle != null ? Text(subtitle, style: const TextStyle(color: _iosSecondary, fontSize: 12)) : null,
      trailing: trailing,
      onTap: onTap,
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      title: Text(title, style: const TextStyle(color: _iosLabel, fontSize: 16)),
      subtitle: Text(subtitle, style: const TextStyle(color: _iosSecondary, fontSize: 12)),
      value: value,
      activeThumbColor: _iosBlue,
      onChanged: onChanged,
    );
  }
}
