import 'dart:async' show unawaited;

import 'package:carservice_business/core/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

// import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────
// The web dashboard's "Ops Console" palette, for both brightnesses.
//
// Source of truth: `carservice.mn/app/globals.css`, the `.landing-ops` block
// (dark) and its `html.light .landing-ops` override (light), read
// 2026-09-28. Every `--oc-*` value in [OpsColors] is copied from there,
// including the per-brightness `--oc-on-accent`.
//
// Everything Material draws on its own — bottom navigation, sheets, menus,
// dialogs, chips — is pinned to that palette through an explicit
// [ColorScheme] (no `ColorScheme.fromSeed`), so no seed-derived tint that
// the web doesn't have can appear next to it.
//
// Surfaces are flat panels with a 1px line, no glass and no elevation tint:
// the dashboard is a dense data tool.
// ─────────────────────────────────────────────────────────────────────────

/// Persists the user's theme choice across launches.
///
/// Uses its own small Hive box rather than [Authenticator]'s pattern
/// (`lib/core/services/auth_storage.dart`) verbatim: that box stores a typed
/// `User` object and needs a generated `TypeAdapter`; a single theme-mode
/// string needs neither, so a plain `Box<String>` is the right-sized version
/// of the same box/key convention. `Hive.initFlutter()` already runs in
/// `main.dart` before this provider is constructed, so opening the box here
/// (rather than adding another `await X.init()` call to `main.dart`) is
/// enough — this keeps the change inside the files this slice owns.
class ThemeProvider extends ChangeNotifier {
  static const _boxName = 'settings';
  static const _key = 'themeMode';

  ThemeProvider() {
    unawaited(_restore());
  }

  ThemeMode mode = ThemeMode.light;
  bool get userChoosedSystem => mode == ThemeMode.system;

  Future<void> _restore() async {
    try {
      final box = await Hive.openBox<String>(_boxName);
      final restored = _decode(box.get(_key));
      if (restored != null && restored != mode) {
        mode = restored;
        notifyListeners();
      }
    } catch (_) {
      // No persisted box yet, or Hive isn't available in this environment
      // (e.g. a unit test with no plugin bindings) — keep the ThemeMode.light
      // default rather than throwing out of a constructor.
    }
  }

  /// Was previously unreachable: the missing `return` after the `if` branch
  /// meant every call fell through and unconditionally set `mode = dark`, so
  /// starting from dark could never get back to light. Fixed by making this
  /// a plain toggle, and persisting the result.
  ///
  /// The in-memory toggle is synchronous and always completes immediately;
  /// persistence is dispatched with [unawaited] rather than `await`ed here,
  /// so a slow or stuck disk/box can never delay (or, worse, hang) the
  /// caller — toggling the theme must never be gated on I/O.
  Future<void> toggleTheme() async {
    mode = mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    unawaited(_persist(mode));
  }

  /// Picks an explicit mode (Профайл → Харагдах байдал), including
  /// [ThemeMode.system]. Same fire-and-forget persistence as [toggleTheme].
  void setMode(ThemeMode value) {
    if (value == mode) return;
    mode = value;
    notifyListeners();
    unawaited(_persist(value));
  }

  Future<void> _persist(ThemeMode value) async {
    try {
      final box = await Hive.openBox<String>(_boxName);
      await box.put(_key, _encode(value));
    } catch (_) {
      // Persistence is best-effort; the in-memory toggle already happened
      // and must not be rolled back if the disk write fails.
    }
  }

  static String _encode(ThemeMode m) => switch (m) {
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
    ThemeMode.light => 'light',
  };

  static ThemeMode? _decode(String? value) {
    switch (value) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      default:
        return null;
    }
  }
}

