// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';
import 'package:kotonoha/domain/models/session_item.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/theme/app_theme.dart';
import 'package:kotonoha/ui/core/widgets/answer_option_button.dart';
import 'package:kotonoha/ui/core/widgets/answer_option_grid.dart';
import 'package:kotonoha/ui/quiz/quiz_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #39 — production QuizScreen kana options must stay fully drawable at the
/// phone widths and text scales in the issue, using the bundled Klee One
/// face. Passing "no RenderFlex overflow" is not enough: each glyph's
/// painted box must be at least its unconstrained line height, and the
/// button must enclose that box.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final loader = FontLoader('KleeOne')
      ..addFont(rootBundle.load('assets/fonts/KleeOne-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/KleeOne-SemiBold.ttf'));
    await loader.load();
  });

  final a = kHiraganaGojuon.first;
  const kanaOptions = ['あ', 'い', 'う', 'え'];

  SessionItem soundItem({List<String> options = kanaOptions}) => SessionItem(
    question: QuizQuestion(
      target: a,
      direction: QuizDirection.soundToKana,
      options: options,
      correctIndex: 0,
    ),
    mode: PracticeMode.quickReview,
  );

  SessionItem recallItem() => SessionItem(
    question: QuizQuestion(
      target: a,
      direction: QuizDirection.kanaRecall,
      options: const [],
      correctIndex: 0,
    ),
    mode: PracticeMode.daily,
  );

  testWidgets('320/360 logical px at 1x and 2x keep あいうえ fully drawable', (
    tester,
  ) async {
    final measurements = <String>[];
    for (final width in [320.0, 360.0]) {
      for (final scale in [1.0, 2.0]) {
        await _pumpQuiz(
          tester,
          items: [soundItem()],
          size: Size(width, 640),
          textScale: scale,
        );
        await _revealOptions(tester);
        _expectOptionsUnclipped(
          tester,
          kanaOptions,
          expectedScale: scale,
          kanaFontSize: 34,
        );
        measurements.add(
          _measureLine(tester, width: width, scale: scale, labels: kanaOptions),
        );
        await _dumpCapture(
          tester,
          'quiz_kana_options_${width.toInt()}x640_${scale.toInt()}x.png',
        );
      }
    }
    _writeMeasurements(measurements);
  });

  testWidgets('two- and three-option kana grids stay readable and tappable', (
    tester,
  ) async {
    for (final options in [
      ['あ', 'い'],
      ['あ', 'い', 'う'],
    ]) {
      await _pumpQuiz(
        tester,
        items: [soundItem(options: options)],
        size: const Size(320, 640),
        textScale: 2,
      );
      await _revealOptions(tester);
      _expectOptionsUnclipped(
        tester,
        options,
        expectedScale: 2,
        kanaFontSize: 34,
      );
      await tester.tap(find.widgetWithText(AnswerOptionButton, 'あ'));
      await tester.pump();
      expect(
        tester
            .widget<AnswerOptionButton>(
              find.widgetWithText(AnswerOptionButton, 'あ'),
            )
            .state,
        OptionState.correct,
      );
      expect(find.text(AppStrings.seeResults), findsOneWidget);
    }
  });

  testWidgets('wrong tap still reveals the full correct kana glyph', (
    tester,
  ) async {
    await _pumpQuiz(
      tester,
      items: [soundItem()],
      size: const Size(320, 640),
      textScale: 2,
    );
    await _revealOptions(tester);
    await tester.tap(find.widgetWithText(AnswerOptionButton, 'い'));
    await tester.pump();
    expect(
      tester
          .widget<AnswerOptionButton>(
            find.widgetWithText(AnswerOptionButton, 'い'),
          )
          .state,
      OptionState.wrong,
    );
    expect(
      tester
          .widget<AnswerOptionButton>(
            find.widgetWithText(AnswerOptionButton, 'あ'),
          )
          .state,
      OptionState.revealed,
    );
    _expectOptionsUnclipped(
      tester,
      kanaOptions,
      expectedScale: 2,
      kanaFontSize: 34,
    );
    await _dumpCapture(tester, 'quiz_kana_options_320x640_2x_after_wrong.png');
  });

  testWidgets(
    'kanaRecall is unchanged: no option grid, self-grade still works',
    (tester) async {
      await _pumpQuiz(
        tester,
        items: [recallItem()],
        size: const Size(320, 640),
        textScale: 2,
      );
      expect(find.byType(AnswerOptionGrid), findsNothing);
      expect(find.byType(AnswerOptionButton), findsNothing);
      expect(find.text(a.character), findsOneWidget);
      expect(find.text(AppStrings.iReadUnprompted), findsOneWidget);
      expect(find.text(AppStrings.recallHint), findsOneWidget);

      await tester.tap(find.text(AppStrings.iReadUnprompted));
      await tester.pump();
      expect(find.text(a.romaji), findsOneWidget);
      await tester.tap(find.text(AppStrings.iReadIt));
      await tester.pump();
      expect(find.text(AppStrings.seeResults), findsOneWidget);
    },
  );

  testWidgets('option semantics stay a single kana with a button role', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpQuiz(
      tester,
      items: [soundItem()],
      size: const Size(320, 640),
      textScale: 2,
    );
    await _revealOptions(tester);
    for (final label in kanaOptions) {
      final data = tester
          .getSemantics(find.widgetWithText(AnswerOptionButton, label))
          .getSemanticsData();
      expect(data.label, label);
      expect(data.label.contains('\n'), isFalse);
      expect(
        tester.getSemantics(find.widgetWithText(AnswerOptionButton, label)),
        isSemantics(
          label: label,
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
    }
    handle.dispose();
  });
}

