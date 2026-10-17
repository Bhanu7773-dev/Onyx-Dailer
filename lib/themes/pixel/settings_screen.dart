import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavedialer/services/telecom_service.dart';
import 'package:wavedialer/services/ota_update_service.dart';
import 'package:wavedialer/logic/theme_controller.dart';

const _kBg = Color(0xFF0C0E12);
const _kCardBg = Color(0xFF161D26);
const _kAvatarBg = Color(0xFF1E2632);
const _kBlueAccent = Color(0xFF8AB4F8);
const _kCoralRed = Color(0xFFFF7769);
const _kGreen = Color(0xFF34C759);
const _kTextWhite = Color(0xFFFFFFFF);
const _kTextMuted = Color(0xFF8E9CAE);
const _kSeparator = Color(0xFF1E2530);
const _kHandleColor = Color(0xFF353E4A);

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
  String _appTheme = 'pixel';
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
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _kCardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          title: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _kBlueAccent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_outline_rounded, color: _kBlueAccent, size: 28),
              ),
              const SizedBox(height: 14),
              const Text(
                'Software Up to Date',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          content: Text(
            'Your dialer is running the latest version ($_currentVersion).',
            style: const TextStyle(color: _kTextMuted, fontSize: 14, height: 1.4),
            textAlign: TextAlign.center,
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          actions: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _kBlueAccent,
                  foregroundColor: const Color(0xFF09182C),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ],
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _kCardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          title: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _kCoralRed.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.cloud_off_rounded, color: _kCoralRed, size: 28),
              ),
              const SizedBox(height: 14),
              const Text(
                'Update Check Failed',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          content: const Text(
            'Unable to check for updates. Please verify your internet connection.',
            style: TextStyle(color: _kTextMuted, fontSize: 14, height: 1.4),
            textAlign: TextAlign.center,
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          actions: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _kBlueAccent,
                  foregroundColor: const Color(0xFF09182C),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
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
          _defaultSim = sims.first['id']!;
          prefs.setString('default_sim', _defaultSim);
        } else if (sims.length >= 2) {
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
        _appTheme = prefs.getString('selected_layout_theme') ?? 'pixel';
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
    showModalBottomSheet(
      context: context,
      backgroundColor: _kCardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: _kHandleColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Select Visual Theme',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Choose a design layout style for your dialer.',
                style: TextStyle(color: _kTextMuted, fontSize: 13),
              ),
              const SizedBox(height: 18),

              _buildThemeOption(
                title: 'Pixel UI',
                subtitle: 'Google Pixel Expressive dark theme with analytics & glowing controls',
                themeKey: 'pixel',
                icon: Icons.smartphone_rounded,
                onTap: () {
                  _setAppTheme('pixel');
                  Navigator.pop(ctx);
                },
              ),
              const SizedBox(height: 10),
              _buildThemeOption(
                title: 'Onyx',
                subtitle: 'iOS-inspired dark dialer layout with blur and clean typography',
                themeKey: 'onyx',
                icon: Icons.phone_iphone_rounded,
                onTap: () {
                  _setAppTheme('onyx');
                  Navigator.pop(ctx);
                },
              ),
              const SizedBox(height: 10),
              _buildThemeOption(
                title: 'Nothing UI',
                subtitle: 'Monochrome dot-matrix typography & glyph aesthetic',
                themeKey: 'nothing',
                icon: Icons.grain_rounded,
                onTap: () {
                  _setAppTheme('nothing');
                  Navigator.pop(ctx);
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThemeOption({
    required String title,
    required String subtitle,
    required String themeKey,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final isSelected = _appTheme == themeKey;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1B2636) : const Color(0xFF1E2632),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? _kBlueAccent : Colors.white.withValues(alpha: 0.04),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isSelected ? _kBlueAccent.withValues(alpha: 0.15) : _kCardBg,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isSelected ? _kBlueAccent : _kTextMuted,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? _kBlueAccent : Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: _kTextMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle_rounded, color: _kBlueAccent, size: 22),
          ],
        ),
      ),
    );
  }

  void _showSimSelectionSheet() {
    if (_simCards.length < 2) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: _kCardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: _kHandleColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Default Calling SIM',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Choose which SIM to use for placing outgoing calls.',
                style: TextStyle(color: _kTextMuted, fontSize: 13),
              ),
              const SizedBox(height: 18),

              _buildSimOption(
                label: 'Ask Every Time',
                simId: 'ask',
                icon: Icons.help_outline_rounded,
                onTap: () {
                  _setDefaultSim('ask');
                  Navigator.pop(ctx);
                },
              ),
              const SizedBox(height: 10),

              ..._simCards.map((sim) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildSimOption(
                  label: sim['label'] ?? 'SIM Card',
                  simId: sim['id'] ?? '',
                  icon: Icons.sim_card_outlined,
                  onTap: () {
                    _setDefaultSim(sim['id']!);
                    Navigator.pop(ctx);
                  },
                ),
              )),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSimOption({
    required String label,
    required String simId,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final isSelected = _defaultSim == simId;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1B2636) : const Color(0xFF1E2632),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? _kBlueAccent : Colors.white.withValues(alpha: 0.04),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isSelected ? _kBlueAccent.withValues(alpha: 0.15) : _kCardBg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: isSelected ? _kBlueAccent : _kTextMuted, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? _kBlueAccent : Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle_rounded, color: _kBlueAccent, size: 22),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget rootIndicator;
    if (_isRooted == null) {
      rootIndicator = const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: _kBlueAccent),
      );
    } else {
      rootIndicator = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: _isRooted! ? _kGreen : _kCoralRed,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _isRooted! ? 'Granted' : 'Not Available',
            style: TextStyle(
              color: _isRooted! ? _kGreen : _kCoralRed,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 24),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(
            color: _kTextWhite,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 60),
        children: [
          // Section 1: System Info
          _buildSectionHeader('SYSTEM INFO'),
          _buildSettingCard([
            _buildListTile(
              title: 'Root Status',
              subtitle: 'Superuser permission status',
              icon: Icons.security_rounded,
              trailing: rootIndicator,
            ),
          ]),

          // Section 2: Call Recording
          _buildSectionHeader('CALL RECORDING'),
          _buildSettingCard([
            _buildSwitchTile(
              title: 'Auto-record calls',
              subtitle: 'Starts recording automatically when call connects',
              icon: Icons.fiber_manual_record_rounded,
              value: _autoRecord,
              onChanged: _toggleAutoRecord,
            ),
            const Divider(color: _kSeparator, height: 1, indent: 68),
            _buildListTile(
              title: 'Storage Directory',
              subtitle: '/storage/emulated/0/Recordings/OnyxDialer/',
              icon: Icons.folder_outlined,
            ),
          ]),

          // Section 3: Smart Protections
          _buildSectionHeader('PROTECTION & SENSORS'),
          _buildSettingCard([
            _buildSwitchTile(
              title: 'Spam Protection',
              subtitle: 'Identify and flag suspected spam calls locally',
              icon: Icons.shield_outlined,
              value: _spamProtection,
              onChanged: _toggleSpamProtection,
            ),
            const Divider(color: _kSeparator, height: 1, indent: 68),
            _buildSwitchTile(
              title: 'Block proximity sensor',
              subtitle: 'Keeps screen active during calls near ear',
              icon: Icons.sensors_off_rounded,
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
              icon: Icons.sim_card_outlined,
              trailing: _simCards.length >= 2
                  ? const Icon(Icons.keyboard_arrow_down_rounded, color: _kTextMuted, size: 22)
                  : null,
              onTap: _simCards.length >= 2 ? _showSimSelectionSheet : null,
            ),
          ]),

          // Section 5: Appearance & Themes
          _buildSectionHeader('APPEARANCE & THEMES'),
          _buildSettingCard([
            _buildListTile(
              title: 'App Theme',
              subtitle: _appTheme == 'pixel'
                  ? 'Pixel UI'
                  : (_appTheme == 'nothing'
                      ? 'Nothing UI'
                      : 'Onyx'),
              icon: Icons.palette_outlined,
              trailing: const Icon(Icons.keyboard_arrow_down_rounded, color: _kTextMuted, size: 22),
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
              icon: Icons.system_update_rounded,
              trailing: _isCheckingUpdate
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _kBlueAccent),
                    )
                  : (_availableUpdate != null && _availableUpdate!.isNewer
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _kBlueAccent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'UPDATE',
                            style: TextStyle(
                              color: Color(0xFF09182C),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      : const Icon(Icons.refresh_rounded, color: _kTextMuted, size: 20)),
              onTap: _isCheckingUpdate ? null : _checkUpdateManually,
            ),
          ]),

          // Section 7: About & Legal
          _buildSectionHeader('ABOUT & LEGAL'),
          _buildSettingCard([
            _buildListTile(
              title: 'Open Source Licenses',
              subtitle: 'Third-party libraries and licenses',
              icon: Icons.description_outlined,
              trailing: const Icon(Icons.chevron_right_rounded, color: _kTextMuted, size: 22),
              onTap: () {
                showLicensePage(
                  context: context,
                  applicationName: 'Onyx Dialer (Pixel UI)',
                  applicationVersion: 'v$_currentVersion',
                  applicationLegalese: '© 2026 Bhanu Pratap Singh Rajawat\nLicensed under the MIT License',
                );
              },
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 22, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: _kTextMuted,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSettingCard(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildListTile({
    required String title,
    String? subtitle,
    required IconData icon,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: _kAvatarBg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: _kBlueAccent, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: _kTextWhite, fontSize: 15, fontWeight: FontWeight.w600)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(color: _kTextMuted, fontSize: 12)),
                  ],
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: _kAvatarBg,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: _kBlueAccent, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: _kTextWhite, fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: _kTextMuted, fontSize: 12)),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: const Color(0xFF09182C),
            activeTrackColor: _kBlueAccent,
            inactiveThumbColor: _kTextMuted,
            inactiveTrackColor: const Color(0xFF222C3A),
            trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
            onChanged: (v) {
              HapticFeedback.lightImpact();
              onChanged(v);
            },
          ),
        ],
      ),
    );
  }
}
