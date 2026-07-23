// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/lesson.dart';
import 'package:kotonoha/domain/models/quiz_result.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/quiz_engine.dart';
import 'package:kotonoha/domain/use_cases/study_set.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/lessons/lessons_screen.dart';
import 'package:kotonoha/ui/quiz/quiz_screen.dart';
import 'package:provider/provider.dart';

/// End-of-session screen. For a plain review it shows score + missed kana; for
/// a lesson test it also decides pass/fail and marks the lesson learned.
class QuizResultScreen extends StatefulWidget {
  const QuizResultScreen({
    required this.result,
    super.key,
    this.lesson,
    this.onAgain,
  });

  final QuizResult result;
  final Lesson? lesson;

  /// When set (only for repeatable non-lesson drills — 今日の稽古 / 目利き), a
  /// calm "再来一回" composes a fresh session. Null hides it entirely.
  final VoidCallback? onAgain;

  static Route<void> route(
    QuizResult result, {
    Lesson? lesson,
    VoidCallback? onAgain,
  }) {
    return MaterialPageRoute<void>(
      builder: (_) =>
          QuizResultScreen(result: result, lesson: lesson, onAgain: onAgain),
    );
  }

  @override
  State<QuizResultScreen> createState() => _QuizResultScreenState();
}

class _QuizResultScreenState extends State<QuizResultScreen> {
  bool _lessonPassed = false;

  bool get _isLesson => widget.lesson != null;

  @override
  void initState() {
    super.initState();
    if (_isLesson) {
      _lessonPassed = Lessons.isPassed(widget.lesson!, widget.result);
      if (_lessonPassed) {
        // Persist after the first frame to avoid notifying during build; the
        // app-scoped owner observes the write so a failure survives even if
        // this screen is popped before it settles.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          context.read<ProgressPersistenceController>().trackKana(
            context.read<KanaProgressRepository>().markUnitLearned(
              widget.lesson!.id,
            ),
          );
        });
      }
    }
  }

  void _retryLesson() {
    final store = context.read<KanaProgressRepository>();
    final lesson = widget.lesson!;
    final rng = Random();
    final learned = Lessons.fromKana(store.allKana)
        .where(
          (l) =>
              l.id != lesson.id &&
              l.script == lesson.script &&
              store.isUnitLearned(l.id),
        )
        .expand((l) => l.kana)
        .toList();
    final targets = Lessons.testTargets(lesson, learned, rng);
    final questions = const QuizEngine().generateSession(
      targets: targets,
      allKana: store.kanaForScript(lesson.script),
      length: targets.length,
      random: rng,
    );
    Navigator.of(context).pushReplacement(
      QuizScreen.route(
        questions: questions,
        title: lesson.title,
        mode: PracticeMode.lessonTest,
        lesson: lesson,
      ),
    );
  }

  void _reviewMissed(List<Kana> missed) {
    final store = context.read<KanaProgressRepository>();
    final questions = const QuizEngine().generateSession(
      targets: missed,
      // learned only; the engine scopes distractors per target script.
      allKana: StudySet.reviewPool(store),
      length: missed.length,
      random: Random(),
    );
    Navigator.of(context).pushReplacement(
      QuizScreen.route(
        questions: questions,
        title: AppStrings.quizTitleMissed,
        mode: PracticeMode.missed,
      ),
    );
  }

  void _backToLessons() {
    Navigator.of(
      context,
    ).popUntil((r) => r.settings.name == LessonsScreen.routeName || r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final missed = result.missedKana;
    final perfect = missed.isEmpty;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(AppStrings.sessionComplete),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            const SizedBox(height: 8),
            // 凪 — the session settles in stillness. A komorebi glow, then the
            // close line (which never varies with how it went), and the score
            // recedes to a quiet footnote — never the reward.
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppColors.komorebi.withValues(alpha: 0.30),
                          AppColors.komorebi.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _note(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 19,
                      height: 1.5,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${result.correctCount}/${result.total}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            if (!perfect) ...[
              const Text(
                AppStrings.missedKana,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final k in missed)
                    _MissedChip(char: k.character, romaji: k.romaji),
                ],
              ),
              const SizedBox(height: 28),
            ],
            ..._actions(missed),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions(List<Kana> missed) {
    if (_isLesson) {
      return [
        if (!_lessonPassed)
          FilledButton(
            onPressed: _retryLesson,
            child: const Text(AppStrings.retryLesson),
          ),
        if (!_lessonPassed) const SizedBox(height: 12),
        _outlined(AppStrings.backToLessons, _backToLessons),
      ];
    }
    return [
      if (missed.isNotEmpty) ...[
        FilledButton(
          onPressed: () => _reviewMissed(missed),
          child: Text(AppStrings.reviewMissedKana(missed.length)),
        ),
        const SizedBox(height: 12),
      ],
      _outlined(
        AppStrings.done,
        () => Navigator.of(context).popUntil((r) => r.isFirst),
      ),
      // Opt-in "one more round" — last, low-emphasis, never the default.
      if (widget.onAgain != null) ...[
        const SizedBox(height: 12),
        _outlined(AppStrings.practiceAgain, widget.onAgain!),
      ],
    ];
  }

  Widget _outlined(String label, VoidCallback onPressed) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        side: const BorderSide(color: AppColors.hairline),
        foregroundColor: AppColors.ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }

  /// The leading line. A lesson keeps an honest pass / not-yet gate (it decides
  /// whether the row is learned); every other session closes on the same calm,
  /// performance-invariant line — the score never tiers the words.
  String _note() {
    if (_isLesson) {
      return _lessonPassed
          ? AppStrings.lessonPassed
          : AppStrings.lessonNotPassed;
    }
    return AppStrings.sessionCloseLine;
  }
}

class _MissedChip extends StatelessWidget {
  const _MissedChip({required this.char, required this.romaji});

  final String char;
  final String romaji;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            char,
            style: const TextStyle(fontSize: 26, color: AppColors.ink),
          ),
          const SizedBox(width: 8),
          Text(
            romaji,
            style: const TextStyle(color: AppColors.inkMuted, fontSize: 15),
          ),
        ],
      ),
    );
  }
}