/// IBM Plex family names, as registered in `pubspec.yaml`'s `fonts:` block.
///
/// Bundled binaries: IBM Plex Sans 400/500/600/700 and IBM Plex Mono 400/500,
/// fetched from IBM's official `IBM/plex` GitHub repo (SIL Open Font License
/// 1.1 — redistribution permitted; license copies live alongside the font
/// files at `asset/fonts/IBMPlexSans/OFL.txt` and
/// `asset/fonts/IBMPlexMono/OFL.txt`).
///
/// (Superseded 2026-09-24: IBM Plex Sans is now the default `fontFamily`.)
/// Poppins stayed the app's default `fontFamily` for this slice — every
/// existing screen relies on it implicitly (none hardcode a
/// family), and flipping the app-wide default is a typography-wide visual
/// change to 40+ read-only feature files, not a theme-definition change.
/// That migration is explicitly out of this slice's scope (see the slice
/// spec: "Keep Poppins bundled — feature screens still reference it;
/// removing it is a later slice's job"). IBM Plex Mono is wired here and
/// ready to use — `CarserviceTheme.monoFontFamily` — for tabular content order
/// numbers, plates, money) the next time those widgets are touched; no
/// existing screen was edited to adopt it in this slice (that would be
/// restyling a read-only file).
abstract final class AppFonts {
  static const sans = 'IBM Plex Sans';
  static const mono = 'IBM Plex Mono';
}

/// Legacy, brightness-agnostic palette. Every field name below is unchanged
/// from the pre-P0-F3 navy/blue theme — over 300 call sites across 40+
/// feature files (read-only for this slice) reference these as literal
/// `Color` constants, not through `Theme.of(context)`, so renaming or
/// removing any of them would break compilation in files this slice must
/// not touch. What changed is only the *value* each name maps to: every
/// entry now carries the Ops Console token it plays the equivalent role
/// for (see the class-level comment above for the source line range).
///
/// Because these are static consts, not `Theme.of(context)` lookups, they
/// can react to [ThemeMode] through the runtime palette and typography
/// accessors below.
/// Runtime aliases for the legacy palette names used by the pre-parity
/// widgets. Unlike [AppColors], these resolve through the active
/// [CarserviceTheme] so switching brightness updates existing presentation code.
/// New widgets should prefer the semantic [CarserviceTheme] fields directly.
class ThemePalette {
  const ThemePalette(this.theme);
  final CarserviceTheme theme;

  // These aliases remain for compatibility only. New call sites should use
  // `accent` for chips/icons and the explicit fixed dark brand surfaces.
  Color get primary => theme.accent;
  Color get primaryLight => theme.accentHi;
  Color get brandSurface => OpsColors.darkCarbon;
  Color get brandSurface2 => OpsColors.darkPanel2;
  Color get accent => theme.accent;
  Color get accentLight => theme.accentHi;
  Color get good => theme.ok;
  Color get warning => theme.warn;
  Color get danger => theme.danger;
  Color get background => theme.shellBackground;
  Color get surface => theme.panel;
  Color get cardBg => theme.panel;
  Color get divider => theme.border;
  Color get textPrimary => theme.ink;
  Color get textSecondary => theme.mutedText;
  Color get textHint => theme.mutedText3;
  Color get textOnDark => Colors.white;
  Color get goodBg => theme.ok.withValues(alpha: 0.12);
  Color get warningBg => theme.warn.withValues(alpha: 0.12);
  Color get dangerBg => theme.danger.withValues(alpha: 0.12);
}

extension ThemePaletteContext on BuildContext {
  ThemePalette get colors => ThemePalette(CarserviceTheme.of(this));

  Color checkStatusColor(CheckStatus status) => switch (status) {
    CheckStatus.good => colors.good,
    CheckStatus.warning => colors.warning,
    CheckStatus.danger => colors.danger,
  };

  Color checkStatusBackground(CheckStatus status) =>
      checkStatusColor(status).withValues(alpha: 0.12);
}

/// Dual-brightness Ops Console tokens, transcribed 1:1 from the
/// `.landing-ops` blocks of `carservice.mn/app/globals.css` (`--oc-*` custom
/// properties). [AppTheme] builds `ThemeData`/[CarserviceTheme] from these.
abstract final class OpsColors {
  static const darkCarbon = Color(0xFF0B0D10); // --oc-carbon
  static const darkPanel = Color(0xFF0E1116); // --oc-panel
  static const darkPanel2 = Color(0xFF101318); // --oc-panel2
  static const darkLine = Color(0xFF23272E); // --oc-line
  static const darkLine2 = Color(0xFF191D23); // --oc-line2
  static const darkInk = Color(0xFFF4F5F7); // --oc-ink
  static const darkInk2 = Color(0xFFEDEEF0); // --oc-ink2
  static const darkMuted = Color(0xFFA7ADB6); // --oc-muted
  static const darkMuted2 = Color(0xFF8A8F98); // --oc-muted2
  static const darkMuted3 = Color(0xFF6E747E); // --oc-muted3
  static const darkMuted4 = Color(0xFF4A4D54); // --oc-muted4
  static const darkAccent = Color(0xFF22D3EE); // --oc-accent
  static const darkAccentHi = Color(0xFF67E8F9); // --oc-accent-hi
  static const darkOk = Color(0xFF3DDC97); // --oc-ok
  static const darkWarn = Color(0xFFDC7F4F); // --oc-warn
  // Plan §5.1 "Danger" dark row; not an --oc-* token.
  static const darkDanger = Color(0xFFEF4444);
  // Content on accent fills — dark on the light cyan accent.
  static const darkOnAccent = Color(0xFF14120C); // --oc-on-accent

