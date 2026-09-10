// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';
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

/// 手解き runs in two passes: an honest ENCODE (every glyph shown with its
/// romaji + audio — you cannot recall a kana you have never met), then an
/// optional, self-paced RECAP (glyph only, romaji behind a tap) so the row test
/// is no longer the first time the learner retrieves anything. The recap is
/// opt-in — the default is straight to 測驗這一行 — and is never graded or scored.
enum _Phase { encode, recap }

class _StudyScreenState extends State<StudyScreen> {
  final PageController _controller = PageController();
  late final SpeechService _speech;
  late final AppLifecycleListener _lifecycle;
  int? _ownedPlay;
  int _index = 0;
  _Phase _phase = _Phase.encode;
  // Recap-only: whether the current card's romaji is revealed. Held in the State
  // and reset on every page change (mirrors reading_screen), so the
  // PageView.builder cards can stay stateless.
  bool _revealed = false;

  List<Kana> get _kana => widget.lesson.kana;
  bool get _isLast => _index >= _kana.length - 1;

  @override
  void initState() {
    super.initState();
    _speech = context.read<SpeechService>();
    _lifecycle = AppLifecycleListener(
      onInactive: _abandonOwnedPlayback,
      onHide: _abandonOwnedPlayback,
      onPause: _abandonOwnedPlayback,
      onDetach: _abandonOwnedPlayback,
    );
    // Auto-play the first card once the first frame is up (auditory learner).
    WidgetsBinding.instance.addPostFrameCallback((_) => _speakCurrent());
  }

  void _abandonOwnedPlayback() {
    final generation = _ownedPlay;
    _ownedPlay = null;
    if (generation != null) {
      unawaited(_speech.stop(generation: generation));
    }
  }

  void _speakCurrent() {
    if (!mounted) return;
    unawaited(_speech.speak(_kana[_index].character));
    _ownedPlay = _speech.generation;
  }

  void _onPageChanged(int i) {
    setState(() {
      _index = i;
      _revealed = false;
    });
    // The recap is a silent recall — don't auto-speak the answer; the learner
    // hears it on reveal (or via the speak button) instead.
    if (_phase == _Phase.encode) _speakCurrent();
  }

  void _next() {
    _controller.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  /// Enter the optional recall lap: walk the SAME row again from the top with
  /// romaji hidden behind a tap. Reachable only from the last encode card, so
  /// every recap glyph has already been met with its romaji + audio.
  void _enterRecap() {
    setState(() {
      _phase = _Phase.recap;
      _index = 0;
      _revealed = false;
    });
    _controller.jumpToPage(0);
  }

  /// Confirm a recap card: reveal the romaji and speak the kana.
  void _reveal() {
    setState(() => _revealed = true);
    _speakCurrent();
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

  /// The footer button(s). The only new branch on the default path is the last
  /// ENCODE card, which offers a choice: go to the test now (primary, = today's
  /// behaviour) or take the optional recall lap (secondary). Every other card —
  /// and the last recap card — keeps a single full-width button.
  Widget _footer() {
    if (_phase == _Phase.encode && _isLast) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                side: const BorderSide(color: AppColors.hairline),
                foregroundColor: AppColors.ink,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: _enterRecap,
              child: const Text(AppStrings.studyReviewOnce),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
              ),
              onPressed: _startTest,
              child: const Text(AppStrings.testThisRow),
            ),
          ),
        ],
      );
    }
    final isRecapLast = _phase == _Phase.recap && _isLast;
    return FilledButton(
      onPressed: isRecapLast ? _startTest : _next,
      child: Text(isRecapLast ? AppStrings.testThisRow : AppStrings.nextCard),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _abandonOwnedPlayback();
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
              AppStrings.itemProgress(_index + 1, _kana.length),
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
                itemBuilder: (context, i) => _StudyCard(
                  kana: _kana[i],
                  recall: _phase == _Phase.recap,
                  revealed: i == _index && _revealed,
                  onReveal: _reveal,
                  onSpeak: _speakCurrent,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: _footer(),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudyCard extends StatelessWidget {
  const _StudyCard({
    required this.kana,
    this.recall = false,
    this.revealed = false,
    this.onReveal,
    this.onSpeak,
  }) : assert(
         !recall || onReveal != null,
         'a recall card needs an onReveal callback',
       );

  final Kana kana;

  /// In the recall lap the romaji is withheld behind a tap; in the encode pass
  /// (the default) it is always shown — today's card, verbatim.
  final bool recall;
  final bool revealed;
  final VoidCallback? onReveal;
  final VoidCallback? onSpeak;

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
            ..._body(),
            const Spacer(),
            if (!recall)
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

  /// ENCODE (or a revealed recap card) shows the romaji + speak button outright.
  /// An unrevealed RECAP card withholds them behind 看答案 — the learner reads
  /// the glyph in their head first, then confirms.
  List<Widget> _body() {
    if (!recall || revealed) {
      return [
        Text(
          kana.romaji,
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w600,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(height: 12),
        SpeakButton(text: kana.character, size: 34, onPlay: onSpeak),
      ];
    }
    return [
      const Text(
        AppStrings.readPrompt,
        style: TextStyle(color: AppColors.inkMuted, fontSize: 15),
      ),
      const SizedBox(height: 16),
      TextButton(
        onPressed: onReveal,
        style: TextButton.styleFrom(foregroundColor: AppColors.accent),
        child: const Text(AppStrings.revealAnswer),
      ),
    ];
  }
}
