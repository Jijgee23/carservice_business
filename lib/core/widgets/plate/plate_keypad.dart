import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';

/// Letters a Mongolian plate's three-letter part is typed from.
const plateKeypadLetters = [
  'А', 'Б', 'В', 'Г', 'Д', 'Е', 'Ж', 'З', //
  'И', 'К', 'Л', 'М', 'Н', 'О', 'Ө', 'П', //
  'Р', 'С', 'Т', 'У', 'Ү', 'Ф', 'Х', 'Ц', //
  'Ч', 'Ш', 'Э', 'Ю', 'Я',
];

const _digitRows = [
  ['1', '2', '3'],
  ['4', '5', '6'],
  ['7', '8', '9'],
];

/// The in-app keypad of a plate field: digits for the first four
/// characters, Cyrillic letters for the rest, so a plate is typed without
/// switching the phone's keyboard. [ABC] hands over to the system keyboard
/// for a non-standard plate.
class PlateKeypad extends StatelessWidget {
  const PlateKeypad({
    super.key,
    required this.letters,
    required this.onKey,
    required this.onBackspace,
    required this.onClear,
    required this.onToggle,
    required this.onSystemKeyboard,
    required this.onDone,
  });

  /// Letter grid when true, digit pad otherwise.
  final bool letters;
  final ValueChanged<String> onKey;
  final VoidCallback onBackspace;

  /// Long press on ⌫.
  final VoidCallback onClear;

  /// Switches between digits and letters.
  final VoidCallback onToggle;
  final VoidCallback onSystemKeyboard;
  final VoidCallback onDone;

  static const _gap = 6.0;

  @override
  Widget build(BuildContext context) {
    final theme = CarserviceTheme.of(context);
    Widget row(List<Widget> keys) => Padding(
      padding: const EdgeInsets.only(top: _gap),
      child: Row(
        children: [
          for (var i = 0; i < keys.length; i++) ...[
            if (i > 0) const SizedBox(width: _gap),
            keys[i],
          ],
        ],
      ),
    );
    Widget char(String c) =>
        _Key(key: ValueKey('plate_key_$c'), label: c, semantics: c, onTap: () => onKey(c));
    final backspace = _Key(
      key: const ValueKey('plate_key_backspace'),
      icon: Icons.backspace_outlined,
      semantics: 'Арилгах',
      onTap: onBackspace,
      onLongPress: onClear,
    );
    final toggle = _Key(
      key: const ValueKey('plate_key_mode'),
      label: letters ? '123' : 'АБВ',
      semantics: letters ? 'Цифр' : 'Үсэг',
      muted: true,
      onTap: onToggle,
    );
    final abc = _Key(
      key: const ValueKey('plate_key_abc'),
      label: 'ABC',
      semantics: 'Утасны гар',
      muted: true,
      onTap: onSystemKeyboard,
    );
    final done = _Key(
      key: const ValueKey('plate_key_done'),
      label: 'Болсон',
      semantics: 'Болсон',
      flex: 2,
      primary: true,
      onTap: onDone,
    );

    final List<Widget> rows;
    if (letters) {
      rows = [
        for (var start = 0; start < plateKeypadLetters.length; start += 8)
          row([
            for (var i = start; i < start + 8; i++)
              i < plateKeypadLetters.length
                  ? char(plateKeypadLetters[i])
                  : const Expanded(child: SizedBox()),
          ]),
        row([toggle, abc, const Expanded(child: SizedBox()), backspace, done]),
      ];
    } else {
      rows = [
        for (final digits in _digitRows) row([for (final d in digits) char(d)]),
        row([toggle, char('0'), backspace]),
        row([abc, const Expanded(child: SizedBox()), done]),
      ];
    }
    return Container(
      key: const ValueKey('plate_keypad'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(_gap, 0, _gap, _gap),
      decoration: BoxDecoration(
        color: theme.panel2,
        borderRadius: BorderRadius.circular(AppDimens.radiusMD),
        border: Border.all(color: theme.border),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: rows),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    super.key,
    required this.semantics,
    required this.onTap,
    this.label,
    this.icon,
    this.onLongPress,
    this.flex = 1,
    this.muted = false,
    this.primary = false,
  });

  final String? label;
  final IconData? icon;
  final String semantics;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final int flex;
  final bool muted;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = CarserviceTheme.of(context);
    // Dark panels sit too close to each other: lift the keys with ink.
    final dark = Theme.of(context).brightness == Brightness.dark;
    Color lifted(double alpha) => Color.alphaBlend(theme.ink.withValues(alpha: alpha), theme.panel);
    final background = primary
        ? theme.accent
        : muted
        ? (dark ? lifted(0.16) : theme.border)
        : (dark ? lifted(0.08) : theme.panel);
    final foreground = primary ? theme.onAccent : theme.ink;
    return Expanded(
      flex: flex,
      child: Semantics(
        button: true,
        label: semantics,
        excludeSemantics: true,
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(AppDimens.radiusSM),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppDimens.radiusSM),
            // Keypad keys never take focus: the plate field keeps it.
            canRequestFocus: false,
            onTap: onTap,
            onLongPress: onLongPress,
            child: SizedBox(
              height: 44,
              child: Center(
                child: icon != null
                    ? Icon(icon, size: 20, color: foreground)
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          label!,
                          style: TextStyle(
                            fontSize: muted || primary ? 14 : 18,
                            fontWeight: FontWeight.w600,
                            color: foreground,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