  static const lightCarbon = Color(0xFFF6F5F2); // --oc-carbon (light)
  static const lightPanel = Color(0xFFFFFFFF); // --oc-panel (light)
  static const lightPanel2 = Color(0xFFFAF9F8); // --oc-panel2 (light)
  static const lightLine = Color(0xFFE3E0DA); // --oc-line (light)
  static const lightLine2 = Color(0xFFEAE7E1); // --oc-line2 (light)
  static const lightInk = Color(0xFF16171B); // --oc-ink (light)
  static const lightInk2 = Color(0xFF1E1F24); // --oc-ink2 (light)
  static const lightMuted = Color(0xFF5C6067); // --oc-muted (light)
  static const lightMuted2 = Color(0xFF74787F); // --oc-muted2 (light)
  static const lightMuted3 = Color(0xFF90949B); // --oc-muted3 (light)
  static const lightMuted4 = Color(0xFFB7BABF); // --oc-muted4 (light)
  static const lightAccent = Color(0xFF0E7490); // --oc-accent (light)
  static const lightAccentHi = Color(0xFF0891B2); // --oc-accent-hi (light)
  static const lightOk = Color(0xFF1E9F6E); // --oc-ok (light)
  static const lightWarn = Color(0xFFB45309); // --oc-warn (light)
  // Plan §5.1 "Danger" light row; not an --oc-* token.
  static const lightDanger = Color(0xFFDC2626);
  // Content on accent fills — white on the dark teal accent.
  static const lightOnAccent = Color(0xFFFFFFFF); // --oc-on-accent (light)
}

/// Ops Console geometry (slice spec): 10px on panels (web's `rounded-[10px]`),
/// 8px on compact controls (inputs, chips, small buttons).
abstract final class AppRadii {
  static const panel = 10.0;
  static const control = 8.0;
}

@immutable
class CarserviceTheme extends ThemeExtension<CarserviceTheme> {
  const CarserviceTheme({
    required this.shellBackground,
    required this.panel,
    required this.panel2,
    required this.border,
    required this.borderSubtle,
    required this.ink,
    required this.ink2,
    required this.mutedText,
    required this.mutedText2,
    required this.mutedText3,
    required this.accent,
    required this.accentHi,
    required this.onAccent,
    required this.ok,
    required this.warn,
    required this.danger,
    required this.monoFontFamily,
  });

  final Color shellBackground;
  final Color panel;
  final Color panel2;
  final Color border;
  final Color borderSubtle;
  final Color ink;
  final Color ink2;
  final Color mutedText;
  final Color mutedText2;
  final Color mutedText3;
  final Color accent;
  final Color accentHi;
  final Color onAccent;
  final Color ok;
  final Color warn;
  final Color danger;

  /// Order numbers, plate numbers, money — anything tabular. Read this
  /// instead of hardcoding `'IBM Plex Mono'` in a widget.
  final String monoFontFamily;