const _captureKey = Key('quiz-option-capture');

Future<void> _pumpQuiz(
  WidgetTester tester, {
  required List<SessionItem> items,
  required Size size,
  required double textScale,
}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final repo = await KanaProgressRepository.load();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<KanaProgressRepository>.value(value: repo),
        ChangeNotifierProvider<ProgressPersistenceController>.value(
          value: ProgressPersistenceController(
            kanaFlush: repo.flushPending,
            kanjiFlush: () async {},
            wordFlush: () async {},
          ),
        ),
        Provider<SpeechService>.value(value: const SilentSpeechService()),
        Provider<AnalyticsLog>.value(value: InMemoryAnalyticsLog()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: RepaintBoundary(
            key: _captureKey,
            child: QuizScreen(key: UniqueKey(), items: items, title: 'probe'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _revealOptions(WidgetTester tester) async {
  expect(find.byType(AnswerOptionGrid), findsOneWidget);
  final buttons = find.byType(AnswerOptionButton);
  expect(buttons, findsWidgets);
  await tester.ensureVisible(buttons.first);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void _expectOptionsUnclipped(
  WidgetTester tester,
  List<String> labels, {
  required double expectedScale,
  required double kanaFontSize,
}) {
  final rects = <Rect>[];
  for (final label in labels) {
    final button = find.widgetWithText(AnswerOptionButton, label);
    expect(button, findsOneWidget);
    expect(button.hitTestable(), findsOneWidget);

    final textFinder = find.descendant(of: button, matching: find.text(label));
    final paragraph = tester.renderObject<RenderParagraph>(textFinder);
    expect(
      paragraph.textScaler.scale(kanaFontSize),
      closeTo(kanaFontSize * expectedScale, 0.05),
      reason: '$label must honor TextScaler $expectedScale, not clamp it',
    );

    final painter = TextPainter(
      text: paragraph.text,
      textDirection: paragraph.textDirection,
      textScaler: paragraph.textScaler,
      textAlign: paragraph.textAlign,
      locale: paragraph.locale,
      strutStyle: paragraph.strutStyle,
      textHeightBehavior: paragraph.textHeightBehavior,
      textWidthBasis: paragraph.textWidthBasis,
    )..layout();

    expect(
      paragraph.size.height + 0.5,
      greaterThanOrEqualTo(painter.height),
      reason:
          '$label clipped: box=${paragraph.size.height.toStringAsFixed(1)} '
          'natural=${painter.height.toStringAsFixed(1)}',
    );
    expect(
      paragraph.size.width + 0.5,
      greaterThanOrEqualTo(painter.width),
      reason:
          '$label horizontally clipped: box=${paragraph.size.width} '
          'natural=${painter.width}',
    );

    final textRect = tester.getRect(textFinder);
    final buttonRect = tester.getRect(button);
    expect(
      buttonRect.inflate(0.5).contains(textRect.topLeft) &&
          buttonRect.inflate(0.5).contains(textRect.bottomRight),
      isTrue,
      reason: '$label text $textRect escapes button $buttonRect',
    );
    rects.add(buttonRect);
  }

  for (var i = 0; i < rects.length; i++) {
    for (var j = i + 1; j < rects.length; j++) {
      expect(
        rects[i].overlaps(rects[j]),
        isFalse,
        reason: 'options ${labels[i]} and ${labels[j]} overlap',
      );
    }
  }
}

String _measureLine(
  WidgetTester tester, {
  required double width,
  required double scale,
  required List<String> labels,
}) {
  final parts = <String>['${width.toInt()}x640 @${scale}x'];
  for (final label in labels) {
    final textFinder = find.descendant(
      of: find.widgetWithText(AnswerOptionButton, label),
      matching: find.text(label),
    );
    final paragraph = tester.renderObject<RenderParagraph>(textFinder);
    final painter = TextPainter(
      text: paragraph.text,
      textDirection: paragraph.textDirection,
      textScaler: paragraph.textScaler,
    )..layout();
    final button = tester.getRect(
      find.widgetWithText(AnswerOptionButton, label),
    );
    parts.add(
      '$label box=${paragraph.size.height.toStringAsFixed(1)} '
      'natural=${painter.height.toStringAsFixed(1)} '
      'button=${button.height.toStringAsFixed(1)}',
    );
  }
  return parts.join(' | ');
}

void _writeMeasurements(List<String> lines) {
  final artifacts = Directory('/opt/cursor/artifacts');
  if (!artifacts.existsSync()) {
    return;
  }
  File('${artifacts.path}/quiz_kana_option_measurements.txt')
      .writeAsStringSync('${lines.join('\n')}\n');
}

Future<void> _dumpCapture(WidgetTester tester, String filename) async {
  final artifacts = Directory('/opt/cursor/artifacts');
  if (!artifacts.existsSync()) {
    return;
  }
  final bytes = await _capturePng(tester, find.byKey(_captureKey));
  File('${artifacts.path}/$filename').writeAsBytesSync(bytes);
}

Future<Uint8List> _capturePng(WidgetTester tester, Finder finder) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(finder);
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 2));
  final data = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.png),
  );
  return data!.buffer.asUint8List();
}
