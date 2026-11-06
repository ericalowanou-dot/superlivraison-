import 'package:flutter/material.dart';

/// Couleurs reprises des maquettes.
class Palette {
  const Palette({
    required this.bg,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.line,
    required this.soft,
    required this.link,
    required this.warnBg,
    required this.warn,
  });

  final Color bg, surface, ink, muted, line, soft, link, warnBg, warn;

  static const sky = Color(0xFF87CEEB);
  static const onSky = Color(0xFF0B2F44);

  static const light = Palette(
    bg: Color(0xFFF4FBFE),
    surface: Colors.white,
    ink: Color(0xFF0B2F44),
    muted: Color(0xFF4A6B7C),
    line: Color(0xFFD3EBF5),
    soft: Color(0xFFEAF7FC),
    link: Color(0xFF0B6E99),
    warnBg: Color(0xFFFFF1DC),
    warn: Color(0xFF7A4B00),
  );

  static const dark = Palette(
    bg: Color(0xFF0A2230),
    surface: Color(0xFF12344A),
    ink: Color(0xFFEAF7FC),
    muted: Color(0xFFA9C6D6),
    line: Color(0xFF21506B),
    soft: Color(0xFF173F58),
    link: Color(0xFF87CEEB),
    warnBg: Color(0xFF4A3410),
    warn: Color(0xFFFFD699),
  );

  static Palette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

class AppTheme {
  static ThemeData get light => _build(Palette.light, Brightness.light);
  static ThemeData get dark => _build(Palette.dark, Brightness.dark);

  static ThemeData _build(Palette p, Brightness brightness) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: p.line),
    );
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: p.bg,
      colorScheme: ColorScheme.fromSeed(seedColor: Palette.sky, brightness: brightness).copyWith(
        primary: Palette.sky,
        onPrimary: Palette.onSky,
        surface: p.surface,
        onSurface: p.ink,
        secondaryContainer: Palette.sky,
        onSecondaryContainer: Palette.onSky,
      ),
      textTheme: ThemeData(brightness: brightness).textTheme.apply(bodyColor: p.ink, displayColor: p.ink),
      appBarTheme: AppBarTheme(
        backgroundColor: p.bg,
        foregroundColor: p.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(color: p.ink, fontSize: 21, fontWeight: FontWeight.w800),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(borderSide: BorderSide(color: p.link, width: 2)),
        hintStyle: TextStyle(color: p.muted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Palette.sky,
          foregroundColor: Palette.onSky,
          minimumSize: const Size.fromHeight(52),
          shape: shape,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.ink,
          backgroundColor: p.surface,
          minimumSize: const Size.fromHeight(48),
          side: BorderSide(color: p.line),
          shape: shape,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        indicatorColor: Palette.sky,
        labelTextStyle: WidgetStatePropertyAll(TextStyle(color: p.ink, fontSize: 12, fontWeight: FontWeight.w600)),
      ),
      dividerColor: p.line,
    );
  }
}
