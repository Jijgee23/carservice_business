import 'package:flutter/services.dart';

import 'package:carservice_business/core/utils/validators.dart';

/// Keeps a plate field in its canonical form ([normalizePlate]) whatever
/// the input path — system keyboard, paste, hardware keys: upper case, no
/// spaces or dashes, Latin lookalikes as Cyrillic. The cursor stays after
/// the same character it followed.
class PlateInputFormatter extends TextInputFormatter {
  const PlateInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = normalizePlate(newValue.text);
    if (text == newValue.text) return newValue;
    final selection = newValue.selection;
    if (!selection.isValid) {
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    int map(int offset) =>
        normalizePlate(newValue.text.substring(0, offset)).length;
    return TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: map(selection.baseOffset),
        extentOffset: map(selection.extentOffset),
      ),
    );
  }
}
