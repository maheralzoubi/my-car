import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../constants/constants.dart';
import '../theme/app_palette.dart';

/// The app's toggle: blue track when on, neutral track when off, white knob.
/// Announces as a switch with its on/off state.
///
/// Pass `onChanged: null` to disable it.
class AppSwitch extends StatelessWidget {
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
    this.dimWhenDisabled = true,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  /// What the switch controls, for screen readers. Not needed when it sits
  /// inside a [SettingsTile], which labels it.
  final String? semanticLabel;

  /// Fade the switch when disabled. [SettingsTile] turns this off because it
  /// fades the whole row instead (avoids a double fade).
  final bool dimWhenDisabled;

  static const Duration _duration = Duration(milliseconds: 180);

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    final enabled = onChanged != null;

    return Semantics(
      label: semanticLabel,
      toggled: value,
      enabled: enabled,
      onTap: enabled ? () => onChanged!(!value) : null,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged!(!value) : null,
        child: Opacity(
          opacity: enabled || !dimWhenDisabled ? 1 : 0.4,
          child: AnimatedContainer(
            duration: _duration,
            width: 48.r,
            height: 28.r,
            padding: EdgeInsets.all(3.r),
            decoration: BoxDecoration(
              color: value ? p.primaryButton : p.track,
              borderRadius: BorderRadius.circular(AppSizes.radiusFull),
            ),
            child: AnimatedAlign(
              duration: _duration,
              curve: Curves.easeOut,
              alignment: value
                  ? AlignmentDirectional.centerEnd
                  : AlignmentDirectional.centerStart,
              child: AspectRatio(
                aspectRatio: 1,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Color(0x33101828), blurRadius: 3),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
