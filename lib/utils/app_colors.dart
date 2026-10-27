import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color background = Color(0xFFE9F1FA);

  static const Color primary = Color(0xFF00ABE4);

  static const Color offline = Color(0xFF9E9E9E);

  static const Color white = Colors.white;

  static const Color textPrimary = Color(0xFF1F2937);

  static const Color textSecondary = Color(0xFF6B7280);

  static const Color success = Color(0xFF4CAF50);

  static const Color warning = Color(0xFFFF9800);

  static const Color error = Color(0xFFF44336);

  static const Color divider = Color(0xFFD6E3F0);

  /// Alarm priority colours, following IEC 60601-1-8 convention:
  /// red for high, amber for medium, cyan for low. Kept deliberately
  /// separate from [error]/[warning] — those signal app/connectivity
  /// problems, these signal patient-safety conditions, and conflating
  /// the two would make a network hiccup look like a clinical alarm.
  static const Color alarmHigh = Color(0xFFD32F2F);

  static const Color alarmMedium = Color(0xFFFFA000);

  static const Color alarmLow = Color(0xFF0097A7);
}