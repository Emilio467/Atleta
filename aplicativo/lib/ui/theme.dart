import 'package:flutter/material.dart';

abstract final class Palette {
  static const background = Color(0xFF020003);
  static const surface = Color(0xFF1E1C21);
  static const raised = Color(0xFF343136);
  static const border = Color(0xFF353539);
  static const text = Color(0xFFF5F6F3);
  static const muted = Color(0xFFA1ABA0);
  static const axis = Color(0xFF888C87);
  static const line = Color(0xFF9C9F9D);
  static const green = Color(0xFF73C75A);
  static const lime = Color(0xFF79EA38);
  static const dashboard = LinearGradient(
    colors: [
      Color(0xFF12370E),
      Color(0xFF0B230C),
      Color(0xFF070D08),
      Color(0xFF080608),
    ],
    stops: [0, .31, .67, 1],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
  static const orange = Color(0xFFEF994D);
  static const pink = Color(0xFFEF6098);
  static const navigationGlass = LinearGradient(
    colors: [Color(0xBB29272A), Color(0xA51C1A1D), Color(0xCD211F22)],
    stops: [0, .36, 1],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
  static const navigationBorder = Color(0xA0454247);
  static const navigationSelected = LinearGradient(
    colors: [Color(0xB6504D51), Color(0xA5403E42)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const detail = LinearGradient(
    colors: [
      Color(0xFF15370D),
      Color(0xFF1B4314),
      Color(0xFF215119),
      Color(0xFF24591B),
      Color(0xFF24581A),
      Color(0xFF205015),
      Color(0xFF163912),
      Color(0xFF0B2407),
      Color(0xFF031002),
      Colors.black,
    ],
    stops: [0, .20, .40, .55, .62, .68, .76, .82, .89, .96],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
  static const todayGround = LinearGradient(
    colors: [
      Color(0xFF002104),
      Color(0xFF012503),
      Color(0xFF021102),
      Color(0xFF020603),
      background,
    ],
    stops: [0, .46, .70, .84, .96],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
  static const todayPanel = LinearGradient(
    colors: [
      Color(0xFF04A91B),
      Color(0xFF03A619),
      Color(0xFF11B611),
      Color(0xFF059A13),
      Color(0xFF087113),
      Color(0xFF0B3E16),
      Color(0xFF041805),
      Color(0xFF020903),
      background,
    ],
    stops: [0, .35, .56, .63, .708, .78, .847, .92, .98],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

abstract final class Design {
  static const page = 18.0, small = 8.0, card = 22.0, pill = 100.0;
  static const todayMargin = 15.0, detailMargin = 21.0;
  static const navHeight = 68.0, maxWidth = 480.0, referenceWidth = 390.0;
  static const mono = 'IBM Plex Mono';
  static const metric = TextStyle(
    fontSize: 43,
    height: 1.06,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.6,
    color: Palette.text,
  );
  static const label = TextStyle(
    fontSize: 19,
    fontWeight: FontWeight.w500,
    color: Palette.green,
    letterSpacing: -.25,
  );
  static const body = TextStyle(
    fontSize: 15,
    height: 1.27,
    color: Palette.text,
    letterSpacing: -.16,
  );
  static const foot = TextStyle(
    fontSize: 13,
    color: Palette.muted,
    height: 1.22,
  );
  static const header = TextStyle(
    fontSize: 32,
    height: 1.05,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.15,
  );
  static const section = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -.35,
  );
  static const dashboardSection = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    letterSpacing: -.4,
  );
  static final dashboardButton = FilledButton.styleFrom(
    backgroundColor: Palette.lime,
    foregroundColor: const Color(0xFF0D2105),
    minimumSize: const Size(48, 48),
    textStyle: const TextStyle(
      fontFamily: 'Inter',
      fontSize: 16,
      fontWeight: FontWeight.w700,
    ),
  );

  static ThemeData theme() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: Palette.green,
          brightness: Brightness.dark,
        ).copyWith(
          surface: Palette.surface,
          primary: Palette.green,
          onSurface: Palette.text,
        );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: Palette.background,
      fontFamily: 'Inter',
      canvasColor: Palette.background,
      useMaterial3: true,
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Palette.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Palette.raised,
        contentTextStyle: TextStyle(color: Palette.text),
        insetPadding: EdgeInsets.fromLTRB(14, 6, 14, 96),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Palette.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Palette.green,
          foregroundColor: const Color(0xFF11230D),
          minimumSize: const Size(44, 48),
        ),
      ),
    );
  }
}
