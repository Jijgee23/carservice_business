import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';

// Building blocks of the tenant-app mobile design ("Midnight + Alizarin"):
// navy hero cards, white bordered cards, mono section labels, status pills,
// round icon buttons, grouped settings rows and the blurred bottom action
// bar. Colors come from [CarserviceTheme], so both brightnesses work; the
// navy hero is fixed dark in both, like the web's dark panels.

/// Fixed colors for content on the navy hero ([OpsHeroCard]).
abstract final class OpsDark {
  static const bg = OpsColors.darkPanel;
  static const line = OpsColors.darkLine;
  static const ink = OpsColors.darkInk;
  static const muted = OpsColors.darkMuted;
  static const muted2 = OpsColors.darkMuted2;
  static const accent = OpsColors.darkAccent;
  static const accentHi = OpsColors.darkAccentHi;
}

/// Mono text style (plates, order numbers, times, money, section labels).
TextStyle opsMono(
  BuildContext context, {
  double fontSize = 12,
  FontWeight fontWeight = FontWeight.w400,
  Color? color,
  double? letterSpacing,
}) => TextStyle(
  fontFamily: CarserviceTheme.of(context).monoFontFamily,
  fontSize: fontSize,
  fontWeight: fontWeight,
  color: color ?? CarserviceTheme.of(context).mutedText,
  letterSpacing: letterSpacing,
);

/// "Бат-Эрдэнэ Болд" → "ББ"; first letters of the given parts.
String opsInitials(String? first, [String? last]) => [first, last]
    .map((p) => p?.trim() ?? '')
    .where((p) => p.isNotEmpty)
    .map((p) => p.characters.first)
    .join()
    .toUpperCase();

/// Navy card: today's stats, a vehicle's header, the profile identity.
class OpsHeroCard extends StatelessWidget {
  const OpsHeroCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 20,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    // In dark mode cards are this navy too: lift the hero a step and give
    // it a line so it still reads as the page's lead card.
    decoration: Theme.of(context).brightness == Brightness.dark
        ? BoxDecoration(
            color: OpsColors.darkLine2,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: OpsDark.line),
          )
        : BoxDecoration(color: OpsDark.bg, borderRadius: BorderRadius.circular(radius)),
    child: Padding(
      padding: padding,
      child: IconTheme.merge(
        data: const IconThemeData(color: OpsDark.ink),
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: OpsDark.ink),
          child: child,
        ),
      ),
    ),
  );
}

/// White card with a 1px line — the design's default container.
class OpsCard extends StatelessWidget {
  const OpsCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 16,
    this.onTap,
    this.borderColor,
    this.borderWidth = 1,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  /// Defaults to the theme's line color.
  final Color? borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: borderColor ?? t.border, width: borderWidth),
    );
    return Material(
      color: t.panel,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              onTap: onTap,
              customBorder: shape,
              child: Padding(padding: padding, child: child),
            ),
    );
  }
}

/// "ЯВЦ", "АЖЛУУД", "БҮРТГЭЛ" — mono, upper-case, tracked, muted.
class OpsSectionLabel extends StatelessWidget {
  const OpsSectionLabel(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: opsMono(context, fontSize: 11, letterSpacing: 0.66, color: color),
  );
}

/// Semantic tint of a status pill.
enum OpsTone { accent, warn, ok, info, neutral }

extension OpsToneColors on OpsTone {
  /// Text / icon color on the tint.
  Color foreground(CarserviceTheme t) => switch (this) {
    OpsTone.accent => t.accent,
    OpsTone.warn => t.warn,
    OpsTone.ok => t.ok,
    OpsTone.info => t.info,
    OpsTone.neutral => t.mutedText,
  };

  /// The pale tint behind it.
  Color background(CarserviceTheme t) => switch (this) {
    OpsTone.neutral => t.shellBackground,
    _ => Color.alphaBlend(foreground(t).withValues(alpha: 0.12), t.panel),
  };
}

/// Status pill: "Засварт", "Оношилгоо", "Бэлэн".
class OpsPill extends StatelessWidget {
  const OpsPill(this.label, {super.key, this.tone = OpsTone.neutral, this.icon});

  final String label;
  final OpsTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final fg = tone.foreground(t);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tone.background(t),
        borderRadius: BorderRadius.circular(AppDimens.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 4)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// 44px round outlined icon button (back, more, notifications). [badge]
/// draws the accent dot.
class OpsCircleButton extends StatelessWidget {
  const OpsCircleButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.badge = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final button = IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: t.panel,
        foregroundColor: t.ink,
        side: BorderSide(color: t.border),
        fixedSize: const Size.square(44),
        minimumSize: const Size.square(44),
      ),
      icon: Icon(icon, size: 20),
    );
    if (!badge) return button;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        Positioned(
          top: 12,
          right: 13,
          child: IgnorePointer(
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: t.accentHi, shape: BoxShape.circle),
            ),
          ),
        ),
      ],
    );
  }
}

