// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/lesson.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/speak_button.dart';
import 'package:kotonoha/ui/quiz/quiz_screen.dart';
import 'package:kotonoha/ui/study/study_viewmodel.dart';
import 'package:provider/provider.dart';

/// Teaches one lesson's kana one card at a time (calm flashcards with audio),
/// then sends the learner into a test scoped to that lesson.
///
/// A thin View over [StudyViewModel]: it owns the pager, the speaker and
/// the lifecycle listener, renders, and navigates. The pass (encode /
/// recap), the card in view, the reveal and how the row test is composed
/// are the ViewModel's.
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
  late final StudyViewModel _vm;
  late final SpeechService _speech;
  late final AppLifecycleListener _lifecycle;
  int? _ownedPlay;
  bool _playable = true;

  @override
  void initState() {
    super.initState();
    _vm = StudyViewModel(
      lesson: widget.lesson,
      kana: context.read<KanaProgressRepository>(),
    );
    _speech = context.read<SpeechService>();
    _lifecycle = AppLifecycleListener(
      onInactive: _abandonOwnedPlayback,
      onHide: _abandonOwnedPlayback,
      onPause: _abandonOwnedPlayback,
      onDetach: _abandonOwnedPlayback,
      onResume: _onResumed,
    );
    _playable = _foreground;
    // Auto-play the first card once the first frame is up (auditory learner).
    WidgetsBinding.instance.addPostFrameCallback((_) => _speakCurrent());
  }

  bool get _foreground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  void _onResumed() {
    _playable = true;
  }

  void _abandonOwnedPlayback() {
    _playable = false;
    final generation = _ownedPlay;
    _ownedPlay = null;
    if (generation != null) {
      unawaited(_speech.stop(generation: generation));
    }
  }

  void _speakCurrent() {
    if (!mounted || !_playable || !_foreground) return;
    unawaited(_speech.speak(_vm.current.character));
    _ownedPlay = _speech.generation;
  }

  void _onPageChanged(int i) {
    _vm.showCard(i);
    // The recap is a silent recall — don't auto-speak the answer; the learner
    // hears it on reveal (or via the speak button) instead.
    if (!_vm.isRecap) _speakCurrent();
  }

  void _next() {
    _controller.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  /// Enter the optional recall lap: the ViewModel walks the SAME row again
  /// from the top with romaji hidden; the pager follows it there.
  void _enterRecap() {
    _vm.enterRecap();
    _controller.jumpToPage(0);
  }

  /// Confirm a recap card: reveal the romaji and speak the kana.
  void _reveal() {
    _vm.reveal();
    _speakCurrent();
  }

  void _startTest() {
    Navigator.of(context).pushReplacement(
      QuizScreen.route(
        questions: _vm.composeTest(),
        title: widget.lesson.title,
        mode: PracticeMode.lessonTest,
        lesson: widget.lesson,
      ),
    );
  }

  /// The footer button(s). The only new branch on the default path is the last
  /// ENCODE card, which offers a choice: go to the test now (primary, = today's
  /// behaviour) or take the optional recall lap (secondary). Every other card —
  /// and the last recap card — keeps a single full-width button.
  Widget _footer() {
    if (_vm.offersRecap) {
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
    final isRecapLast = _vm.isRecap && _vm.isLast;
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
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.lesson.title)),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _vm,
          builder: (context, _) => _body(),
        ),
      ),
    );
  }

  Widget _body() {
    final cards = _vm.cards;
    return Column(
      children: [
        const SizedBox(height: 8),
        Text(
          AppStrings.itemProgress(_vm.index + 1, cards.length),
          style: const TextStyle(
            color: AppColors.inkMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: PageView.builder(
            controller: _controller,
            onPageChanged: _onPageChanged,
            itemCount: cards.length,
            itemBuilder: (context, i) => _StudyCard(
              kana: cards[i],
              recall: _vm.isRecap,
              revealed: i == _vm.index && _vm.isRevealed,
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
