import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileService {
  static Uint8List? cachedAvatar;
  static const MethodChannel _channel = MethodChannel('dark.onyx.com/telecom_commands');
  static const String _prefKey = 'custom_profile_avatar_base64';

  static Future<Uint8List?> getProfileAvatar() async {
    if (cachedAvatar != null) return cachedAvatar;

    // 0. Check persistent cache in SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      final base64Str = prefs.getString(_prefKey);
      if (base64Str != null && base64Str.isNotEmpty) {
        cachedAvatar = base64Decode(base64Str);
        return cachedAvatar;
      }
    } catch (_) {}

    // 1. Try Native Android ContactsContract.Profile query
    try {
      final nativeBytes = await _channel.invokeMethod<Uint8List>('getUserProfileAvatar');
      if (nativeBytes != null && nativeBytes.isNotEmpty) {
        cachedAvatar = nativeBytes;
        await _saveToPrefs(nativeBytes);
        return cachedAvatar;
      }
    } catch (e) {
      debugPrint('ProfileService native query: $e');
    }

    // 2. Try flutter_contacts profile API
    try {
      final profile = await FlutterContacts.profile.get(properties: {
        ContactProperty.photoThumbnail,
        ContactProperty.photoFullRes,
      });
      if (profile?.photo?.thumbnail != null) {
        cachedAvatar = profile!.photo!.thumbnail;
        await _saveToPrefs(cachedAvatar!);
        return cachedAvatar;
      }
      if (profile?.photo?.fullSize != null) {
        cachedAvatar = profile!.photo!.fullSize;
        await _saveToPrefs(cachedAvatar!);
        return cachedAvatar;
      }
    } catch (e) {
      debugPrint('ProfileService plugin query: $e');
    }

    // 3. Look for contact named "Me", "Myself", "Owner" or first starred contact with photo
    try {
      final contacts = await FlutterContacts.getAll(
        properties: {ContactProperty.name, ContactProperty.photoThumbnail},
      );
      for (final c in contacts) {
        final name = (c.displayName ?? '').toLowerCase();
        if ((name.startsWith('me') || name.startsWith('myself') || name.startsWith('owner')) &&
            c.photo?.thumbnail != null) {
          cachedAvatar = c.photo!.thumbnail;
          await _saveToPrefs(cachedAvatar!);
          return cachedAvatar;
        }
      }
    } catch (e) {
      debugPrint('ProfileService contact scan: $e');
    }

    return null;
  }

  static Future<Uint8List?> pickImageFromGallery() async {
    try {
      final bytes = await _channel.invokeMethod<Uint8List>('pickGalleryImage');
      if (bytes != null && bytes.isNotEmpty) {
        await setCustomAvatar(bytes);
        return bytes;
      }
    } catch (e) {
      debugPrint('ProfileService gallery pick error: $e');
    }
    return null;
  }

  static Future<void> setCustomAvatar(Uint8List bytes) async {
    cachedAvatar = bytes;
    await _saveToPrefs(bytes);
  }

  static Future<void> _saveToPrefs(Uint8List bytes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, base64Encode(bytes));
    } catch (_) {}
  }
}
