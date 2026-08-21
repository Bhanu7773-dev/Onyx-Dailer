import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wavedialer/themes/nothing/settings_screen.dart';
import 'package:wavedialer/logic/profile_service.dart';

const _nBg = Color(0xFF141414);
const _nCard = Color(0xFF1E1E1E);
const _nLabel = Color(0xFFFFFFFF);
const _nSecondary = Color(0xFF888888);
const _nDivider = Color(0xFF2A2A2A);
const _nRed = Color(0xFFE5162A);

class NothingDialogs {
  /// Consistent Nothing UI Confirmation Dialog
  static Future<bool?> showConfirmDialog({
    required BuildContext context,
    required String title,
    required String message,
    String confirmLabel = 'CONFIRM',
    String cancelLabel = 'CANCEL',
    bool isDestructive = false,
  }) {
    HapticFeedback.mediumImpact();
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.75),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, anim1, anim2) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: _nBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _nDivider, width: 1.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.toUpperCase(),
                    style: const TextStyle(
                      color: _nLabel,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      fontFamily: 'NothingFont',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    style: const TextStyle(
                      color: _nSecondary,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: TextButton.styleFrom(
                          foregroundColor: _nSecondary,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        child: Text(
                          cancelLabel,
                          style: const TextStyle(
                            fontFamily: 'NothingFont',
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDestructive ? _nRed : const Color(0xFF2C2C2C),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        ),
                        child: Text(
                          confirmLabel,
                          style: const TextStyle(
                            fontFamily: 'NothingFont',
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Profile Avatar Menu (Settings, About, Change Avatar)
  static void showProfileMenu(BuildContext context, {VoidCallback? onAvatarChanged}) {
    HapticFeedback.mediumImpact();
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: CupertinoActionSheet(
          title: const Text(
            'ONYX & NOTHING DIALER',
            style: TextStyle(
              color: _nLabel,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
              fontSize: 16,
              fontFamily: 'NothingFont',
            ),
          ),
          message: const Text(
            'Quick access to app settings and info',
            style: TextStyle(color: _nSecondary, fontSize: 13),
          ),
          actions: [
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.settings_outlined, color: _nLabel, size: 20),
                  SizedBox(width: 10),
                  Text('Settings', style: TextStyle(color: _nLabel, fontFamily: 'NothingFont', letterSpacing: 1)),
                ],
              ),
            ),
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                showAboutDialog(context);
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.info_outline_rounded, color: _nLabel, size: 20),
                  SizedBox(width: 10),
                  Text('About Onyx Dialer', style: TextStyle(color: _nLabel, fontFamily: 'NothingFont', letterSpacing: 1)),
                ],
              ),
            ),
            CupertinoActionSheetAction(
              onPressed: () async {
                Navigator.pop(ctx);
                final pickedBytes = await ProfileService.pickImageFromGallery();
                if (pickedBytes != null) {
                  onAvatarChanged?.call();
                }
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.photo_library_outlined, color: _nLabel, size: 20),
                  SizedBox(width: 10),
                  Text('Choose from Gallery', style: TextStyle(color: _nLabel, fontFamily: 'NothingFont', letterSpacing: 1)),
                ],
              ),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: _nSecondary, fontFamily: 'NothingFont')),
          ),
        ),
      ),
    );
  }

  /// Nothing UI About Dialog
  static void showAboutDialog(BuildContext context) {
    HapticFeedback.lightImpact();
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.75),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, anim1, anim2) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.86,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: _nBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _nDivider, width: 1.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _nCard,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _nDivider, width: 1),
                        ),
                        child: const Icon(Icons.call, color: _nRed, size: 24),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ONYX DIALER',
                              style: TextStyle(
                                color: _nLabel,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                                fontFamily: 'NothingFont',
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Version 1.0.0 (Nothing UI)',
                              style: TextStyle(color: _nSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'A modern phone dialer with native root / Shizuku two-sided call recording and customizable themes.',
                    style: TextStyle(color: _nSecondary, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: _nDivider, height: 1),
                  const SizedBox(height: 16),
                  const Text(
                    'DEVELOPER',
                    style: TextStyle(
                      color: _nSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      fontFamily: 'NothingFont',
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Billu Builder',
                    style: TextStyle(color: _nLabel, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => launchUrl(
                        Uri.parse('https://t.me/fitx_updates'),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.send, size: 16),
                      label: const Text('JOIN TELEGRAM CHANNEL', style: TextStyle(fontFamily: 'NothingFont', letterSpacing: 1.2, fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0088CC),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('CLOSE', style: TextStyle(color: _nSecondary, fontFamily: 'NothingFont', letterSpacing: 1.5)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Nothing UI Create / Add Contact Dialog
  static Future<void> showNewContact(BuildContext context, {VoidCallback? onDone}) async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.75),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, anim1, anim2) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.88,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: _nBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _nDivider, width: 1.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'NEW CONTACT',
                    style: TextStyle(
                      color: _nLabel,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      fontFamily: 'NothingFont',
                    ),
                  ),
                  const SizedBox(height: 18),
                  _buildInputField('NAME', nameCtrl, TextInputType.name),
                  const SizedBox(height: 14),
                  _buildInputField('PHONE NUMBER', phoneCtrl, TextInputType.phone),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('CANCEL', style: TextStyle(color: _nSecondary, fontFamily: 'NothingFont', letterSpacing: 1.5)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          if (nameCtrl.text.trim().isNotEmpty && phoneCtrl.text.trim().isNotEmpty) {
                            Navigator.pop(ctx, true);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _nRed,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        ),
                        child: const Text('SAVE', style: TextStyle(fontFamily: 'NothingFont', letterSpacing: 1.5, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (result == true) {
      try {
        final newContact = Contact(
          name: Name(first: nameCtrl.text.trim()),
          phones: [Phone(number: phoneCtrl.text.trim())],
        );
        await FlutterContacts.create(newContact);
        onDone?.call();
      } catch (e) {
        debugPrint('Failed to save contact: $e');
      }
    }
  }

  /// Nothing UI Edit Contact Dialog
  static Future<void> showEditContact(BuildContext context, Contact contact, {VoidCallback? onDone}) async {
    if (contact.id == null) return;
    final fullContact = await FlutterContacts.get(
      contact.id!,
      properties: {ContactProperty.name, ContactProperty.phone},
    );
    if (fullContact == null) return;

    final nameCtrl = TextEditingController(text: fullContact.name?.first ?? '');
    final initialPhone = fullContact.phones.isNotEmpty ? fullContact.phones.first.number : '';
    final phoneCtrl = TextEditingController(text: initialPhone);

    final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.75),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, anim1, anim2) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.88,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: _nBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _nDivider, width: 1.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'EDIT CONTACT',
                    style: TextStyle(
                      color: _nLabel,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      fontFamily: 'NothingFont',
                    ),
                  ),
                  const SizedBox(height: 18),
                  _buildInputField('NAME', nameCtrl, TextInputType.name),
                  const SizedBox(height: 14),
                  _buildInputField('PHONE NUMBER', phoneCtrl, TextInputType.phone),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('CANCEL', style: TextStyle(color: _nSecondary, fontFamily: 'NothingFont', letterSpacing: 1.5)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _nRed,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        ),
                        child: const Text('SAVE', style: TextStyle(fontFamily: 'NothingFont', letterSpacing: 1.5, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (result == true) {
      try {
        final updatedContact = fullContact.copyWith(
          name: fullContact.name?.copyWith(first: nameCtrl.text.trim()) ?? Name(first: nameCtrl.text.trim()),
          phones: [Phone(number: phoneCtrl.text.trim())],
        );
        await FlutterContacts.update(updatedContact);
        onDone?.call();
      } catch (e) {
        debugPrint('Failed to update contact: $e');
      }
    }
  }

  static Widget _buildInputField(String label, TextEditingController controller, TextInputType type) {
    return Container(
      decoration: BoxDecoration(
        color: _nCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _nDivider, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: TextField(
        controller: controller,
        keyboardType: type,
        cursorColor: _nRed,
        style: const TextStyle(color: _nLabel, fontSize: 15, fontFamily: 'NothingFont'),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: _nSecondary, fontSize: 12, letterSpacing: 1.5, fontFamily: 'NothingFont'),
          border: InputBorder.none,
          isDense: true,
        ),
      ),
    );
  }
}
