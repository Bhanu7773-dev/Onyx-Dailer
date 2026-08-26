import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavedialer/services/telecom_service.dart';
import 'package:wavedialer/services/ota_update_service.dart';
import 'package:wavedialer/logic/theme_controller.dart';

String get _nFont => ThemeController.instance.nothingFontFamily;

// Nothing UI Colors
const _bg = Color(0xFF000000);
const _nCard = Color(0xFF161616);
const _nLabel = Color(0xFFFFFFFF);
const _nSecondary = Color(0xFF7E7E7E);
const _nDivider = Color(0xFF222222);
const _nRed = Color(0xFFE5162A);

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
  String _appTheme = 'nothing';
  String _nothingFont = 'dot'; // 'dot' | 'serif'
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
    HapticFeedback.selectionClick();
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
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF141414),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF2E2E2E)),
          ),
          title: Text(
            'SYSTEM UP TO DATE',
            style: TextStyle(fontFamily: _nFont, color: Colors.white, fontSize: 13, letterSpacing: 1.5, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'You are running the latest version (${update.currentVersion}).',
            style: const TextStyle(color: Color(0xFF888888), fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('OK', style: TextStyle(fontFamily: _nFont, color: _nRed, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF1C1C1E),
          content: Text(
            'Unable to check for updates. Check internet connection.',
            style: TextStyle(fontFamily: _nFont, color: Colors.white, fontSize: 12),
          ),
        ),
      );
    }
  }

  Future<void> _loadSimCards() async {
    final sims = await TelecomService.getSimCards();
    if (mounted) {
      setState(() {
        _simCards = sims;
        if (_simCards.length == 1) {
          _setDefaultSim(_simCards.first['id']!);
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
        _appTheme = prefs.getString('selected_layout_theme') ?? 'nothing';
        _nothingFont = prefs.getString('nothing_font') ?? 'dot';
      });
    }
  }

  Future<void> _toggleAutoRecord(bool value) async {
    HapticFeedback.lightImpact();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_record', value);
    if (mounted) setState(() => _autoRecord = value);
  }

  Future<void> _toggleBlockProximity(bool value) async {
    HapticFeedback.lightImpact();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('block_proximity', value);
    if (mounted) setState(() => _blockProximity = value);
  }

  Future<void> _toggleSpamProtection(bool value) async {
    HapticFeedback.lightImpact();
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

  Future<void> _setNothingFont(String font) async {
    HapticFeedback.selectionClick();
    await ThemeController.instance.setNothingFont(font);
    if (mounted) setState(() => _nothingFont = font);
  }

  Widget _buildNothingFontPicker() {
    final isDot = _nothingFont == 'dot';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _nCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _nDivider, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Text(
              'NOTHING FONT STYLE',
              style: TextStyle(
                fontFamily: _nFont,
                fontSize: 10,
                letterSpacing: 2,
                color: _nSecondary,
              ),
            ),
          ),
          // Segmented toggle
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D0D),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                // DOT-MATRIX option
                Expanded(
                  child: GestureDetector(
                    onTap: () => _setNothingFont('dot'),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: isDot ? _nRed : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: isDot
                            ? [BoxShadow(color: _nRed.withValues(alpha: 0.3), blurRadius: 8)]
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          'DOT·MATRIX',
                          style: TextStyle(
                            fontFamily: _nFont,
                            fontSize: 11,
                            letterSpacing: 1.5,
                            color: isDot ? Colors.white : _nSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // SERIF option
                Expanded(
                  child: GestureDetector(
                    onTap: () => _setNothingFont('serif'),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: !isDot ? _nRed : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: !isDot
                            ? [BoxShadow(color: _nRed.withValues(alpha: 0.3), blurRadius: 8)]
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          'Serif',
                          style: TextStyle(
                            fontFamily: 'NotoSerifFont',
                            fontSize: 14,
                            color: !isDot ? Colors.white : _nSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Preview row
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Text(
              isDot ? 'Aa  0123  NOTHING DIALER' : 'Aa  0123  Nothing Dialer',
              style: TextStyle(
                fontFamily: isDot ? 'NothingFont' : 'NotoSerifFont',
                fontSize: isDot ? 13 : 15,
                color: _nSecondary,
                letterSpacing: isDot ? 1.2 : 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }


  void _showThemeSelectionSheet() {
    HapticFeedback.mediumImpact();
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: CupertinoActionSheet(
          title: Text(
            'SELECT THEME',
            style: TextStyle(
              color: _nLabel,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
              fontFamily: _nFont,
            ),
          ),
          message: const Text(
            'Choose a visual layout theme for the application.',
            style: TextStyle(color: _nSecondary),
          ),
          actions: [
            CupertinoActionSheetAction(
              onPressed: () {
                _setAppTheme('nothing');
                Navigator.pop(ctx);
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Nothing UI', style: TextStyle(color: _nLabel, fontFamily: _nFont)),
                  if (_appTheme == 'nothing') ...[
                    const SizedBox(width: 8),
                    const Icon(CupertinoIcons.checkmark_alt, color: _nRed, size: 18),
                  ],
                ],
              ),
            ),
            CupertinoActionSheetAction(
              onPressed: () {
                _setAppTheme('onyx');
                Navigator.pop(ctx);
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Onyx (iOS Style)', style: TextStyle(color: _nLabel, fontFamily: _nFont)),
                  if (_appTheme == 'onyx') ...[
                    const SizedBox(width: 8),
                    const Icon(CupertinoIcons.checkmark_alt, color: _nRed, size: 18),
                  ],
                ],
              ),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: _nSecondary, fontFamily: _nFont)),
          ),
        ),
      ),
    );
  }

  void _showSimSelectionSheet() {
    HapticFeedback.mediumImpact();
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: CupertinoActionSheet(
          title: Text(
            'DEFAULT CALLING SIM',
            style: TextStyle(
              color: _nLabel,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
              fontFamily: _nFont,
            ),
          ),
          message: const Text(
            'Select the SIM card to use for outgoing calls.',
            style: TextStyle(color: _nSecondary),
          ),
          actions: [
            CupertinoActionSheetAction(
              onPressed: () {
                _setDefaultSim('ask');
                Navigator.pop(ctx);
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Ask Every Time', style: TextStyle(color: _nLabel, fontFamily: _nFont)),
                  if (_defaultSim == 'ask') ...[
                    const SizedBox(width: 8),
                    const Icon(CupertinoIcons.checkmark_alt, color: _nRed, size: 18),
                  ],
                ],
              ),
            ),
            ..._simCards.map((sim) => CupertinoActionSheetAction(
                  onPressed: () {
                    _setDefaultSim(sim['id']!);
                    Navigator.pop(ctx);
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(sim['label'] ?? 'Unknown SIM', style: TextStyle(color: _nLabel, fontFamily: _nFont)),
                      if (_defaultSim == sim['id']) ...[
                        const SizedBox(width: 8),
                        const Icon(CupertinoIcons.checkmark_alt, color: _nRed, size: 18),
                      ],
                    ],
                  ),
                )),
          ],
          cancelButton: CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: _nSecondary, fontFamily: _nFont)),
          ),
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
        child: CircularProgressIndicator(strokeWidth: 2, color: _nRed),
      );
    } else {
      rootIndicator = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: _isRooted! ? const Color(0xFF1E3A20) : const Color(0xFF331414),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isRooted! ? const Color(0xFF34C759) : _nRed,
            width: 1,
          ),
        ),
        child: Text(
          _isRooted! ? 'ACTIVE' : 'INACTIVE',
          style: TextStyle(
            color: _isRooted! ? const Color(0xFF34C759) : _nRed,
            fontWeight: FontWeight.bold,
            fontSize: 11,
            letterSpacing: 1.5,
            fontFamily: _nFont,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top Bar: Back button + SETTINGS
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: _nLabel, size: 24),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    'SETTINGS',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: _nLabel,
                      letterSpacing: 3.5,
                      fontFamily: _nFont,
                    ),
                  ),
                ],
              ),
            ),

            // Settings List
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 40),
                children: [
                  // Section 1: System Status
                  _buildSectionHeader('SYSTEM STATUS'),
                  _buildSettingCard([
                    _buildListTile(
                      title: 'ROOT ENGINE',
                      subtitle: 'Direct hardware two-sided call recording',
                      trailing: rootIndicator,
                    ),
                  ]),

                  // Section 2: Appearance & Theme
                  _buildSectionHeader('APPEARANCE & THEMES'),
                  _buildSettingCard([
                    _buildListTile(
                      title: 'APP THEME',
                      subtitle: _appTheme == 'nothing' ? 'Nothing UI' : 'Onyx (iOS Style)',
                      trailing: const Icon(Icons.arrow_forward_ios_rounded, color: _nSecondary, size: 14),
                      onTap: _showThemeSelectionSheet,
                    ),
                  ]),

                  // Font switcher — only shown when Nothing theme is active
                  if (_appTheme == 'nothing') ...[
                    const SizedBox(height: 8),
                    _buildNothingFontPicker(),
                  ],

                  // Section 3: Call Recording
                  _buildSectionHeader('CALL RECORDING'),
                  _buildSettingCard([
                    _buildSwitchTile(
                      title: 'AUTO-RECORD CALLS',
                      subtitle: 'Automatically captures incoming and outgoing calls',
                      value: _autoRecord,
                      onChanged: _toggleAutoRecord,
                    ),
                    const Divider(color: _nDivider, height: 1, indent: 16),
                    _buildListTile(
                      title: 'STORAGE LOCATION',
                      subtitle: '/storage/emulated/0/Recordings/OnyxDialer/',
                    ),
                  ]),

                  // Section 4: Carrier & SIM
                  _buildSectionHeader('CARRIER & SIM'),
                  _buildSettingCard([
                    _buildListTile(
                      title: 'DEFAULT CALLING SIM',
                      subtitle: _defaultSim == 'ask'
                          ? 'Ask Every Time'
                          : (_simCards.firstWhere((sim) => sim['id'] == _defaultSim, orElse: () => {'label': 'Unknown'})['label'] ?? 'Unknown'),
                      trailing: _simCards.length <= 1
                          ? null
                          : const Icon(Icons.arrow_forward_ios_rounded, color: _nSecondary, size: 14),
                      onTap: _simCards.length <= 1 ? null : _showSimSelectionSheet,
                    ),
                  ]),

                  // Section 5: Sensors & Protection
                  _buildSectionHeader('PROTECTION & SENSORS'),
                  _buildSettingCard([
                    _buildSwitchTile(
                      title: 'SPAM PROTECTION',
                      subtitle: 'Identify and flag suspected spam calls locally',
                      value: _spamProtection,
                      onChanged: _toggleSpamProtection,
                    ),
                    const Divider(color: _nDivider, height: 1, indent: 16),
                    _buildSwitchTile(
                      title: 'BLOCK PROXIMITY SENSOR',
                      subtitle: 'Keep screen active during calls near ear',
                      value: _blockProximity,
                      onChanged: _toggleBlockProximity,
                    ),
                  ]),

                  // Section 6: OTA & Software Updates
                  _buildSectionHeader('SOFTWARE UPDATES'),
                  _buildSettingCard([
                    _buildListTile(
                      title: 'CHECK FOR UPDATES',
                      subtitle: _isCheckingUpdate
                          ? 'Checking GitHub releases...'
                          : (_availableUpdate != null && _availableUpdate!.isNewer
                              ? 'Update ${_availableUpdate!.latestTag} available'
                              : 'Current version: v$_currentVersion (Up to date)'),
                      trailing: _isCheckingUpdate
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: _nRed),
                            )
                          : (_availableUpdate != null && _availableUpdate!.isNewer
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _nRed,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'UPDATE',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontFamily: _nFont,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded, color: _nSecondary, size: 20)),
                      onTap: _isCheckingUpdate ? null : _checkUpdateManually,
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 22, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          color: _nSecondary,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 2,
          fontFamily: _nFont,
        ),
      ),
    );
  }

  Widget _buildSettingCard(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: _nCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _nDivider, width: 1),
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
      onTap: onTap,
      title: Text(
        title,
        style: TextStyle(
          color: _nLabel,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          fontFamily: _nFont,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: const TextStyle(color: _nSecondary, fontSize: 12, height: 1.3),
            )
          : null,
      trailing: trailing,
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      value: value,
      activeThumbColor: Colors.white,
      activeTrackColor: _nRed,
      inactiveThumbColor: const Color(0xFF888888),
      inactiveTrackColor: const Color(0xFF282828),
      onChanged: onChanged,
      title: Text(
        title,
        style: TextStyle(
          color: _nLabel,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          fontFamily: _nFont,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: _nSecondary, fontSize: 12, height: 1.3),
      ),
    );
  }
}
