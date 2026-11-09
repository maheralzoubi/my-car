import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../../core/app_services.dart';
import '../../../../../core/constants/app_colors.dart';

/// Up to two initials of [name], or '?' when there is no name.
String profileInitials(String? name) {
  final parts = (name ?? '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  return parts.take(2).map((p) => p.characters.first.toUpperCase()).join();
}

/// Contents of a circular avatar: the on-device profile photo when one was
/// picked, otherwise the signed-in user's initials. The caller supplies the
/// circle (size, gradient, shadow).
class ProfileAvatarContent extends StatelessWidget {
  const ProfileAvatarContent({super.key, required this.fontSize, this.name});

  final double fontSize;

  /// Name to take initials from; defaults to the session user.
  final String? name;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Uint8List?>(
      valueListenable: AppServices.instance.profilePhoto.photo,
      builder: (context, bytes, _) {
        if (bytes != null) {
          return ClipOval(
            child: Image.memory(
              bytes,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => _initials(),
            ),
          );
        }
        return _initials();
      },
    );
  }

  Widget _initials() => Center(
        child: Text(
          profileInitials(name ?? AppServices.instance.session.name),
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            color: AppColors.white,
          ),
        ),
      );
}
