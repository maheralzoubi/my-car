import 'package:flutter/material.dart';

import 'app_button.dart';

/// Former primary CTA. The redesign has no gradients: this now renders a
/// solid primary [AppButton]. Use [AppButton] directly in new code.
@Deprecated('Use AppButton')
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;

  @override
  Widget build(BuildContext context) => AppButton(
    label: label,
    onPressed: onPressed,
    icon: icon,
    isLoading: isLoading,
  );
}
