import 'package:flutter/material.dart';

/// Cross-SDK compatibility helpers supporting both Flutter 3.19.6 (Dart 3.3,
/// required for Windows 7 SP1 x64 compatibility) and newer Flutter 3.x SDKs
/// without deprecation warnings or compile errors.
Color colorWithOpacity(Color color, double opacity) {
  final alpha = (opacity.clamp(0.0, 1.0) * 255).round();
  return color.withAlpha(alpha);
}

/// Equivalent to Material 3 `ColorScheme.surfaceContainerLow` compatible with
/// Flutter 3.19.x as well as newer SDKs.
Color surfaceContainerLowCompat(ColorScheme scheme) {
  return scheme.brightness == Brightness.light
      ? Color.alphaBlend(scheme.primary.withAlpha(8), scheme.surface)
      : Color.alphaBlend(Colors.white.withAlpha(13), scheme.surface);
}

/// Equivalent to Material 3 `ColorScheme.surfaceContainerHighest` compatible with
/// Flutter 3.19.x as well as newer SDKs.
Color surfaceContainerHighestCompat(ColorScheme scheme) {
  return scheme.brightness == Brightness.light
      ? Color.alphaBlend(scheme.onSurface.withAlpha(20), scheme.surface)
      : Color.alphaBlend(Colors.white.withAlpha(30), scheme.surface);
}

/// Default rounded outlined card shape shared across screens.
RoundedRectangleBorder appCardShape(
  ColorScheme scheme, {
  Color? borderColor,
  double borderWidth = 1,
}) {
  return RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(18),
    side: BorderSide(
      color: borderColor ?? colorWithOpacity(scheme.outlineVariant, 0.55),
      width: borderWidth,
    ),
  );
}

/// Styled flat outlined card that avoids Flutter 3.19 (`CardTheme`) vs
/// Flutter 3.32+ (`CardThemeData`) `ThemeData.cardTheme` API divergence.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.margin = EdgeInsets.zero,
    this.shape,
  });

  final Widget child;
  final EdgeInsetsGeometry margin;
  final ShapeBorder? shape;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = scheme.brightness == Brightness.light;
    return Card(
      elevation: 0,
      color: isLight ? Colors.white : surfaceContainerLowCompat(scheme),
      margin: margin,
      shape: shape ?? appCardShape(scheme),
      child: child,
    );
  }
}
