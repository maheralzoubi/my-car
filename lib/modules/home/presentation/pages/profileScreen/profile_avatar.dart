import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../../core/app_services.dart';
import '../../../../../core/core.dart';

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

/// The user's avatar: a soft-accent circle of [size] holding the on-device
/// profile photo, or the user's initials in the accent color.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.size, this.name});

  /// Diameter, already scaled by the caller (e.g. `64.r`).
  final double size;

  /// Name to take initials from; defaults to the session user.
  final String? name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.colors.primarySoft,
        shape: BoxShape.circle,
      ),
      // Initials take ~36% of the circle, like the mockup's "YN".
      child: ProfileAvatarContent(fontSize: size * 0.36, name: name),
    );
  }
}

/// Contents of a circular avatar: the on-device profile photo when one was
/// picked, otherwise the signed-in user's initials. The caller supplies the
/// circle; [ProfileAvatar] is the standard one.
class ProfileAvatarContent extends StatelessWidget {
  const ProfileAvatarContent({
    super.key,
    required this.fontSize,
    this.name,
    this.color,
  });

  final double fontSize;

  /// Name to take initials from; defaults to the session user.
  final String? name;

  /// Initials color; defaults to the accent (for a `primarySoft` circle).
  final Color? color;

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
              errorBuilder: (_, _, _) => _initials(context),
            ),
          );
        }
        return _initials(context);
      },
    );
  }

  Widget _initials(BuildContext context) => Center(
    child: Text(
      profileInitials(name ?? AppServices.instance.session.name),
      // Size is set by the caller to fit its circle.
      style: AppTextStyles.headline.copyWith(
        fontSize: fontSize,
        color: color ?? context.colors.primary,
      ),
    ),
  );
}