  static CarserviceTheme of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<CarserviceTheme>() ?? _fallback(theme);
  }

  /// Keeps shared widgets safe in previews, isolated tests, and host apps
  /// that provide a plain [ThemeData] rather than installing our extension.
  /// The fallback deliberately follows Material's active color scheme so it
  /// still tracks the host brightness and custom theme colors.
  static CarserviceTheme _fallback(ThemeData theme) {
    final scheme = theme.colorScheme;
    return CarserviceTheme(
      shellBackground: theme.scaffoldBackgroundColor,
      panel: scheme.surface,
      panel2: scheme.surface,
      border: scheme.outline,
      borderSubtle: scheme.outlineVariant,
      ink: scheme.onSurface,
      ink2: scheme.onSurface,
      mutedText: scheme.onSurfaceVariant,
      mutedText2: scheme.onSurfaceVariant,
      mutedText3: scheme.onSurfaceVariant,
      accent: scheme.primary,
      accentHi: scheme.secondary,
      onAccent: scheme.onPrimary,
      ok: scheme.tertiary,
      warn: scheme.secondary,
      danger: scheme.error,
      monoFontFamily: AppFonts.mono,
    );
  }

  @override
  CarserviceTheme copyWith({
    Color? shellBackground,
    Color? panel,
    Color? panel2,
    Color? border,
    Color? borderSubtle,
    Color? ink,
    Color? ink2,
    Color? mutedText,
    Color? mutedText2,
    Color? mutedText3,
    Color? accent,
    Color? accentHi,
    Color? onAccent,
    Color? ok,
    Color? warn,
    Color? danger,
    String? monoFontFamily,
  }) => CarserviceTheme(
    shellBackground: shellBackground ?? this.shellBackground,
    panel: panel ?? this.panel,
    panel2: panel2 ?? this.panel2,
    border: border ?? this.border,
    borderSubtle: borderSubtle ?? this.borderSubtle,
    ink: ink ?? this.ink,
    ink2: ink2 ?? this.ink2,
    mutedText: mutedText ?? this.mutedText,
    mutedText2: mutedText2 ?? this.mutedText2,
    mutedText3: mutedText3 ?? this.mutedText3,
    accent: accent ?? this.accent,
    accentHi: accentHi ?? this.accentHi,
    onAccent: onAccent ?? this.onAccent,
    ok: ok ?? this.ok,
    warn: warn ?? this.warn,
    danger: danger ?? this.danger,
    monoFontFamily: monoFontFamily ?? this.monoFontFamily,
  );

  @override
  CarserviceTheme lerp(CarserviceTheme? other, double t) {
    if (other == null) return this;
    return CarserviceTheme(
      shellBackground: Color.lerp(shellBackground, other.shellBackground, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      panel2: Color.lerp(panel2, other.panel2, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      ink2: Color.lerp(ink2, other.ink2, t)!,
      mutedText: Color.lerp(mutedText, other.mutedText, t)!,
      mutedText2: Color.lerp(mutedText2, other.mutedText2, t)!,
      mutedText3: Color.lerp(mutedText3, other.mutedText3, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentHi: Color.lerp(accentHi, other.accentHi, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      ok: Color.lerp(ok, other.ok, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      // Not interpolable — snap over at the halfway point like other
      // discrete (non-Color) ThemeExtension fields conventionally do.
      monoFontFamily: t < 0.5 ? monoFontFamily : other.monoFontFamily,
    );
  }
}

/// Typography resolved from the active [CarserviceTheme]. The metrics match the
/// former static styles exactly; only their semantic foreground colors now
/// follow brightness. `bigNumber` stays white because it is used on an
/// explicit dark dashboard surface.
class ThemeTextStyles {
  const ThemeTextStyles(this.theme);

  final CarserviceTheme theme;

  TextStyle get h1 => TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: theme.ink,
    height: 1.3,
  );
  TextStyle get h2 => TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: theme.ink,
    height: 1.3,
  );
  TextStyle get h3 =>
      TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: theme.ink);
  TextStyle get body =>
      TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: theme.ink);
  TextStyle get bodyMedium =>
      TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: theme.ink);
  TextStyle get caption => TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: theme.mutedText,
  );
  TextStyle get captionMedium => TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: theme.mutedText,
  );
  TextStyle get label => TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
    color: theme.mutedText,
  );
  TextStyle get bigNumber => const TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.w800,
    color: Colors.white,
  );
  TextStyle get buttonText => TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: theme.onAccent,
  );
}

extension ThemeTextStylesContext on BuildContext {
  ThemeTextStyles get textStyles => ThemeTextStyles(CarserviceTheme.of(this));
}

