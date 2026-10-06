import "package:flutter/material.dart";

const brandSeed = Color(0xFF0F6B4D);

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: brandSeed, brightness: brightness);
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: brightness);
  final radius = BorderRadius.circular(16);
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurface),
    ),
    textTheme: base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
      titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.primary, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.error)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide(color: scheme.outlineVariant),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.5), space: 1),
  );
}

/// Content never stretches wider than this on desktop browsers.
const maxContentWidth = 720.0;

class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: maxContentWidth), child: child),
    );
  }
}

IconData activityIcon(String activity) => switch (activity) {
      "hiking" => Icons.hiking,
      "sightseeing" => Icons.photo_camera_outlined,
      "beach" => Icons.beach_access_outlined,
      "camping" => Icons.cabin_outlined,
      "business" => Icons.work_outline,
      "temple" => Icons.temple_buddhist_outlined,
      _ => Icons.explore_outlined,
    };

String titleCase(String value) =>
    value.isEmpty ? value : value[0].toUpperCase() + value.substring(1).replaceAll("_", " ");

IconData categoryIcon(String category) => switch (category) {
      "clothing" => Icons.checkroom_outlined,
      "footwear" => Icons.directions_walk,
      "personal" => Icons.soap_outlined,
      "health" => Icons.medical_services_outlined,
      "electronics" => Icons.power_outlined,
      "documents" => Icons.badge_outlined,
      "food" => Icons.lunch_dining_outlined,
      "activity" => Icons.backpack_outlined,
      _ => Icons.inventory_2_outlined,
    };

IconData weatherIcon(List<String> tags) {
  if (tags.contains("rain")) return Icons.umbrella_outlined;
  if (tags.contains("cold")) return Icons.ac_unit;
  if (tags.contains("hot")) return Icons.wb_sunny_outlined;
  return Icons.wb_cloudy_outlined;
}

/// A soft gradient per destination so trip cards are easy to tell apart.
LinearGradient destinationGradient(String name, ColorScheme scheme) {
  const hues = [152.0, 196.0, 222.0, 28.0, 268.0, 340.0, 172.0];
  final hue = hues[name.toLowerCase().codeUnits.fold<int>(0, (a, b) => a + b) % hues.length];
  final dark = scheme.brightness == Brightness.dark;
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      HSLColor.fromAHSL(1, hue, 0.55, dark ? 0.30 : 0.42).toColor(),
      HSLColor.fromAHSL(1, (hue + 30) % 360, 0.60, dark ? 0.22 : 0.32).toColor(),
    ],
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
