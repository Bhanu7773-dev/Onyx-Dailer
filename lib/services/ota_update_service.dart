import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:wavedialer/logic/theme_controller.dart';

class UpdateInfo {
  final String latestTag;
  final String currentVersion;
  final String releaseTitle;
  final String releaseNotes;
  final String apkDownloadUrl;
  final int apkSize;
  final DateTime? publishedAt;
  final bool isNewer;

  UpdateInfo({
    required this.latestTag,
    required this.currentVersion,
    required this.releaseTitle,
    required this.releaseNotes,
    required this.apkDownloadUrl,
    required this.apkSize,
    this.publishedAt,
    required this.isNewer,
  });

  String get formattedSize {
    if (apkSize <= 0) return '';
    final mb = apkSize / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

class OtaUpdateService {
  static final OtaUpdateService instance = OtaUpdateService._internal();
  OtaUpdateService._internal();

  static const MethodChannel _methodChannel = MethodChannel('dark.onyx.com/telecom_commands');
  static const String _releasesApiUrl = 'https://api.github.com/repos/Bhanu7773-dev/Onyx-Dailer/releases';

  UpdateInfo? lastCheckedUpdate;
  bool isChecking = false;

  /// Gets current installed version from native package manager.
  Future<String> getCurrentVersion() async {
    try {
      final res = await _methodChannel.invokeMethod<Map>('getAppVersion');
      if (res != null && res['versionName'] != null) {
        return res['versionName'].toString();
      }
    } catch (e) {
      debugPrint('OtaUpdateService: Error getting current version: $e');
    }
    return '1.0.1';
  }

  /// Compares two semver strings (e.g. "v1.0.2" > "1.0.1", "2.0.0" > "1.0.1").
  /// Returns:
  ///   1 if versionA > versionB
  ///  -1 if versionA < versionB
  ///   0 if versionA == versionB
  int compareVersions(String versionA, String versionB) {
    try {
      final aMain = versionA.split('+').first.trim();
      final bMain = versionB.split('+').first.trim();

      final aParts = RegExp(r'\d+').allMatches(aMain).map((m) => int.parse(m.group(0)!)).toList();
      final bParts = RegExp(r'\d+').allMatches(bMain).map((m) => int.parse(m.group(0)!)).toList();

      final maxLen = aParts.length > bParts.length ? aParts.length : bParts.length;
      while (aParts.length < maxLen) {
        aParts.add(0);
      }
      while (bParts.length < maxLen) {
        bParts.add(0);
      }

      for (int i = 0; i < maxLen; i++) {
        if (aParts[i] > bParts[i]) return 1;
        if (aParts[i] < bParts[i]) return -1;
      }

      // Check build numbers if present (e.g. +2 vs +1)
      if (versionA.contains('+') && versionB.contains('+')) {
        final aBuild = int.tryParse(versionA.split('+').last) ?? 0;
        final bBuild = int.tryParse(versionB.split('+').last) ?? 0;
        if (aBuild > bBuild) return 1;
        if (aBuild < bBuild) return -1;
      }

      return 0;
    } catch (e) {
      debugPrint('OtaUpdateService: Version compare error: $e');
      return versionA.compareTo(versionB);
    }
  }

  /// Returns true if [remoteTag] is strictly newer than [currentVersion].
  bool isVersionNewer(String remoteTag, String currentVersion) {
    return compareVersions(remoteTag, currentVersion) > 0;
  }

  /// Checks GitHub releases API and always targets the highest available version.
  Future<UpdateInfo?> checkForUpdate() async {
    if (isChecking) return lastCheckedUpdate;
    isChecking = true;

    try {
      final currentVer = await getCurrentVersion();
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10)
        ..badCertificateCallback = ((_, __, ___) => true);

      // Fetch all releases to find the highest release tag
      final request = await client.getUrl(Uri.parse(_releasesApiUrl));
      request.headers.set('User-Agent', 'Onyx-Dialer-App');
      request.headers.set('Accept', 'application/vnd.github.v3+json');

      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final list = json.decode(body) as List<dynamic>;

        if (list.isNotEmpty) {
          // Sort releases descending by version number to pick highest
          Map<String, dynamic>? highestRelease;
          for (final item in list) {
            final rel = item as Map<String, dynamic>;
            if (highestRelease == null) {
              highestRelease = rel;
            } else {
              final tagCurr = rel['tag_name'] as String? ?? '';
              final tagBest = highestRelease['tag_name'] as String? ?? '';
              if (compareVersions(tagCurr, tagBest) > 0) {
                highestRelease = rel;
              }
            }
          }

          if (highestRelease != null) {
            final tag = highestRelease['tag_name'] as String? ?? '';
            final title = highestRelease['name'] as String? ?? tag;
            final notes = highestRelease['body'] as String? ?? 'No release notes provided.';
            final publishedStr = highestRelease['published_at'] as String?;
            final publishedAt = publishedStr != null ? DateTime.tryParse(publishedStr) : null;

            final assets = (highestRelease['assets'] as List<dynamic>?) ?? [];
            String? apkUrl;
            int apkSize = 0;

            for (final a in assets) {
              final aName = (a['name'] as String? ?? '').toLowerCase();
              if (aName.endsWith('.apk')) {
                apkUrl = a['browser_download_url'] as String?;
                apkSize = (a['size'] as int?) ?? 0;
                break;
              }
            }

            apkUrl ??= 'https://github.com/Bhanu7773-dev/Onyx-Dailer/releases/download/$tag/app-release.apk';
            final isNewer = isVersionNewer(tag, currentVer);

            final update = UpdateInfo(
              latestTag: tag,
              currentVersion: currentVer,
              releaseTitle: title,
              releaseNotes: notes,
              apkDownloadUrl: apkUrl,
              apkSize: apkSize,
              publishedAt: publishedAt,
              isNewer: isNewer,
            );

            lastCheckedUpdate = update;
            return update;
          }
        }
      } else {
        debugPrint('OtaUpdateService: GitHub returned status code ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('OtaUpdateService: Check for update failed: $e');
    } finally {
      isChecking = false;
    }
    return null;
  }

  /// Downloads APK with streaming progress to temporary file.
  Future<String?> downloadApk(
    String downloadUrl, {
    required void Function(double progress, int receivedBytes, int totalBytes) onProgress,
  }) async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15)
        ..badCertificateCallback = ((_, __, ___) => true);

      final request = await client.getUrl(Uri.parse(downloadUrl));
      request.headers.set('User-Agent', 'Onyx-Dialer-App');
      final response = await request.close();

      // Handle redirects
      if (response.isRedirect || response.statusCode == 302 || response.statusCode == 301) {
        final redirectLocation = response.headers.value(HttpHeaders.locationHeader);
        if (redirectLocation != null) {
          return await downloadApk(redirectLocation, onProgress: onProgress);
        }
      }

      if (response.statusCode != 200) {
        debugPrint('OtaUpdateService: Download failed with HTTP status ${response.statusCode}');
        return null;
      }

      final contentLength = response.contentLength;

      // Save to external storage Download folder or app cache
      File file;
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (await downloadDir.exists()) {
        file = File('${downloadDir.path}/onyx_dialer_update.apk');
      } else {
        file = File('${Directory.systemTemp.parent.path}/cache/onyx_dialer_update.apk');
      }

      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      if (await file.exists()) {
        await file.delete();
      }

      final sink = file.openWrite();
      int received = 0;

      await for (final chunk in response) {
        received += chunk.length;
        sink.add(chunk);
        if (contentLength > 0) {
          final progress = received / contentLength;
          onProgress(progress, received, contentLength);
        } else {
          onProgress(0.5, received, 0);
        }
      }

      await sink.flush();
      await sink.close();

      return file.path;
    } catch (e) {
      debugPrint('OtaUpdateService: Download error: $e');
      return null;
    }
  }

  /// Triggers native Android PackageInstaller via Intent.
  Future<bool> installApk(String filePath) async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('installApk', {'filePath': filePath});
      return res ?? false;
    } catch (e) {
      debugPrint('OtaUpdateService: Install error: $e');
      return false;
    }
  }

  /// Displays the themed Update Dialog.
  void showUpdateModal(BuildContext context, UpdateInfo updateInfo) {
    final theme = ThemeController.instance.currentTheme;
    if (theme == 'nothing') {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _NothingUpdateDialog(updateInfo: updateInfo),
      );
    } else if (theme == 'pixel') {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _PixelUpdateDialog(updateInfo: updateInfo),
      );
    } else {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _OnyxUpdateDialog(updateInfo: updateInfo),
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NOTHING UI THEMED UPDATE DIALOG
// ─────────────────────────────────────────────────────────────────────────────

class _NothingUpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;
  const _NothingUpdateDialog({required this.updateInfo});

  @override
  State<_NothingUpdateDialog> createState() => _NothingUpdateDialogState();
}

