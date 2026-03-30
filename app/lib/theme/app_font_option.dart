import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum AppFontOption {
  appDefault(
    storageValue: 'default',
    label: 'Default',
  ),
  inter(
    storageValue: 'inter',
    label: 'Inter',
  ),
  montserrat(
    storageValue: 'montserrat',
    label: 'Montserrat',
  ),
  poppins(
    storageValue: 'poppins',
    label: 'Poppins',
  ),
  roboto(
    storageValue: 'roboto',
    label: 'Roboto',
  );

  const AppFontOption({
    required this.storageValue,
    required this.label,
  });

  final String storageValue;
  final String label;

  static AppFontOption fromStorage(String? value) {
    for (final option in AppFontOption.values) {
      if (option.storageValue == value) {
        return option;
      }
    }
    return AppFontOption.appDefault;
  }
}

class AppFontTheme {
  AppFontTheme._();

  static ThemeData applyLegacy(ThemeData base, AppFontOption option) {
    switch (option) {
      case AppFontOption.appDefault:
        return base;
      case AppFontOption.inter:
        return _applyInter(base);
      case AppFontOption.montserrat:
        return _applyMontserrat(base);
      case AppFontOption.poppins:
        return _applyPoppins(base);
      case AppFontOption.roboto:
        return _applyRoboto(base);
    }
  }

  static ThemeData applyRedesign(ThemeData base, AppFontOption option) {
    switch (option) {
      case AppFontOption.appDefault:
        return _applySpaceGrotesk(base);
      case AppFontOption.inter:
        return _applyInter(base);
      case AppFontOption.montserrat:
        return _applyMontserrat(base);
      case AppFontOption.poppins:
        return _applyPoppins(base);
      case AppFontOption.roboto:
        return _applyRoboto(base);
    }
  }

  static TextStyle? previewTextStyle(
    TextStyle? base,
    AppFontOption option, {
    required bool redesign,
  }) {
    if (base == null) return null;

    switch (option) {
      case AppFontOption.appDefault:
        return redesign ? GoogleFonts.spaceGrotesk(textStyle: base) : base;
      case AppFontOption.inter:
        return GoogleFonts.inter(textStyle: base);
      case AppFontOption.montserrat:
        return GoogleFonts.montserrat(textStyle: base);
      case AppFontOption.poppins:
        return GoogleFonts.poppins(textStyle: base);
      case AppFontOption.roboto:
        return GoogleFonts.roboto(textStyle: base);
    }
  }

  static ThemeData _applyInter(ThemeData base) {
    return base.copyWith(
      textTheme: GoogleFonts.interTextTheme(base.textTheme),
      primaryTextTheme: GoogleFonts.interTextTheme(base.primaryTextTheme),
    );
  }

  static ThemeData _applyMontserrat(ThemeData base) {
    return base.copyWith(
      textTheme: GoogleFonts.montserratTextTheme(base.textTheme),
      primaryTextTheme: GoogleFonts.montserratTextTheme(base.primaryTextTheme),
    );
  }

  static ThemeData _applyPoppins(ThemeData base) {
    return base.copyWith(
      textTheme: GoogleFonts.poppinsTextTheme(base.textTheme),
      primaryTextTheme: GoogleFonts.poppinsTextTheme(base.primaryTextTheme),
    );
  }

  static ThemeData _applyRoboto(ThemeData base) {
    return base.copyWith(
      textTheme: GoogleFonts.robotoTextTheme(base.textTheme),
      primaryTextTheme: GoogleFonts.robotoTextTheme(base.primaryTextTheme),
    );
  }

  static ThemeData _applySpaceGrotesk(ThemeData base) {
    return base.copyWith(
      textTheme: GoogleFonts.spaceGroteskTextTheme(base.textTheme),
      primaryTextTheme:
          GoogleFonts.spaceGroteskTextTheme(base.primaryTextTheme),
    );
  }
}
