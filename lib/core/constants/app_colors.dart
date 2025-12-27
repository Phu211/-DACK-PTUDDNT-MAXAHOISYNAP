import 'package:flutter/material.dart';

class AppColors {
  // Primary brand color - #25F4EE (Turquoise/Cyan) - Màu chủ đạo
  static const Color primary = Color(0xFF25F4EE);
  static const Color primaryDark = Color(0xFF1DD4C4);
  static const Color primaryLight = Color(0xFF4DF5F0);
  static const Color primaryLighter = Color(0xFF7DF6F2);

  // Gradient colors based on primary
  static const Color primaryCyan = Color(0xFF25F4EE);
  static const Color primaryBlue = Color(0xFF3B82F6);
  static const Color primaryPurple = Color(0xFF9333EA);
  static const Color primaryMagenta = Color(0xFF7B2CBF);

  // Accent colors với primary
  static const Color accentPrimary = Color(0xFF25F4EE);
  static const Color accentPrimaryDark = Color(0xFF1DD4C4);

  // Gradient combinations with primary color
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryCyan, primaryBlue, primaryPurple],
  );

  static const LinearGradient primaryGradientVertical = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [primaryCyan, primaryBlue, primaryPurple],
  );

  static const LinearGradient primaryGradientHorizontal = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [primaryCyan, primaryBlue, primaryPurple],
  );

  // Simple gradient with primary color
  static const LinearGradient primarySimpleGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryDark],
  );

  // Background colors - Changed to white
  static const Color backgroundDark = Colors.white;
  static const Color backgroundBlack = Colors.white;
  static const Color surfaceDark = Colors.white;
  static const Color surfaceGrey = Colors.white;

  // Text colors - Changed to black
  static const Color textPrimary = Colors.black;
  static const Color textSecondary = Colors.black87;
  static const Color textTertiary = Colors.black54;

  // Border colors - Changed to light grey
  static const Color borderDark = Color(0xFFE0E0E0);
  static const Color borderLight = Color(0xFFD0D0D0);

  // Accent colors
  static const Color accentBlue = Color(0xFF1877F2);
  static const Color accentGreen = Color(0xFF42B72A);
  static const Color accentRed = Color(0xFFF02849);
  static const Color accentYellow = Color(0xFFF7B928);

  // Interactive colors với primary
  static const Color linkColor = Color(0xFF25F4EE);
  static const Color hoverColor = Color(0xFF4DF5F0);
  static const Color activeColor = Color(0xFF1DD4C4);

  // Status colors
  static const Color success = Color(0xFF42B72A);
  static const Color error = Color(0xFFF02849);
  static const Color warning = Color(0xFFF7B928);
  static const Color info = Color(0xFF1877F2);

  // Helper method to get gradient colors as list
  static List<Color> get gradientColors => [
    primaryCyan,
    primaryBlue,
    primaryPurple,
  ];

  // Helper method to create custom gradient
  static LinearGradient createGradient({
    AlignmentGeometry begin = Alignment.topLeft,
    AlignmentGeometry end = Alignment.bottomRight,
    List<Color>? colors,
  }) {
    return LinearGradient(
      begin: begin,
      end: end,
      colors: colors ?? gradientColors,
    );
  }
}