class _NothingUpdateDialogState extends State<_NothingUpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  String? _downloadedPath;
  String? _error;

  String get _nFont => ThemeController.instance.nothingFontFamily;

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _progress = 0.0;
      _error = null;
    });

    final path = await OtaUpdateService.instance.downloadApk(
      widget.updateInfo.apkDownloadUrl,
      onProgress: (p, received, total) {
        if (mounted) {
          setState(() {
            _progress = p;
          });
        }
      },
    );

    if (mounted) {
      if (path != null) {
        setState(() {
          _isDownloading = false;
          _downloadedPath = path;
          _progress = 1.0;
        });
        // Auto trigger installation
        _installApk();
      } else {
        setState(() {
          _isDownloading = false;
          _error = 'Download failed. Please check internet connection.';
        });
      }
    }
  }

  Future<void> _installApk() async {
    if (_downloadedPath == null) return;
    await OtaUpdateService.instance.installApk(_downloadedPath!);
  }

  @override
  Widget build(BuildContext context) {
    const nBg = Color(0xFF141414);
    const nCard = Color(0xFF1E1E1E);
    const nRed = Color(0xFFE5162A);
    const nWhite = Color(0xFFFFFFFF);
    const nSecondary = Color(0xFF888888);

    final info = widget.updateInfo;

    return Dialog(
      backgroundColor: nBg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF2E2E2E), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: nRed.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.system_update_rounded, color: nRed, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'OTA UPDATE AVAILABLE',
                        style: TextStyle(
                          fontFamily: _nFont,
                          color: nWhite,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${info.currentVersion}  ➔  ${info.latestTag}',
                        style: const TextStyle(
                          color: nRed,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Release Notes Card
            Container(
              constraints: const BoxConstraints(maxHeight: 160),
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: nCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2A2A2A)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (info.releaseTitle.isNotEmpty && info.releaseTitle != info.latestTag) ...[
                      Text(
                        info.releaseTitle.toUpperCase(),
                        style: TextStyle(
                          fontFamily: _nFont,
                          color: nWhite,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      info.releaseNotes,
                      style: const TextStyle(
                        color: Color(0xFFCCCCCC),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                    if (info.formattedSize.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Size: ${info.formattedSize}',
                        style: const TextStyle(color: nSecondary, fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(color: nRed, fontSize: 12),
              ),
            ],

            // Progress indicator
            if (_isDownloading) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  backgroundColor: const Color(0xFF282828),
                  valueColor: const AlwaysStoppedAnimation<Color>(nRed),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  'DOWNLOADING ${(_progress * 100).toInt()}%',
                  style: TextStyle(
                    fontFamily: _nFont,
                    color: nSecondary,
                    fontSize: 10,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Action buttons (Full-width stacked)
            Column(
              children: [
                if (_downloadedPath != null)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: nRed,
                        foregroundColor: nWhite,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.install_mobile_rounded, size: 18),
                      label: Text(
                        'INSTALL NOW',
                        style: TextStyle(
                          fontFamily: _nFont,
                          letterSpacing: 1.5,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: _installApk,
                    ),
                  )
                else if (_isDownloading)
                  const SizedBox.shrink()
                else
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: nRed,
                        foregroundColor: nWhite,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: Text(
                        'DOWNLOAD & INSTALL',
                        style: TextStyle(
                          fontFamily: _nFont,
                          letterSpacing: 1.5,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: _startDownload,
                    ),
                  ),
                if (!_isDownloading) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'CANCEL',
                        style: TextStyle(
                          fontFamily: _nFont,
                          color: nSecondary,
                          letterSpacing: 1.5,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ONYX (iOS) THEMED UPDATE DIALOG
// ─────────────────────────────────────────────────────────────────────────────

class _OnyxUpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;
  const _OnyxUpdateDialog({required this.updateInfo});

  @override
  State<_OnyxUpdateDialog> createState() => _OnyxUpdateDialogState();
}

class _OnyxUpdateDialogState extends State<_OnyxUpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  String? _downloadedPath;
  String? _error;

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _progress = 0.0;
      _error = null;
    });

    final path = await OtaUpdateService.instance.downloadApk(
      widget.updateInfo.apkDownloadUrl,
      onProgress: (p, received, total) {
        if (mounted) {
          setState(() {
            _progress = p;
          });
        }
      },
    );

    if (mounted) {
      if (path != null) {
        setState(() {
          _isDownloading = false;
          _downloadedPath = path;
          _progress = 1.0;
        });
        _installApk();
      } else {
        setState(() {
          _isDownloading = false;
          _error = 'Download failed. Please check internet connection.';
        });
      }
    }
  }

  Future<void> _installApk() async {
    if (_downloadedPath == null) return;
    await OtaUpdateService.instance.installApk(_downloadedPath!);
  }

  @override
  Widget build(BuildContext context) {
    const iosBlue = Color(0xFF007AFF);
    const iosSecondary = Color(0xFF8E8E93);

    final info = widget.updateInfo;

    return CupertinoAlertDialog(
      title: Column(
        children: [
          const Icon(CupertinoIcons.arrow_down_circle_fill, color: iosBlue, size: 36),
          const SizedBox(height: 8),
          const Text('Software Update Available'),
          const SizedBox(height: 4),
          Text(
            'Version ${info.latestTag}',
            style: const TextStyle(fontSize: 13, color: iosSecondary, fontWeight: FontWeight.normal),
          ),
        ],
      ),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          children: [
            Container(
              constraints: const BoxConstraints(maxHeight: 140),
              child: SingleChildScrollView(
                child: Text(
                  info.releaseNotes,
                  style: const TextStyle(fontSize: 13, height: 1.3),
                  textAlign: TextAlign.start,
                ),
              ),
            ),
            if (info.formattedSize.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Size: ${info.formattedSize}',
                style: const TextStyle(fontSize: 12, color: iosSecondary),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: CupertinoColors.destructiveRed, fontSize: 12),
              ),
            ],
            if (_isDownloading) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  backgroundColor: const Color(0xFF3A3A3C),
                  valueColor: const AlwaysStoppedAnimation<Color>(iosBlue),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${(_progress * 100).toInt()}%',
                style: const TextStyle(fontSize: 11, color: iosSecondary),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_isDownloading)
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
        if (_downloadedPath != null)
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: _installApk,
            child: const Text('Install Now'),
          )
        else if (_isDownloading)
          const CupertinoDialogAction(
            onPressed: null,
            child: CupertinoActivityIndicator(),
          )
        else
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: _startDownload,
            child: const Text('Download & Update'),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PIXEL MATERIAL 3 EXPRESSIVE THEMED UPDATE DIALOG
// ─────────────────────────────────────────────────────────────────────────────

class _PixelUpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;
  const _PixelUpdateDialog({required this.updateInfo});

  @override
  State<_PixelUpdateDialog> createState() => _PixelUpdateDialogState();
}

class _PixelUpdateDialogState extends State<_PixelUpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  String? _downloadedPath;
  String? _error;

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _progress = 0.0;
      _error = null;
    });

    final path = await OtaUpdateService.instance.downloadApk(
      widget.updateInfo.apkDownloadUrl,
      onProgress: (p, received, total) {
        if (mounted) {
          setState(() {
            _progress = p;
          });
        }
      },
    );

    if (mounted) {
      if (path != null) {
        setState(() {
          _isDownloading = false;
          _downloadedPath = path;
          _progress = 1.0;
        });
        _installApk();
      } else {
        setState(() {
          _isDownloading = false;
          _error = 'Download failed. Please check internet connection.';
        });
      }
    }
  }

  Future<void> _installApk() async {
    if (_downloadedPath == null) return;
    await OtaUpdateService.instance.installApk(_downloadedPath!);
  }

  @override
  Widget build(BuildContext context) {
    const kCardBg = Color(0xFF161D26);
    const kAvatarBg = Color(0xFF1E2632);
    const kBlueAccent = Color(0xFF8AB4F8);
    const kButtonText = Color(0xFF09182C);
    const kTextWhite = Color(0xFFFFFFFF);
    const kTextMuted = Color(0xFF8E9CAE);
    const kCoralRed = Color(0xFFFF7769);
    const kNotesBg = Color(0xFF0C0E12);

    final info = widget.updateInfo;

    return AlertDialog(
      backgroundColor: kCardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      titlePadding: EdgeInsets.zero,
      title: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: kBlueAccent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.system_update_rounded,
                color: kBlueAccent,
                size: 26,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Software Update',
              style: TextStyle(
                color: kTextWhite,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: kAvatarBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'v${info.latestTag}',
                style: const TextStyle(
                  color: kBlueAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Container(
            constraints: const BoxConstraints(maxHeight: 140),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kNotesBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
            ),
            child: SingleChildScrollView(
              child: Text(
                info.releaseNotes,
                style: const TextStyle(color: kTextMuted, fontSize: 13, height: 1.4),
              ),
            ),
          ),
          if (info.formattedSize.isNotEmpty) ...[
            const SizedBox(height: 10),
            Center(
              child: Text(
                'Download size: ${info.formattedSize}',
                style: const TextStyle(color: kTextMuted, fontSize: 12),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(color: kCoralRed, fontSize: 12.5),
              textAlign: TextAlign.center,
            ),
          ],
          if (_isDownloading) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                backgroundColor: kAvatarBg,
                valueColor: const AlwaysStoppedAnimation<Color>(kBlueAccent),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Downloading... ${(_progress * 100).toInt()}%',
              style: const TextStyle(color: kTextMuted, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        Row(
          children: [
            if (!_isDownloading)
              Expanded(
                child: TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Later',
                    style: TextStyle(
                      color: kTextMuted,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            if (!_isDownloading) const SizedBox(width: 8),
            Expanded(
              flex: _isDownloading ? 1 : 1,
              child: _downloadedPath != null
                  ? FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: kBlueAccent,
                        foregroundColor: kButtonText,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                      onPressed: _installApk,
                      child: const Text('Install Now', style: TextStyle(fontWeight: FontWeight.bold)),
                    )
                  : _isDownloading
                      ? Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: const Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: kBlueAccent),
                            ),
                          ),
                        )
                      : FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: kBlueAccent,
                            foregroundColor: kButtonText,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          ),
                          onPressed: _startDownload,
                          child: const Text('Update', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
            ),
          ],
        ),
      ],
    );
  }
}