class AppDimens {
  AppDimens._();
  static const double radiusXS = 4;
  static const double radiusSM = 8; // AppRadii.control — compact controls
  // Panel radius, per the slice spec: 10px, matching web's `rounded-[10px]`.
  // Was 12 under the navy/blue theme.
  static const double radiusMD = 10;
  static const double radiusLG = 16;
  static const double radiusXL = 20;
  static const double radiusFull = 999;
  static const double paddingXS = 4;
  static const double paddingSM = 8;
  static const double paddingMD = 16;
  static const double paddingLG = 20;
  static const double paddingXL = 24;
  static const double iconSM = 16;
  static const double iconMD = 20;
  static const double iconLG = 24;
  // Ops Console panels are flat (1px border, no shadow) — was 2.
  static const double cardElevation = 0;
  static const double bottomNavHeight = 64;
}

extension CheckStatusTheme on CheckStatus {
  IconData get icon {
    switch (this) {
      case CheckStatus.good:
        return Icons.check_circle;
      case CheckStatus.warning:
        return Icons.warning_amber_rounded;
      case CheckStatus.danger:
        return Icons.cancel;
    }
  }

  String get label {
    switch (this) {
      case CheckStatus.good:
        return 'Хэвийн';
      case CheckStatus.warning:
        return 'Анхаарах';
      case CheckStatus.danger:
        return 'Засвар шаардлагатай';
    }
  }
}

extension InspectionTypeTheme on InspectionType {
  String get label {
    switch (this) {
      case InspectionType.technical:
        return 'Техникийн оношилгоо';
      case InspectionType.routine:
        return 'Ердийн үзлэг';
      case InspectionType.repair:
        return 'Засварын дараах';
    }
  }
}

abstract final class AppTheme {
  static ThemeData get light => _theme(Brightness.light);
  static ThemeData get dark => _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final p = _Palette.of(brightness);

    OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(color: color, width: width),
        );
    WidgetStateProperty<T> bySelection<T>(T selected, T idle) =>
        WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? selected : idle,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      // IBM Plex Sans is the app-wide default (web parity; it has Cyrillic).
      fontFamily: AppFonts.sans,
      colorScheme: _scheme(p),
      scaffoldBackgroundColor: p.carbon,
      // Dropdown menus and other canvas-coloured popups are panels.
      canvasColor: p.panel,
      dividerColor: p.line,
      extensions: [p.extension],

      // Component text styles below *replace* Material's defaults rather
      // than merging with them, so each names the family itself — without
      // it app bar titles, buttons, tabs and dialogs fell back to the
      // platform font instead of IBM Plex Sans.

      // ── Page chrome ───────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: p.panel,
        foregroundColor: p.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        shape: Border(bottom: BorderSide(color: p.line)),
        titleTextStyle: TextStyle(
          fontFamily: AppFonts.sans,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: p.ink,
        ),
        iconTheme: IconThemeData(color: p.ink),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: p.isDark
              ? Brightness.light
              : Brightness.dark,
          statusBarBrightness: p.isDark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: p.panel,
          systemNavigationBarIconBrightness: p.isDark
              ? Brightness.light
              : Brightness.dark,
        ),
      ),
      // Every back button — an app bar's automatic one or an explicit
      // `BackButton` — is the same rounded chevron tile.
      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: (_) => Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            // Translucent, so the button's press overlay shows through.
            color: p.ink.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(AppDimens.radiusMD),
            border: Border.all(color: p.line),
          ),
          child: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: AppDimens.iconSM,
            color: p.ink,
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.panel,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: p.selected,
        iconTheme: bySelection(
          IconThemeData(color: p.accentHi),
          IconThemeData(color: p.muted),
        ),
        labelTextStyle: bySelection(
          TextStyle(
            fontFamily: AppFonts.sans,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: p.ink,
          ),
          TextStyle(
            fontFamily: AppFonts.sans,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: p.muted,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: p.panel,
        indicatorColor: p.selected,
        selectedIconTheme: IconThemeData(color: p.accentHi),
        unselectedIconTheme: IconThemeData(color: p.muted),
        selectedLabelTextStyle: TextStyle(
          fontFamily: AppFonts.sans,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: p.ink,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontFamily: AppFonts.sans,
          fontSize: 13,
          color: p.muted,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: p.ink,
        unselectedLabelColor: p.muted,
        indicatorColor: p.accent,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(
          fontFamily: AppFonts.sans,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: AppFonts.sans,
          fontSize: 13,
          fontWeight: FontWeight.w400,
        ),
      ),

      // ── Panels ────────────────────────────────────────────────────────
      // Flat panel + 1px line, matching `.landing-ops`.
      cardTheme: CardThemeData(
        color: p.panel,
        surfaceTintColor: Colors.transparent,
        elevation: AppDimens.cardElevation,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.panel),
          side: BorderSide(color: p.line),
        ),
        margin: EdgeInsets.zero,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.panel,
        modalBackgroundColor: p.panel,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: p.muted3,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppDimens.radiusXL),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusLG),
          side: BorderSide(color: p.line),
        ),
        titleTextStyle: TextStyle(
          fontFamily: AppFonts.sans,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: p.ink,
        ),
        contentTextStyle: TextStyle(
          fontFamily: AppFonts.sans,
          fontSize: 14,
          height: 1.5,
          color: p.muted,
        ),
      ),
      // Same panel as `AppDropdown.menuStyle`, so every menu matches.
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(p.panel),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(6),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 6),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDimens.radiusLG),
              side: BorderSide(color: p.line),
            ),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.panel,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        menuPadding: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusLG),
          side: BorderSide(color: p.line),
        ),
        textStyle: TextStyle(
          fontFamily: AppFonts.sans,
          fontSize: 14,
          color: p.ink,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.ink,
        contentTextStyle: TextStyle(
          fontFamily: AppFonts.sans,
          fontSize: 14,
          color: p.panel,
        ),
        // The bar is the inverse surface, so its action takes the other
        // brightness' accent.
        actionTextColor: p.isDark
            ? OpsColors.lightAccent
            : OpsColors.darkAccentHi,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.panel),
        ),
      ),

      // ── Buttons ───────────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: p.onAccent,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.paddingLG,
            vertical: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
          textStyle: const TextStyle(
            fontFamily: AppFonts.sans,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          backgroundColor: p.accent,
          foregroundColor: p.onAccent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
          textStyle: const TextStyle(
            fontFamily: AppFonts.sans,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.muted,
          side: BorderSide(color: p.line),
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.paddingLG,
            vertical: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
        ),
      ),
      // No foreground here: a theme-wide colour would also override
      // `IconButton.filled`'s on-accent icon. Standard icon buttons get
      // `colorScheme.onSurfaceVariant` (= muted) by default. The style stays
      // non-null because AppBar derives its ink-coloured leading/action icons
      // by copying it.
      iconButtonTheme: const IconButtonThemeData(style: ButtonStyle()),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        elevation: 2,
        focusElevation: 2,
        hoverElevation: 3,
        highlightElevation: 3,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.panel,
        selectedColor: p.selected,
        side: BorderSide(color: p.line),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
        labelStyle: TextStyle(
          fontFamily: AppFonts.sans,
          fontSize: 13,
          color: p.ink,
        ),
        secondaryLabelStyle: TextStyle(
          fontFamily: AppFonts.sans,
          fontSize: 13,
          color: p.accentHi,
        ),
        checkmarkColor: p.accentHi,
      ),

      // ── Forms ─────────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.panel,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppDimens.paddingMD,
          vertical: 14,
        ),
        border: inputBorder(p.line),
        enabledBorder: inputBorder(p.line),
        // `.auth-input:focus` under `.landing-ops`: the accent at 60%.
        focusedBorder: inputBorder(p.accent.withValues(alpha: 0.6), 1.5),
        hintStyle: TextStyle(fontFamily: AppFonts.sans, color: p.muted3),
        prefixIconColor: p.muted,
      ),
      dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.accentHi,
        linearTrackColor: p.line,
      ),
    );
  }

  /// Every [ColorScheme] role mapped onto the palette, so Material widgets
  /// with no explicit theme above still stay on-palette.
  static ColorScheme _scheme(_Palette p) {
    Color tint(Color color) => Color.alphaBlend(
      color.withValues(alpha: p.isDark ? 0.18 : 0.14),
      p.panel,
    );
    return ColorScheme(
      brightness: p.brightness,
      primary: p.accent,
      onPrimary: p.onAccent,
      primaryContainer: p.selected,
      onPrimaryContainer: p.accentHi,
      secondary: p.accentHi,
      onSecondary: p.onAccent,
      secondaryContainer: p.selected,
      onSecondaryContainer: p.accentHi,
      tertiary: p.ok,
      onTertiary: p.onAccent,
      tertiaryContainer: tint(p.ok),
      onTertiaryContainer: p.ok,
      error: p.danger,
      onError: Colors.white,
      errorContainer: tint(p.danger),
      onErrorContainer: p.danger,
      surface: p.panel,
      onSurface: p.ink,
      onSurfaceVariant: p.muted,
      surfaceDim: p.carbon,
      surfaceBright: p.panel,
      surfaceContainerLowest: p.panel,
      surfaceContainerLow: p.panel,
      surfaceContainer: p.panel,
      surfaceContainerHigh: p.panel2,
      surfaceContainerHighest: p.panel2,
      surfaceTint: Colors.transparent,
      outline: p.line,
      outlineVariant: p.line2,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: p.ink,
      onInverseSurface: p.panel,
      inversePrimary: p.accentHi,
    );
  }
}

