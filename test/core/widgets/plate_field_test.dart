import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/widgets/plate/plate_field.dart';

const _field = ValueKey('plate');
final _keypad = find.byKey(const ValueKey('plate_keypad'));

Finder _key(String name) => find.byKey(ValueKey('plate_key_$name'));

class _Harness {
  final controller = TextEditingController();
  final changes = <String>[];
  final submitted = <String>[];
}

Future<_Harness> _pump(
  WidgetTester tester, {
  double width = 375,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.reset);
  final h = _Harness();
  addTearDown(h.controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 900),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              PlateField(
                fieldKey: _field,
                controller: h.controller,
                onChanged: h.changes.add,
                onSubmitted: h.submitted.add,
              ),
              const SizedBox(height: 16),
              const TextField(key: ValueKey('other')),
            ],
          ),
        ),
      ),
    ),
  );
  return h;
}

TextField _textField(WidgetTester tester) => tester.widget<TextField>(
  find.descendant(of: find.byKey(_field), matching: find.byType(TextField)),
);

Future<void> _tapKeys(WidgetTester tester, String keys) async {
  for (final char in keys.split('')) {
    await tester.tap(_key(char));
    await tester.pump();
  }
}

void main() {
  testWidgets('focus opens the keypad instead of the phone keyboard', (
    tester,
  ) async {
    await _pump(tester);
    expect(_keypad, findsNothing);

    await tester.tap(find.byKey(_field));
    await tester.pumpAndSettle();
    expect(_keypad, findsOneWidget);
    expect(_textField(tester).keyboardType, TextInputType.none);
    expect(tester.takeException(), isNull);
  });

  testWidgets('digits first, letters after the fourth, back on erase', (
    tester,
  ) async {
    final h = await _pump(tester);
    await tester.tap(find.byKey(_field));
    await tester.pumpAndSettle();

    await _tapKeys(tester, '123');
    expect(_key('У'), findsNothing);
    await _tapKeys(tester, '4');
    expect(_key('1'), findsNothing);
    await _tapKeys(tester, 'УБ');
    expect(h.controller.text, '1234УБ');
    expect(h.changes.last, '1234УБ');
    expect(h.changes, hasLength(6));

    for (var i = 0; i < 3; i++) {
      await tester.tap(_key('backspace'));
      await tester.pump();
    }
    expect(h.controller.text, '123');
    expect(_key('1'), findsOneWidget);
  });

  testWidgets('a completed standard plate closes the keypad and submits', (
    tester,
  ) async {
    final h = await _pump(tester);
    await tester.tap(find.byKey(_field));
    await tester.pumpAndSettle();

    await _tapKeys(tester, '1234УБА');
    await tester.pumpAndSettle();
    expect(h.controller.text, '1234УБА');
    expect(h.submitted, ['1234УБА']);
    expect(_keypad, findsNothing);
    expect(_textField(tester).focusNode!.hasFocus, isFalse);
  });

  testWidgets('digits kept on by hand stay digits, up to seven', (
    tester,
  ) async {
    final h = await _pump(tester);
    await tester.tap(find.byKey(_field));
    await tester.pumpAndSettle();

    await _tapKeys(tester, '1234');
    await tester.tap(_key('mode'));
    await tester.pump();
    await _tapKeys(tester, '567');
    expect(h.controller.text, '1234567');
    // Not a standard plate: the keypad stays, and adds no eighth character.
    expect(_keypad, findsOneWidget);
    await _tapKeys(tester, '8');
    expect(h.controller.text, '1234567');
    expect(h.submitted, isEmpty);
  });

  testWidgets('a key goes in at the cursor', (tester) async {
    final h = await _pump(tester);
    await tester.tap(find.byKey(_field));
    await tester.pumpAndSettle();
    h.controller.value = const TextEditingValue(
      text: '1234УА',
      selection: TextSelection.collapsed(offset: 5),
    );
    await tester.pump();
    // Set from outside, so switch to the letters by hand.
    await tester.tap(_key('mode'));
    await tester.pump();
    await _tapKeys(tester, 'Б');
    expect(h.controller.text, '1234УБА');
    expect(h.controller.selection.baseOffset, 6);
    // A fix in the middle is not «done»: the keypad stays.
    expect(_keypad, findsOneWidget);
    expect(h.submitted, isEmpty);
  });

  testWidgets('long-press on erase clears the plate', (tester) async {
    final h = await _pump(tester);
    await tester.tap(find.byKey(_field));
    await tester.pumpAndSettle();
    await _tapKeys(tester, '1234У');
    await tester.longPress(_key('backspace'));
    await tester.pump();
    expect(h.controller.text, isEmpty);
    expect(_key('1'), findsOneWidget);
  });

  testWidgets('ABC hands over to the phone keyboard, still canonical', (
    tester,
  ) async {
    final h = await _pump(tester);
    await tester.tap(find.byKey(_field));
    await tester.pumpAndSettle();

    await tester.tap(_key('abc'));
    await tester.pumpAndSettle();
    expect(_keypad, findsNothing);
    expect(_textField(tester).keyboardType, TextInputType.text);
    expect(_textField(tester).focusNode!.hasFocus, isTrue);

    await tester.enterText(find.byKey(_field), '1234 abc');
    await tester.pump();
    expect(h.controller.text, '1234АВС');
  });

  testWidgets('«Бэлэн» submits and closes the keypad', (tester) async {
    final h = await _pump(tester);
    await tester.tap(find.byKey(_field));
    await tester.pumpAndSettle();
    await _tapKeys(tester, '1234УБ');

    await tester.tap(_key('done'));
    await tester.pumpAndSettle();
    expect(h.submitted, ['1234УБ']);
    expect(_keypad, findsNothing);
    expect(_textField(tester).focusNode!.hasFocus, isFalse);
  });

  testWidgets('a tap elsewhere closes the keypad', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(_field));
    await tester.pumpAndSettle();
    expect(_keypad, findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('other')));
    await tester.pumpAndSettle();
    expect(_keypad, findsNothing);
  });

  testWidgets('the keypad fits a 320dp phone with large text', (tester) async {
    await _pump(tester, width: 320, textScale: 1.3);
    await tester.tap(find.byKey(_field));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await _tapKeys(tester, '1234');
    expect(_key('Ө'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
