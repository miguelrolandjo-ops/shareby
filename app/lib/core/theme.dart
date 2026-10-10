import 'package:flutter/material.dart';

/// Palette carried over from the clickable prototype.
class AppColors {
  static const ink = Color(0xFF16302B);
  static const inkSoft = Color(0xFF5B7168);
  static const inkFaint = Color(0xFF8C9C96);
  static const bg = Color(0xFFEFF4F1);
  static const surface = Color(0xFFFFFFFF);
  static const line = Color(0xFFDCE5E0);
  static const brand = Color(0xFF0F6B5C);
  static const brandDark = Color(0xFF0A4A40);
  static const brandSoft = Color(0xFFDCEBE7);
  static const greySoft = Color(0xFFE7ECE9);
  static const amberSoft = Color(0xFFFBEAD2);
  static const amberInk = Color(0xFF7A5111);
  static const lilac = Color(0xFF9A7FD1);
  static const lilacSoft = Color(0xFFEAE1F8);
}

/// Colors a user can give a folder (stored as ARGB ints).
class FolderPalette {
  static const amber = 0xFFE8A23D;
  static const sky = 0xFF4C9FE0;
  static const mint = 0xFF2FA88F;
  static const coral = 0xFFEF6F5E;
  static const lilac = 0xFF9A7FD1;
  static const grey = 0xFF9AA39D;
  static const all = [amber, sky, mint, coral, lilac, grey];

  static Color soft(Color c) => Color.alphaBlend(c.withValues(alpha: 0.2), Colors.white);
  static Color deep(Color c) => Color.lerp(c, AppColors.ink, 0.45)!;
}

const kHeadFont = 'Fredoka';
const kBodyFont = 'PlusJakartaSans';

TextStyle headStyle(double size, {FontWeight weight = FontWeight.w600, Color color = AppColors.ink}) =>
    TextStyle(fontFamily: kHeadFont, fontSize: size, fontWeight: weight, color: color, height: 1.15);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.brand).copyWith(
    primary: AppColors.brand,
    onPrimary: Colors.white,
    surface: AppColors.surface,
    onSurface: AppColors.ink,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    fontFamily: kBodyFont,
  );
  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink),
    dividerColor: AppColors.line,
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.brandSoft,
      elevation: 0,
      height: 68,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.greySoft,
      hintStyle: const TextStyle(color: AppColors.inkFaint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: rounded,
        textStyle: const TextStyle(fontFamily: kBodyFont, fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        minimumSize: const Size.fromHeight(52),
        shape: rounded,
        side: const BorderSide(color: AppColors.line),
        textStyle: const TextStyle(fontFamily: kBodyFont, fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.brand,
      foregroundColor: Colors.white,
    ),
  );
}
