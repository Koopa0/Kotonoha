// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/ui/core/answer_option_state.dart';
import 'package:kotonoha/ui/core/widgets/answer_option_button.dart';

void main() {
  Future<void> pumpOption(
    WidgetTester tester, {
    required OptionState state,
    VoidCallback? onTap,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 100,
            child: AnswerOptionButton(
              label: 'あ',
              state: state,
              fontSize: 30,
              onTap: onTap,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('AnswerOptionButton semantics', () {
    testWidgets(
      'reads the kana exactly once in idle, correct, wrong, and revealed',
      (tester) async {
        final handle = tester.ensureSemantics();

        const states = [
          OptionState.idle,
          OptionState.correct,
          OptionState.wrong,
          OptionState.revealed,
        ];

        for (final state in states) {
          await pumpOption(
            tester,
            state: state,
            onTap: state == OptionState.idle ? () {} : null,
          );

          final data = tester
              .getSemantics(find.byType(AnswerOptionButton))
              .getSemanticsData();
          expect(
            data.label,
            'あ',
            reason: 'state=${state.name} must not merge a duplicate Text label',
          );
          expect(data.label.contains('\n'), isFalse);
        }
        handle.dispose();
      },
    );

    testWidgets('keeps a button role and exposes enabled vs disabled', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await pumpOption(tester, state: OptionState.idle, onTap: () {});
      expect(
        tester.getSemantics(find.byType(AnswerOptionButton)),
        isSemantics(
          label: 'あ',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );

      await pumpOption(tester, state: OptionState.correct);
      expect(
        tester.getSemantics(find.byType(AnswerOptionButton)),
        isSemantics(
          label: 'あ',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          hasTapAction: false,
        ),
      );
      handle.dispose();
    });

    testWidgets('idle tap still fires; disabled states do not', (tester) async {
      var taps = 0;
      await pumpOption(tester, state: OptionState.idle, onTap: () => taps++);
      await tester.tap(find.byType(AnswerOptionButton));
      expect(taps, 1);

      await pumpOption(tester, state: OptionState.wrong);
      await tester.tap(find.byType(AnswerOptionButton));
      expect(taps, 1);
    });
  });
}
