// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/kanji/domain/models/kanji_unit.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_prompt.dart';
import 'package:kotonoha/kanji/ui/kanji_quiz_viewmodel.dart';
import 'package:kotonoha/ui/core/answer_option_state.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/answer_option_button.dart';
import 'package:kotonoha/ui/core/widgets/answer_option_grid.dart';
import 'package:kotonoha/ui/core/widgets/session_summary.dart';
import 'package:kotonoha/ui/core/widgets/speak_button.dart';
import 'package:provider/provider.dart';

/// 漢字の声 — honest kanji reading, drilled in WORDS. A never-met unit
/// (学校【がっこう】) is TAUGHT ear-first: hear it, watch the kana ink in, and see
/// the sentence it lives in. A met unit is RECALLed cold — choose its reading
/// from the written run *in its sentence*, so 日 in 帰国の日 is not the same
/// question as 日 in 毎日歩く. The wrong options are what reading it character
/// by character would produce (学校 → がくこう), or another taught reading of
/// the same run. The meaning is never glossed while asking: a 漢字-literate
/// reader already owns it, and the only thing missing is the sound. No score
/// on screen, no clock; the per-unit Leitner advances either way.
///
/// A thin View over [KanjiQuizViewModel]: it owns the speaker (the owned
/// utterance, whether the app may play), the lifecycle listener, rendering
/// and navigation. The route (teach vs. recall), the question, the verdict
/// and every schedule or analytics write are the ViewModel's.
class KanjiQuizScreen extends StatefulWidget {
  KanjiQuizScreen({
    required this.units,
    required this.title,
    Random? rng,
    super.key,
  }) : rng = rng ?? Random();

  final List<KanjiUnit> units;
  final String title;

  /// Injected so option order is deterministic under test.
  final Random rng;

  /// The example-sentence stem shown on a recall beat *before* the answer.
  static const Key promptStemKey = Key('kanjiPromptStem');

  static Route<void> route(List<KanjiUnit> units, String title) =>
      MaterialPageRoute<void>(
        builder: (_) => KanjiQuizScreen(units: units, title: title),
      );

  @override
  State<KanjiQuizScreen> createState() => _KanjiQuizScreenState();
}

class _KanjiQuizScreenState extends State<KanjiQuizScreen> {
  late final KanjiQuizViewModel _vm;
  late final SpeechService _speech;
  late final AppLifecycleListener _lifecycle;
  int? _ownedPlay;
  bool _playable = true;
  int _shownIndex = 0;
  bool _shownAnswered = false;

  String get _spoken => _vm.current.reading;

