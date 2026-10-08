import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class AppColors {
  /// Matches the App Store icon background.
  static const navy = Color(0xFF1F3A57);
  static const navyDeep = Color(0xFF152A40);
  static const amber = Color(0xFFF5A300);
  static const amberSoft = Color(0xFFFFF1CC);
  static const paper = Color(0xFFF4F2EC);
  static const ink = Color(0xFF1B1F24);
  static const card = Color(0xFFFFFFFF);
  static const line = Color(0xFFE2DED4);
  static const muted = Color(0xFF5B6470);
  static const danger = Color(0xFFB3261E);
  static const sunday = Color(0xFFC0392B);
  static const saturday = Color(0xFF2E6DB4);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.paper,
    colorScheme: const ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.navy,
      onPrimary: Colors.white,
      secondary: AppColors.amber,
      onSecondary: AppColors.ink,
      error: AppColors.danger,
      onError: Colors.white,
      surface: AppColors.card,
      onSurface: AppColors.ink,
    ),
  );

  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.navy,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.card,
      indicatorColor: AppColors.amberSoft,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          color: selected ? AppColors.navy : AppColors.muted,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? AppColors.navy : AppColors.muted,
        );
      }),
    ),
    dividerColor: AppColors.line,
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.amber,
      foregroundColor: AppColors.ink,
      extendedTextStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFCBD3DC),
        disabledForegroundColor: const Color(0xFF5B6470),
        minimumSize: const Size(64, 52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.navy,
        minimumSize: const Size(64, 52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        side: const BorderSide(color: AppColors.navy, width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.navy,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      labelStyle: const TextStyle(color: AppColors.muted),
      hintStyle: const TextStyle(color: Color(0xFF8A9099)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.navy, width: 1.6),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      contentTextStyle: TextStyle(color: Colors.white, fontSize: 15),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.standard,
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return AppColors.ink;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.navy;
          return Colors.white;
        }),
        side: const WidgetStatePropertyAll(BorderSide(color: AppColors.line)),
      ),
    ),
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    ),
  );
}
