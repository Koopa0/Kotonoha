// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/lesson.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/quiz_engine.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/speak_button.dart';
import 'package:kotonoha/ui/quiz/quiz_screen.dart';
import 'package:provider/provider.dart';

/// Teaches one lesson's kana one card at a time (calm flashcards with audio),
/// then sends the learner into a test scoped to that lesson.
class StudyScreen extends StatefulWidget {
  const StudyScreen({required this.lesson, super.key});

  final Lesson lesson;

  static Route<void> route(Lesson lesson) =>
      MaterialPageRoute<void>(builder: (_) => StudyScreen(lesson: lesson));

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  final PageController _controller = PageController();
  int _index = 0;

  List<Kana> get _kana => widget.lesson.kana;
  bool get _isLast => _index >= _kana.length - 1;

  @override
  void initState() {
    super.initState();
    // Auto-play the first card once the first frame is up (auditory learner).
    WidgetsBinding.instance.addPostFrameCallback((_) => _speakCurrent());
  }

  void _speakCurrent() {
    context.read<SpeechService>().speak(_kana[_index].character);
  }

  void _onPageChanged(int i) {
    setState(() => _index = i);
    _speakCurrent();
  }

  void _next() {
    if (_isLast) {
      _startTest();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    }
  }

  void _startTest() {
    final store = context.read<KanaProgressRepository>();
    final rng = Random();
    final learned = _learnedOtherKana(store);
    final targets = Lessons.testTargets(widget.lesson, learned, rng);
    final questions = const QuizEngine().generateSession(
      targets: targets,
      // Distractors stay within the lesson's own script.
      allKana: store.kanaForScript(widget.lesson.script),
      length: targets.length,
      random: rng,
    );
    Navigator.of(context).pushReplacement(
      QuizScreen.route(
        questions: questions,
        title: widget.lesson.title,
        mode: PracticeMode.lessonTest,
        lesson: widget.lesson,
      ),
    );
  }

  /// Kana from previously-learned rows (excluding this one), for interleaving.
  List<Kana> _learnedOtherKana(KanaProgressRepository store) {
    return Lessons.fromKana(store.allKana)
        .where(
          (l) =>
              l.id != widget.lesson.id &&
              l.script == widget.lesson.script &&
              store.isUnitLearned(l.id),
        )
        .expand((l) => l.kana)
        .toList();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.lesson.title)),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            Text(
              AppStrings.lessonProgress(_index + 1, _kana.length),
              style: const TextStyle(
                color: AppColors.inkMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: _onPageChanged,
                itemCount: _kana.length,
                itemBuilder: (context, i) => _StudyCard(kana: _kana[i]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: FilledButton(
                onPressed: _next,
                child: Text(
                  _isLast ? AppStrings.testThisRow : AppStrings.nextCard,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudyCard extends StatelessWidget {
  const _StudyCard({required this.kana});

  final Kana kana;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            Text(
              kana.character,
              style: const TextStyle(
                fontSize: 140,
                height: 1.0,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              kana.romaji,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w600,
                color: AppColors.skyBlue,
              ),
            ),
            const SizedBox(height: 12),
            SpeakButton(text: kana.character, size: 34),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                AppStrings.tapToHear,
                style: TextStyle(color: AppColors.inkMuted, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