  @override
  void initState() {
    super.initState();
    _vm = KanjiQuizViewModel(
      units: widget.units,
      kanji: context.read<KanjiReadingRepository>(),
      persistence: context.read<ProgressPersistenceController>(),
      analytics: context.read<AnalyticsLog>(),
      sessionId: DateTime.now().millisecondsSinceEpoch.toString(),
      rng: widget.rng,
    )..addListener(_onChanged);
    _speech = context.read<SpeechService>();
    _lifecycle = AppLifecycleListener(
      onInactive: _abandonOwnedPlayback,
      onHide: _abandonOwnedPlayback,
      onPause: _abandonOwnedPlayback,
      onDetach: _abandonOwnedPlayback,
      onResume: _onResumed,
    );
    _playable = _foreground;
    WidgetsBinding.instance.addPostFrameCallback((_) => _speakIfTeach());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _abandonOwnedPlayback();
    _vm.removeListener(_onChanged);
    _vm.dispose();
    super.dispose();
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

  // Ear-first: the reading is heard on a teach beat. Recall stays silent until
  // the learner has chosen (cold), so the sound can't give the answer away.
  void _speakIfTeach() {
    if (!_vm.isTeach || !mounted) return;
    _speak(_spoken);
  }

  void _speak(String text) {
    if (!mounted || !_playable || !_foreground) return;
    unawaited(_speech.speak(text));
    _ownedPlay = _speech.generation;
  }

  /// Session transitions are the ViewModel's; what they mean for the
  /// utterance is the view's. A new unit speaks its teach beat once it has a
  /// frame; a recall choice sounds the confirmed reading.
  void _onChanged() {
    if (_vm.isFinished) return;
    if (_vm.index != _shownIndex) {
      _shownIndex = _vm.index;
      _shownAnswered = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _speakIfTeach());
      return;
    }
    if (_vm.isAnswered && !_shownAnswered) {
      _shownAnswered = true;
      _speak(_vm.confirmedReading!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _vm,
          builder: (context, _) => _vm.isFinished ? _summary() : _session(),
        ),
      ),
    );
  }

  Widget _summary() => SessionSummary(
    // A teach-only first session has nothing graded — show no count (never a
    // hollow 0/0), just the closing fact.
    headline: _vm.gradedCount == 0
        ? ''
        : AppStrings.readingSummary(_vm.correctCount, _vm.gradedCount),
    note: AppStrings.closingNote(
      widget.units.first.written,
      band: ClosingBand.forHour(DateTime.now().hour),
    ),
    onDone: () => Navigator.of(context).pop(),
  );

  Widget _session() {
    final isTeach = _vm.isTeach;
    final answered = _vm.isAnswered;
    return Column(
      children: [
        const SizedBox(height: 8),
        Text(
          AppStrings.itemProgress(_vm.index + 1, _vm.total),
          style: const TextStyle(
            color: AppColors.inkMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                _card(),
                if (!isTeach) ...[const SizedBox(height: 20), _options()],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          // Teach + recall-answered advance with a button; while a recall is
          // still being asked, the option grid is the only action.
          child: (isTeach || answered)
              ? SizedBox(
                  height: 54,
                  child: FilledButton(
                    onPressed: isTeach ? _vm.teachNext : _vm.advance,
                    // A teach beat just moves on (an all-teach session has no
                    // results); a recall on the last prompt closes the session.
                    child: Text(
                      !isTeach && _vm.isLastItem
                          ? AppStrings.seeResults
                          : AppStrings.kanjiNext,
                    ),
                  ),
                )
              : const SizedBox(height: 54),
        ),
      ],
    );
  }

  Widget _card() {
    final p = _vm.current;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.hairline),
      ),
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            p.written,
            style: const TextStyle(
              fontSize: 88,
              height: 1.0,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 12),
          ..._cardDetail(p),
        ],
      ),
    );
  }

  // What the card reveals depends on the beat. TEACH shows the reading and the
  // sentence it lives in (a reading is never met stripped of its word). RECALL
  // while ASKING shows the written run *and* its sentence, with the target
  // marked and the reading withheld — enough to pick ひ in 帰国の日 without
  // being told ひ. The Chinese gloss stays off until after the choice. RECALL
  // once ANSWERED reveals the reading and the same context as confirmation.
  List<Widget> _cardDetail(KanjiUnit p) {
    if (_vm.isTeach) {
      return [
        // The kana inks in beneath the word while the sound still rings.
        _InkIn(
          key: ValueKey(_vm.index),
          child: Text(
            p.reading,
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
            ),
          ),
        ),
        const SizedBox(height: 10),
        ..._context(p),
        const SizedBox(height: 12),
        SpeakButton(text: _spoken, size: 28, onPlay: () => _speak(_spoken)),
        const SizedBox(height: 12),
        const Text(
          AppStrings.kanjiTeachHint,
          style: TextStyle(color: AppColors.inkMuted, fontSize: 15),
        ),
      ];
    }
    if (!_vm.isAnswered) {
      return [
        const SizedBox(height: 8),
        _PromptStem(unit: p),
        const SizedBox(height: 10),
        const Text(
          AppStrings.kanjiChooseReading,
          style: TextStyle(color: AppColors.inkMuted, fontSize: 15),
        ),
      ];
    }
    return [
      const Divider(height: 36, indent: 48, endIndent: 48),
      Text(
        p.reading,
        style: const TextStyle(
          fontSize: 40,
          fontWeight: FontWeight.w700,
          color: AppColors.accent,
        ),
      ),
      const SizedBox(height: 10),
      ..._context(p),
      const SizedBox(height: 4),
      SpeakButton(text: _spoken, size: 28, onPlay: () => _speak(_spoken)),
    ];
  }

  /// The sentence the unit was harvested from — shown plain (no furigana, which
  /// would hand over the neighbouring readings) with its one-line gloss, so the
  /// word is always met somewhere real.
  List<Widget> _context(KanjiUnit p) => [
    Text(
      p.example.written,
      textAlign: TextAlign.center,
      style: const TextStyle(color: AppColors.ink, fontSize: 17),
    ),
    const SizedBox(height: 4),
    Text(
      p.example.meaning,
      textAlign: TextAlign.center,
      style: const TextStyle(color: AppColors.inkMuted, fontSize: 14),
    ),
  ];

  Widget _options() {
    final q = _vm.question!;
    final answered = _vm.isAnswered;
    return AnswerOptionGrid(
      children: [
        for (var i = 0; i < q.options.length; i++)
          AnswerOptionButton(
            label: q.options[i],
            state: _optionState(i),
            fontSize: 34,
            onTap: answered ? null : () => _vm.answer(i),
          ),
      ],
    );
  }

  OptionState _optionState(int i) {
    final picked = _vm.picked;
    if (picked == null) return OptionState.idle;
    final accepted = _vm.acceptsOption(i);
    if (i == picked && accepted) return OptionState.correct;
    if (i == picked) return OptionState.wrong;
    if (accepted) return OptionState.revealed;
    return OptionState.dimmed;
  }
}

/// The example sentence with the target run marked and every reading withheld.
/// Lives here (not in domain) because the mark is paint, not scheduling.
class _PromptStem extends StatelessWidget {
  const _PromptStem({required this.unit});

  final KanjiUnit unit;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          for (final s in unit.example.segments)
            TextSpan(
              text: s.text,
              style: s.text == unit.written && s.furigana == unit.reading
                  ? const TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.accent,
                    )
                  : const TextStyle(color: AppColors.inkMuted),
            ),
        ],
      ),
      key: KanjiQuizScreen.promptStemKey,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 17, height: 1.5, color: AppColors.ink),
      semanticsLabel: AppStrings.kanjiAccessibleStem(
        sentence: KanjiPrompt.stemOf(unit),
        localWord: KanjiPrompt.localWord(unit),
        written: unit.written,
      ),
    );
  }
}

/// The reading fades + rises into place as it's first met (an encode cue, with
/// the sound still ringing). Intentionally a private copy of ferry's _InkIn —
/// the two screens evolve independently (CLAUDE.md: don't over-generalise).
class _InkIn extends StatelessWidget {
  const _InkIn({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, (1 - v) * 14),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
