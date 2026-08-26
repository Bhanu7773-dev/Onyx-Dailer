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
  static const String _repoApiUrl = 'https://api.github.com/repos/Bhanu7773-dev/Onyx-Dailer/releases/latest';

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
    return '1.0.0';
  }

  /// Compares two semver strings (e.g. "1.0.1" > "1.0.0").
  /// Returns true if [remoteTag] is strictly newer than [currentVersion].
  bool isVersionNewer(String remoteTag, String currentVersion) {
    try {
      final rClean = remoteTag.replaceAll(RegExp(r'[^0-9.]'), '');
      final cClean = currentVersion.replaceAll(RegExp(r'[^0-9.]'), '');

      final rParts = rClean.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final cParts = cClean.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      while (rParts.length < 3) {
        rParts.add(0);
      }
      while (cParts.length < 3) {
        cParts.add(0);
      }

      for (int i = 0; i < 3; i++) {
        if (rParts[i] > cParts[i]) return true;
        if (rParts[i] < cParts[i]) return false;
      }
      return false;
    } catch (e) {
      debugPrint('OtaUpdateService: Version comparison failed: $e');
      return remoteTag != currentVersion;
    }
  }

  /// Checks GitHub releases API for latest release.
  Future<UpdateInfo?> checkForUpdate() async {
    if (isChecking) return lastCheckedUpdate;
    isChecking = true;

    try {
      final currentVer = await getCurrentVersion();
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10)
        ..badCertificateCallback = ((_, __, ___) => true);

      final request = await client.getUrl(Uri.parse(_repoApiUrl));
      request.headers.set('User-Agent', 'Onyx-Dialer-App');
      request.headers.set('Accept', 'application/vnd.github.v3+json');

      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = json.decode(body) as Map<String, dynamic>;

        final tag = data['tag_name'] as String? ?? '';
        final title = data['name'] as String? ?? tag;
        final notes = data['body'] as String? ?? 'No release notes provided.';
        final publishedStr = data['published_at'] as String?;
        final publishedAt = publishedStr != null ? DateTime.tryParse(publishedStr) : null;

        // Find APK asset
        final assets = (data['assets'] as List<dynamic>?) ?? [];
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

        // Fallback: if no explicit asset matching .apk found, check tag release direct link
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
          return downloadApk(redirectLocation, onProgress: onProgress);
        }
      }

      if (response.statusCode != 200) {
        debugPrint('OtaUpdateService: Download failed with HTTP status ${response.statusCode}');
        return null;
      }

      final contentLength = response.contentLength;

      // Save to external cache or system temp
      final tempDir = Directory.systemTemp;
      final file = File('${tempDir.path}/onyx_dialer_update.apk');
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

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!_isDownloading)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'CANCEL',
                      style: TextStyle(
                        fontFamily: _nFont,
                        color: nSecondary,
                        letterSpacing: 1.5,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                if (_downloadedPath != null)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: nRed,
                      foregroundColor: nWhite,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    icon: const Icon(Icons.install_mobile_rounded, size: 18),
                    label: Text(
                      'INSTALL NOW',
                      style: TextStyle(fontFamily: _nFont, letterSpacing: 1.2, fontSize: 12),
                    ),
                    onPressed: _installApk,
                  )
                else if (_isDownloading)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(color: nRed, strokeWidth: 2),
                  )
                else
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: nRed,
                      foregroundColor: nWhite,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: Text(
                      'DOWNLOAD & INSTALL',
                      style: TextStyle(fontFamily: _nFont, letterSpacing: 1.2, fontSize: 12),
                    ),
                    onPressed: _startDownload,
                  ),
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
