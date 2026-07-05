/// 文件输入：应用色板、字体、组件主题配置
/// 文件职责：统一生成主题对象，提供贴合设计稿的 Material 主题配置
/// 文件对外接口：buildAppTheme
import 'package:flutter/material.dart';

ThemeData buildAppTheme() {
  const scaffoldColor = Color(0xFFF5F4F1);
  const surfaceColor = Colors.white;
  const primaryColor = Color(0xFF3D8A5A);
  const primarySoftColor = Color(0xFFE8F3EB);
  const textColor = Color(0xFF1A1918);
  const mutedTextColor = Color(0xFF8B867C);
  const dividerColor = Color(0xFFE7E3DA);

  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.light,
      ).copyWith(
        primary: primaryColor,
        onPrimary: Colors.white,
        secondary: primarySoftColor,
        onSecondary: textColor,
        surface: surfaceColor,
        onSurface: textColor,
        outline: dividerColor,
        error: const Color(0xFFB64848),
        onError: Colors.white,
      );

  final baseTheme = ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: scaffoldColor,
  );

  final textTheme = baseTheme.textTheme.copyWith(
    headlineMedium: const TextStyle(
      color: textColor,
      fontSize: 30,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.8,
    ),
    titleLarge: const TextStyle(
      color: textColor,
      fontSize: 22,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
    ),
    titleMedium: const TextStyle(
      color: textColor,
      fontSize: 18,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
    ),
    bodyLarge: const TextStyle(
      color: textColor,
      fontSize: 15,
      fontWeight: FontWeight.w500,
    ),
    bodyMedium: const TextStyle(
      color: textColor,
      fontSize: 14,
      fontWeight: FontWeight.w500,
    ),
    bodySmall: const TextStyle(
      color: mutedTextColor,
      fontSize: 12,
      fontWeight: FontWeight.w500,
    ),
  );

  return baseTheme.copyWith(
    textTheme: textTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: scaffoldColor,
      foregroundColor: textColor,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: textColor,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
    ),
    cardTheme: CardThemeData(
      color: surfaceColor,
      elevation: 0,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceColor,
      hintStyle: const TextStyle(
        color: mutedTextColor,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      labelStyle: const TextStyle(
        color: mutedTextColor,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      prefixIconColor: mutedTextColor,
      suffixIconColor: mutedTextColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: primaryColor, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFB64848)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFB64848), width: 1.4),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        disabledBackgroundColor: primaryColor.withValues(alpha: 0.45),
        disabledForegroundColor: Colors.white.withValues(alpha: 0.9),
        minimumSize: const Size.fromHeight(56),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
      elevation: 0,
      shape: CircleBorder(),
    ),
    dividerColor: dividerColor,
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: textColor,
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.zero,
      iconColor: textColor,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: primaryColor,
      linearTrackColor: Color(0xFFE7E3DA),
      circularTrackColor: Color(0xFFE7E3DA),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      side: const BorderSide(color: mutedTextColor, width: 1.2),
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return primaryColor;
        }
        return Colors.transparent;
      }),
    ),
  );
}
