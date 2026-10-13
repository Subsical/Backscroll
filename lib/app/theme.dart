import 'package:flutter/material.dart';

abstract final class Palette {
  static const blurple = Color(0xFF5865F2);
  static const blurpleDark = Color(0xFF4752C4);
  static const green = Color(0xFF45A366);
  static const red = Color(0xFFF23F43);
  static const danger = Color(0xFFD22D39);
  static const yellow = Color(0xFFF0B232);
  static const pink = Color(0xFFEB459E);

  static const chat = Color(0xFF323339);
  static const sidebar = Color(0xFF2C2D32);
  static const rail = Color(0xFF2C2D32);
  static const panel = Color(0xFF393A41);
  static const floating = Color(0xFF393A41);
  static const input = Color(0x14000000);
  static const field = Color(0xFF393A41);
  static const hover = Color(0x1F97979F);
  static const selected = Color(0x3397979F);
  static const divider = Color(0x1F97979F);
  static const spoiler = Color(0xFF7D7E87);
  static const spine = Color(0xFF595A63);
  static const code = Color(0x145865F2);

  static const header = Color(0xFFFFFFFF);
  static const text = Color(0xFFF3F3F4);
  static const subtle = Color(0xFFC5C6CA);
  static const muted = Color(0xFFABACB2);
  static const faint = Color(0xFF9D9EA5);
  static const channel = Color(0xFF999AA1);
  static const placeholder = Color(0xFFA4A5AB);
  static const prompt = Color(0xFF6D6F78);
  static const link = Color(0xFF76AFF6);
  static const mention = Color(0x3D5865F2);
  static const mentionText = Color(0xFFC9CDFB);
}

abstract final class Fonts {
  static const family = 'Figtree';
  static const mono = 'monospace';
  static const monoFallback = [
    'Consolas',
    'Menlo',
    'DejaVu Sans Mono',
    'Liberation Mono',
    'Courier New',
  ];
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: Palette.blurple,
    onPrimary: Colors.white,
    secondary: Palette.blurple,
    onSecondary: Colors.white,
    surface: Palette.chat,
    onSurface: Palette.text,
    error: Palette.red,
    onError: Colors.white,
    surfaceContainerHighest: Palette.sidebar,
    outline: Palette.divider,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: Fonts.family,
    scaffoldBackgroundColor: Palette.chat,
    canvasColor: Palette.chat,
    dividerColor: Palette.divider,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: Palette.hover,
    visualDensity: VisualDensity.standard,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: Palette.text,
      displayColor: Palette.header,
      fontFamily: Fonts.family,
    ),
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(
        color: Palette.floating,
        borderRadius: BorderRadius.all(Radius.circular(8)),
        border: Border.fromBorderSide(BorderSide(color: Palette.divider)),
        boxShadow: Styles.lift,
      ),
      textStyle: TextStyle(
        color: Palette.header,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        fontFamily: Fonts.family,
      ),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      waitDuration: Duration(milliseconds: 300),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.all(4),
      radius: const Radius.circular(2),
      thumbColor: WidgetStateProperty.all(const Color(0xFF767780)),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: Palette.text,
      selectionColor: Color(0x665865F2),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Palette.floating,
      contentTextStyle: TextStyle(
        color: Palette.text,
        fontFamily: Fonts.family,
      ),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Palette.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: Palette.divider),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Palette.panel,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: Palette.faint,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    ),
    textButtonTheme: const TextButtonThemeData(
      style: ButtonStyle(
        mouseCursor: WidgetStateMouseCursor.clickable,
        overlayColor: WidgetStatePropertyAll(Palette.hover),
      ),
    ),
    iconButtonTheme: const IconButtonThemeData(
      style: ButtonStyle(mouseCursor: WidgetStateMouseCursor.clickable),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: Palette.floating,
      surfaceTintColor: Colors.transparent,
      mouseCursor: WidgetStateMouseCursor.clickable,
      textStyle: TextStyle(
        color: Palette.text,
        fontSize: 14,
        fontFamily: Fonts.family,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        side: BorderSide(color: Palette.divider),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Palette.blurple
            : const Color(0x1F000000),
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.transparent
            : Palette.selected,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Palette.blurple
            : Palette.input,
      ),
      side: const BorderSide(color: Color(0xA397979F), width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      mouseCursor: WidgetStateMouseCursor.clickable,
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Palette.header
            : Palette.faint,
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Palette.blurple,
      linearTrackColor: Palette.selected,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Palette.input,
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      hintStyle: TextStyle(color: Palette.placeholder),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: Palette.selected),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: Palette.selected),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: Palette.blurple, width: 1),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: Palette.red, width: 1),
      ),
    ),
  );
}

abstract final class Styles {
  static const sectionLabel = TextStyle(
    color: Palette.channel,
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );
  static const label = TextStyle(
    color: Palette.text,
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );
  static const title = TextStyle(
    color: Palette.header,
    fontSize: 20,
    fontWeight: FontWeight.w700,
  );
  static const body = TextStyle(
    color: Palette.text,
    fontSize: 16,
    height: 1.375,
  );
  static const small = TextStyle(
    color: Palette.muted,
    fontSize: 14,
    height: 1.3,
  );
  static const tiny = TextStyle(color: Palette.muted, fontSize: 12);

  static const underline = Border(bottom: BorderSide(color: Palette.divider));
  static const lift = [
    BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4)),
  ];
  static const card = BoxDecoration(
    color: Palette.panel,
    borderRadius: BorderRadius.all(Radius.circular(8)),
    border: Border.fromBorderSide(BorderSide(color: Palette.divider)),
  );
  static const inset = BoxDecoration(
    color: Palette.input,
    borderRadius: BorderRadius.all(Radius.circular(8)),
    border: Border.fromBorderSide(BorderSide(color: Palette.selected)),
  );
}
