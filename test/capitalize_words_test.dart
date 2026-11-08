import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trainhub/features/fitpro/widgets/fit_widgets.dart';

void main() {
  group('capitalizeWords', () {
    test('latin', () {
      expect(capitalizeWords('nodir najmiddinov'), 'Nodir Najmiddinov');
    });

    test('cyrillic and hyphenated', () {
      expect(capitalizeWords('иван петров'), 'Иван Петров');
      expect(capitalizeWords('анна-мария'), 'Анна-Мария');
      expect(capitalizeWords('ёжиков'), 'Ёжиков');
    });

    test('keeps the rest of the word as typed', () {
      expect(capitalizeWords('mcDonald'), 'McDonald');
      expect(capitalizeWords("o'g'li"), "O'g'li");
    });

    test('letters whose upper case changes length are kept', () {
      expect(capitalizeWords('ßtraße'), 'ßtraße');
    });

    test('scripts without case are untouched', () {
      expect(capitalizeWords('李 小龙'), '李 小龙');
    });
  });

  group('CapitalizeWordsFormatter', () {
    const formatter = CapitalizeWordsFormatter();

    test('capitalizes and keeps cursor', () {
      final result = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: 'nodir n', selection: TextSelection.collapsed(offset: 7)),
      );
      expect(result.text, 'Nodir N');
      expect(result.selection.baseOffset, 7);
    });

    test('does not touch IME composing text', () {
      const composing = TextEditingValue(
        text: 'nodir',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 0, end: 5),
      );
      expect(formatter.formatEditUpdate(TextEditingValue.empty, composing).text, 'nodir');
    });
  });

  testWidgets('FitField: names capitalize, email has no autocorrect/suggestions', (tester) async {
    final name = TextEditingController();
    final email = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              FitField(label: 'Имя', controller: name, textCapitalization: TextCapitalization.words),
              FitField(label: 'Email', controller: email, keyboardType: TextInputType.emailAddress),
            ],
          ),
        ),
      ),
    );

    final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[0].textCapitalization, TextCapitalization.words);
    expect(fields[1].keyboardType, TextInputType.emailAddress);
    expect(fields[1].autocorrect, isFalse);
    expect(fields[1].enableSuggestions, isFalse);
    expect(fields[1].textCapitalization, TextCapitalization.none);
    expect(fields[1].smartDashesType, SmartDashesType.disabled);
    expect(fields[1].smartQuotesType, SmartQuotesType.disabled);

    await tester.enterText(find.byType(TextField).at(0), 'nodir najmiddinov');
    expect(name.text, 'Nodir Najmiddinov');

    await tester.enterText(find.byType(TextField).at(1), 'Nodir.Test@Gmail.com');
    expect(email.text, 'Nodir.Test@Gmail.com');
  });
}
