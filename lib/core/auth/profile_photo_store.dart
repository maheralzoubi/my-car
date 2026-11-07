import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The signed-in user's profile picture, kept on this device only.
///
/// The backend has no avatar-upload endpoint, so a picked photo is stored
/// locally (base64 in SharedPreferences — the picker is asked for a small,
/// compressed image) and cleared on logout. [photo] notifies every avatar
/// on screen when it changes.
class ProfilePhotoStore {
  ProfilePhotoStore();

  static const _key = 'profile_photo_b64';

  final ValueNotifier<Uint8List?> photo = ValueNotifier<Uint8List?>(null);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      photo.value = raw == null ? null : base64Decode(raw);
    } catch (_) {
      // Missing plugin / corrupt value: fall back to the initials avatar.
      photo.value = null;
    }
  }

  /// Shows [bytes] immediately; returns false if it could not be persisted
  /// (it then lasts until the app restarts).
  Future<bool> save(Uint8List bytes) async {
    photo.value = bytes;
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(_key, base64Encode(bytes));
    } catch (_) {
      return false;
    }
  }

  Future<void> clear() async {
    photo.value = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {
      // Nothing persisted to remove.
    }
  }
}