/// Round initials avatar. [onDark] flips it for the navy hero.
class OpsAvatar extends StatelessWidget {
  const OpsAvatar({super.key, required this.initials, this.size = 44, this.onDark = false});

  final String initials;
  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final bg = onDark ? OpsDark.ink : t.ink;
    final fg = onDark ? OpsDark.bg : t.shellBackground;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Text(
          initials,
          style: TextStyle(fontSize: size * 0.34, fontWeight: FontWeight.w600, color: fg),
        ),
      ),
    );
  }
}

/// Thin rounded progress bar.
class OpsProgressBar extends StatelessWidget {
  const OpsProgressBar({
    super.key,
    required this.value,
    this.height = 4,
    this.color,
    this.trackColor,
  });

  /// 0–1; clamped.
  final double value;
  final double height;
  final Color? color;
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppDimens.radiusFull),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: trackColor ?? t.border),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0.0, 1.0),
              child: ColoredBox(color: color ?? t.accentHi),
            ),
          ],
        ),
      ),
    );
  }
}

/// A white rounded group of rows with hairlines between them (settings).
class OpsGroup extends StatelessWidget {
  const OpsGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    return OpsCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: t.shellBackground),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// One row of an [OpsGroup]: icon tile, title, optional value / trailing,
/// chevron when tappable.
class OpsGroupRow extends StatelessWidget {
  const OpsGroupRow({
    super.key,
    required this.icon,
    required this.title,
    this.value,
    this.trailing,
    this.onTap,
    this.tone,
    this.titleColor,
    this.showChevron = true,
  });

  final IconData icon;
  final String title;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Tints the icon tile (e.g. [OpsTone.warn]); null = neutral.
  final OpsTone? tone;
  final Color? titleColor;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final tileBg = tone?.background(t) ?? t.shellBackground;
    final tileFg = tone?.foreground(t) ?? t.ink;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 50),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: tileBg, borderRadius: BorderRadius.circular(9)),
                child: Icon(icon, size: 16, color: tileFg),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title, style: TextStyle(fontSize: 15, color: titleColor ?? t.ink)),
              ),
              if (value != null) ...[
                const SizedBox(width: 8),
                // Natural width (capped), so the title's Expanded pushes it
                // to the end — a Flexible would split the row in half.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(
                    value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: TextStyle(fontSize: 13, color: tone?.foreground(t) ?? t.mutedText),
                  ),
                ),
              ],
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              if (onTap != null && trailing == null && showChevron) ...[
                const SizedBox(width: 6),
                Icon(Icons.chevron_right_rounded, size: 18, color: t.mutedText3),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom action bar over the content: translucent page color, blur, top
/// hairline. Put it in `Scaffold.bottomNavigationBar`.
class OpsBottomActionBar extends StatelessWidget {
  const OpsBottomActionBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: EdgeInsets.fromLTRB(20, 14, 20, 14 + bottom),
          decoration: BoxDecoration(
            color: t.shellBackground.withValues(alpha: 0.86),
            border: Border(top: BorderSide(color: t.border)),
          ),
          child: Row(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 52px primary (accent) action for [OpsBottomActionBar] and forms.
class OpsPrimaryButton extends StatelessWidget {
  const OpsPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.dark = false,
    this.height = 52,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;

  /// Navy instead of the accent ("Дараах хэсэг →").
  final bool dark;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final bg = dark ? t.ink : t.accent;
    final fg = dark ? t.shellBackground : t.onAccent;
    return SizedBox(
      height: height,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          disabledBackgroundColor: bg.withValues(alpha: 0.5),
          disabledForegroundColor: fg,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: loading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: fg),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// 52px outlined secondary action ("Өмнөх", camera).
class OpsSecondaryButton extends StatelessWidget {
  const OpsSecondaryButton({
    super.key,
    required this.onPressed,
    this.label,
    this.icon,
    this.tooltip,
    this.height = 52,
  }) : assert(label != null || icon != null);

  final VoidCallback? onPressed;
  final String? label;
  final IconData? icon;

  /// Needed when [label] is null (icon-only).
  final String? tooltip;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final button = SizedBox(
      height: height,
      width: label == null ? height : null,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: t.ink,
          backgroundColor: t.panel,
          side: BorderSide(color: t.border),
          padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: label == null
            ? Icon(icon, size: 22)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
                  Text(label!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                ],
              ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