/// One brightness' worth of [OpsColors].
class _Palette {
  const _Palette._({
    required this.brightness,
    required this.carbon,
    required this.panel,
    required this.panel2,
    required this.line,
    required this.line2,
    required this.ink,
    required this.ink2,
    required this.muted,
    required this.muted2,
    required this.muted3,
    required this.accent,
    required this.accentHi,
    required this.onAccent,
    required this.ok,
    required this.warn,
    required this.danger,
  });

  factory _Palette.of(Brightness brightness) =>
      brightness == Brightness.dark ? _dark : _light;

  static const _dark = _Palette._(
    brightness: Brightness.dark,
    carbon: OpsColors.darkCarbon,
    panel: OpsColors.darkPanel,
    panel2: OpsColors.darkPanel2,
    line: OpsColors.darkLine,
    line2: OpsColors.darkLine2,
    ink: OpsColors.darkInk,
    ink2: OpsColors.darkInk2,
    muted: OpsColors.darkMuted,
    muted2: OpsColors.darkMuted2,
    muted3: OpsColors.darkMuted3,
    accent: OpsColors.darkAccent,
    accentHi: OpsColors.darkAccentHi,
    onAccent: OpsColors.darkOnAccent,
    ok: OpsColors.darkOk,
    warn: OpsColors.darkWarn,
    danger: OpsColors.darkDanger,
  );

  static const _light = _Palette._(
    brightness: Brightness.light,
    carbon: OpsColors.lightCarbon,
    panel: OpsColors.lightPanel,
    panel2: OpsColors.lightPanel2,
    line: OpsColors.lightLine,
    line2: OpsColors.lightLine2,
    ink: OpsColors.lightInk,
    ink2: OpsColors.lightInk2,
    muted: OpsColors.lightMuted,
    muted2: OpsColors.lightMuted2,
    muted3: OpsColors.lightMuted3,
    accent: OpsColors.lightAccent,
    accentHi: OpsColors.lightAccentHi,
    onAccent: OpsColors.lightOnAccent,
    ok: OpsColors.lightOk,
    warn: OpsColors.lightWarn,
    danger: OpsColors.lightDanger,
  );

  final Brightness brightness;
  final Color carbon;
  final Color panel;
  final Color panel2;
  final Color line;
  final Color line2;
  final Color ink;
  final Color ink2;
  final Color muted;
  final Color muted2;
  final Color muted3;
  final Color accent;
  final Color accentHi;
  final Color onAccent;
  final Color ok;
  final Color warn;
  final Color danger;

  bool get isDark => brightness == Brightness.dark;

  /// Selected nav item, chip or option — `--filter-active-bg`: the accent at
  /// 18% (dark) / 14% (light), flattened onto a panel.
  Color get selected =>
      Color.alphaBlend(accent.withValues(alpha: isDark ? 0.18 : 0.14), panel);

  CarserviceTheme get extension => CarserviceTheme(
    shellBackground: carbon,
    panel: panel,
    panel2: panel2,
    border: line,
    borderSubtle: line2,
    ink: ink,
    ink2: ink2,
    mutedText: muted,
    mutedText2: muted2,
    mutedText3: muted3,
    accent: accent,
    accentHi: accentHi,
    onAccent: onAccent,
    ok: ok,
    warn: warn,
    danger: danger,
    monoFontFamily: AppFonts.mono,
  );
}
