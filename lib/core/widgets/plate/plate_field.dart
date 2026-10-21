import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:carservice_business/core/widgets/plate/plate_input_formatter.dart';
import 'package:carservice_business/core/widgets/plate/plate_keypad.dart';

/// Characters a standard plate has (4 digits + 3 letters); the keypad stops
/// there. The system keyboard ([PlateKeypad]'s ABC) allows up to [_maxLength]
/// for transit, foreign and other non-standard plates.
const _standardLength = 7;
const _maxLength = 12;
const _digitPart = 4;

/// A complete standard plate, as the keypad types it (digits, Cyrillic).
final _standardPlate = RegExp(r'^\d{4}[А-ЯЁӨҮ]{3}$');

/// A licence-plate text field with its own keypad: while focused, digits
/// then Cyrillic letters open under the field instead of the phone's
/// keyboard, switching to letters after the fourth digit. The keypad closes
/// by itself (as «Бэлэн») once it completes a standard plate. Whatever is
/// typed is kept canonical ([PlateInputFormatter]).
class PlateField extends StatefulWidget {
  const PlateField({
    super.key,
    required this.controller,
    this.fieldKey,
    this.decoration = const InputDecoration(),
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.style,
  });

  final TextEditingController controller;

  /// Key of the inner [TextFormField] (tests, `enterText`).
  final Key? fieldKey;
  final InputDecoration decoration;
  final FormFieldValidator<String>? validator;

  /// Called on every change, from the keypad or the system keyboard.
  final ValueChanged<String>? onChanged;

  /// «Бэлэн» on the keypad, or the system keyboard's action key.
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final TextStyle? style;

  @override
  State<PlateField> createState() => _PlateFieldState();
}

class _PlateFieldState extends State<PlateField> {
  final _focus = FocusNode();
  final _keypadKey = GlobalKey();

  /// Letter grid shown (digit pad otherwise).
  bool _letters = false;

  /// The phone's keyboard was asked for (ABC); the keypad stays hidden.
  bool _system = false;

  TextEditingController get _ctrl => widget.controller;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_focusChanged)
      ..dispose();
    super.dispose();
  }

  static int _leadingDigits(String text) {
    var count = 0;
    for (final unit in text.codeUnits) {
      if (unit < 0x30 || unit > 0x39) break;
      count++;
    }
    return count;
  }

  void _focusChanged() {
    if (_focus.hasFocus) {
      setState(() => _letters = _leadingDigits(_ctrl.text) >= _digitPart);
      // Bring the keypad into view once it has laid out.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final keypad = _keypadKey.currentContext;
        if (keypad != null && keypad.mounted) {
          Scrollable.ensureVisible(
            keypad,
            duration: const Duration(milliseconds: 200),
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          );
        }
      });
    } else {
      // The next visit starts on the keypad again.
      setState(() => _system = false);
    }
  }

  TextSelection get _selection {
    final selection = _ctrl.selection;
    return selection.isValid
        ? selection
        : TextSelection.collapsed(offset: _ctrl.text.length);
  }

  void _set(String text, int cursor) {
    _ctrl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: cursor),
    );
    widget.onChanged?.call(text);
  }

  void _insert(String char) {
    final selection = _selection;
    final before = _ctrl.text;
    final text = before.replaceRange(selection.start, selection.end, char);
    if (text.length > _standardLength) {
      HapticFeedback.heavyImpact();
      return;
    }
    HapticFeedback.selectionClick();
    final cursor = selection.start + char.length;
    _set(text, cursor);
    // The last letter of a standard plate, typed at its end: nothing is
    // left to type, so the keypad closes and the plate is submitted.
    if (cursor == text.length && _standardPlate.hasMatch(text)) {
      _done();
      return;
    }
    // The fourth digit completes the number part: on to the letters. Only
    // as it is typed — a later digit after [123] stays on the digits.
    if (!_letters &&
        _leadingDigits(before) < _digitPart &&
        _leadingDigits(text) >= _digitPart) {
      setState(() => _letters = true);
    }
  }

  void _backspace() {
    final selection = _selection;
    if (selection.isCollapsed && selection.start == 0) return;
    final start = selection.isCollapsed ? selection.start - 1 : selection.start;
    final text = _ctrl.text.replaceRange(start, selection.end, '');
    HapticFeedback.selectionClick();
    _set(text, start);
    if (_letters && text.length < _digitPart) {
      setState(() => _letters = false);
    }
  }

  /// «Бэлэн», or a completed standard plate.
  void _done() {
    _focus.unfocus();
    widget.onSubmitted?.call(_ctrl.text);
  }

  void _clear() {
    HapticFeedback.mediumImpact();
    _set('', 0);
    setState(() => _letters = false);
  }

  /// Hands over to the phone's keyboard: refocusing reconnects the field
  /// with the text keyboard type.
  void _useSystemKeyboard() {
    setState(() => _system = true);
    _focus.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _system = true);
      _focus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final keypad = _focus.hasFocus && !_system;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextFormField(
          key: widget.fieldKey,
          controller: _ctrl,
          focusNode: _focus,
          autofocus: widget.autofocus,
          // No system keyboard while the keypad is up.
          keyboardType: _system ? TextInputType.text : TextInputType.none,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          enableSuggestions: false,
          maxLength: _maxLength,
          inputFormatters: const [PlateInputFormatter()],
          onChanged: widget.onChanged,
          onFieldSubmitted: widget.onSubmitted,
          // Like the phone's keyboard, the keypad goes away on a tap
          // elsewhere (taps on the keypad itself are inside, see below).
          onTapOutside: (_) => _focus.unfocus(),
          validator: widget.validator,
          style: widget.style,
          decoration: widget.decoration.copyWith(
            counterText: widget.decoration.counterText ?? '',
          ),
        ),
        // A tap on the keypad is not a tap outside the field.
        TextFieldTapRegion(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 150),
            alignment: Alignment.topCenter,
            child: keypad
                ? PlateKeypad(
                    key: _keypadKey,
                    letters: _letters,
                    onKey: _insert,
                    onBackspace: _backspace,
                    onClear: _clear,
                    onToggle: () => setState(() => _letters = !_letters),
                    onSystemKeyboard: _useSystemKeyboard,
                    onDone: _done,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ),
      ],
    );
  }
}
