import 'package:flutter/material.dart';

/// Colours taken from the web HRIS so both apps share one visual identity.
///
/// Sources (read-only reference, frontend/src/components/):
/// - Login.jsx: crimson / crimsonDark, error box
/// - Home.jsx, EmployeeHomeWidgets.jsx: `T` tokens, Today status colours
/// - ATTENDANCE/AttendanceUserState.jsx: punch status colours
/// - ATTENDANCE/AttendanceBranchSource.jsx: branch colours
class AppColors {
  const AppColors._();

  static const crimson = Color(0xFF800020);
  static const crimsonDark = Color(0xFF4B0000);

  static const accent = Color(0xFF6D2323);
  static const accentDark = Color(0xFF5A1D1D);
  static const accentFaint = Color(0x0F6D2323); // rgba(109,35,35,0.06)
  static const accentBorder = Color(0x1F6D2323); // rgba(109,35,35,0.12)
  static const text = Color(0xFF1A1A1A);
  static const muted = Color(0xFF6B6B6B);
  static const faint = Color(0xFFA0A0A0);
  static const tile = Color(0xFFF7F5F4);
  static const page = Color(0xFFFAF8F7);

  // Today card status (EmployeeHomeWidgets.jsx)
  static const complete = Color(0xFF2E7D32);
  static const clockedIn = Color(0xFF1565C0);

  // Punch status (AttendanceUserState.jsx getAttendanceColor)
  static const punchInOut = Color(0xFF4CAF50);
  static const punchBreak = Color(0xFFFF9800);
  static const punchUnknown = Color(0xFFF44336);

  // Branch (AttendanceBranchSource.jsx BRANCH_COLORS)
  static const branchManila = Color(0xFF6D2323);
  static const branchCavite = Color(0xFF1565C0);
  static const branchUnknown = Color(0xFF9E9E9E);

  // Login.jsx error box
  static const errorFg = Color(0xFF8A2020);
  static const errorBg = Color(0x0AC81E1E);
  static const errorBorder = Color(0x1FC81E1E);

  // Development notice (not from the web HRIS)
  static const noticeFg = Color(0xFF92400E);
  static const noticeBg = Color(0xFFFEF3C7);
  static const noticeBorder = Color(0x66F59E0B);
}

class AppSpacing {
  const AppSpacing._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const radius = 12.0;
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.crimson,
    primary: AppColors.crimson,
    onPrimary: Colors.white,
    surface: Colors.white,
  );

  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppSpacing.radius),
    borderSide: const BorderSide(color: Color(0x2E800020)),
  );

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.page,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.accent,
      foregroundColor: Colors.white,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        side: const BorderSide(color: Color(0x17000000)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      prefixIconColor: const Color(0x73800020),
      hintStyle: const TextStyle(color: Color(0x4D4B0000)),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: const BorderSide(color: Color(0x73800020), width: 1.5),
      ),
      errorBorder: inputBorder.copyWith(
        borderSide: const BorderSide(color: AppColors.errorFg),
      ),
      focusedErrorBorder: inputBorder.copyWith(
        borderSide: const BorderSide(color: AppColors.errorFg, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.crimson,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: AppColors.accentBorder,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? AppColors.accent
              : AppColors.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? AppColors.accent
              : AppColors.muted,
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.accentBorder,
      space: 1,
    ),
  );
}
