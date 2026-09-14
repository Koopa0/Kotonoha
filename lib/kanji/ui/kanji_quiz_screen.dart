// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/kanji/domain/models/kanji_reading_question.dart';
import 'package:kotonoha/kanji/domain/models/kanji_unit.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_prompt.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_reading_quiz.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_units.dart';
import 'package:kotonoha/kanji/kanji_mode.dart';
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
  final String _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
  late final SpeechService _speech;
  late final AppLifecycleListener _lifecycle;
  int? _ownedPlay;
  bool _playable = true;
  int _index = 0;
  bool _done = false;

  // Captured once on entering a unit: a teach beat flips isSeen, so the route
  // must not be re-derived from the live stat mid-beat. Each unit appears at
  // most once per session (KanjiSession.compose is one-pass), so a unit is
  // taught XOR recalled in a session — teach-before-test holds by construction.
  bool _isTeach = true;
  Set<String> _validReadings = const {};
  KanjiReadingQuestion? _question; // recall only
  int? _picked; // recall: chosen option index, null until committed

  int _graded = 0; // recall beats answered
  int _correct = 0; // recall beats answered correctly

  KanjiUnit get _current => widget.units[_index];
  String get _spoken => _current.reading;
  bool get _isLast => _index + 1 >= widget.units.length;

  @override
  void initState() {
    super.initState();
    _speech = context.read<SpeechService>();
    _lifecycle = AppLifecycleListener(
      onInactive: _abandonOwnedPlayback,
      onHide: _abandonOwnedPlayback,
      onPause: _abandonOwnedPlayback,
      onDetach: _abandonOwnedPlayback,
      onResume: _onResumed,
    );
    _playable = _foreground;
    _route();
    WidgetsBinding.instance.addPostFrameCallback((_) => _speakIfTeach());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _abandonOwnedPlayback();
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

  void _route() {
    final repo = context.read<KanjiReadingRepository>();
    final p = _current;
    _isTeach = !repo.statForUnit(p.id).isSeen;
    _picked = null;
    _validReadings = KanjiPrompt.validReadings(p);
    _question = _isTeach
        ? null
        : const KanjiReadingQuiz().buildQuestion(
            p,
            widget.units,
            repo.allKanji,
            widget.rng,
          );
  }

  // Ear-first: the reading is heard on a teach beat. Recall stays silent until
  // the learner has chosen (cold), so the sound can't give the answer away.
  void _speakIfTeach() {
    if (!_isTeach || !mounted) return;
    _speak(_spoken);
  }

  void _speak(String text) {
    if (!mounted || !_playable || !_foreground) return;
    unawaited(_speech.speak(text));
    _ownedPlay = _speech.generation;
  }

  void _advance() {
    if (_isLast) {
      setState(() => _done = true);
      return;
    }
    _index++;
    _route(); // read the repo + build the question outside setState
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _speakIfTeach());
  }

  void _logAttempt({
    required bool correct,
    required String beat,
    required DateTime now,
    String? chosen,
    KanjiUnit? item,
    String? scheduledId,
    bool scored = true,
  }) {
    final p = item ?? _current;
    context.read<AnalyticsLog>().recordObserved(
      Attempt(
        ts: now.millisecondsSinceEpoch,
        itemId: p.id,
        itemType: ItemType.kanji,
        mode: KanjiMode.kanjiReading.name,
        correct: correct,
        sessionId: _sessionId,
        meta: {
          'written': p.written,
          'reading': p.reading,
          // Separates honest encodes from graded recalls in the stream, so a
          // teach exposure is never read as a passed test.
          'beat': beat,
          'chosen': ?chosen,
          if (scheduledId != null && scheduledId != p.id)
            'scheduled': scheduledId,
          if (!scored) 'scored': false,
        },
      ),
    );
  }

  // TEACH 次へ: record an honest ENCODE (untimed correct → isSeen, so it returns
  // as a recall in a future session). Not a graded test, not counted in the score.
  // Untimed by design — there is no clock anywhere on this screen: ReadingStat is
  // a plain untimed Leitner (its RT/CVRT machinery was retired 2026-06-03; kanji
  // mastery is retrieval, not a reflex — see furigana_terminal_fade_test).
  void _teachNext() {
    final now = DateTime.now();
    context.read<ProgressPersistenceController>().trackKanji(
      context.read<KanjiReadingRepository>().recordAnswer(
        _current.id,
        correct: true,
        at: now,
      ),
    );
    _logAttempt(correct: true, beat: 'teach', now: now);
    _advance();
  }

  // RECALL pick: graded but untimed (latencyMs null — no clock; see _teachNext),
  // then the sound confirms AFTER the choice.
  //
  // A legal alternate (毎年 → ねん while the stem asked とし) is not a miss,
  // but it is also not retrieval of the scheduled reading. Credit the
  // harvested sibling when that reading is already seen; otherwise accept
  // without moving anyone's Leitner. A real miss still lands on [_current].
  void _answer(int i) {
    if (_picked != null) return;
    final now = DateTime.now();
    final chosen = _question!.options[i];
    final target = _current;
    final legal = _validReadings.contains(chosen);
    final repo = context.read<KanjiReadingRepository>();

    final KanjiUnit eventUnit;
    final String? scoreId;
    final bool scoreCorrect;
    String? scheduledId;

    if (!legal) {
      eventUnit = target;
      scoreId = target.id;
      scoreCorrect = false;
    } else if (chosen == target.reading) {
      eventUnit = target;
      scoreId = target.id;
      scoreCorrect = true;
    } else {
      final sibling = KanjiPrompt.creditedUnit(
        target,
        chosen,
        corpus: kKanjiUnits,
      );
      scheduledId = target.id;
      eventUnit =
          sibling ??
          KanjiUnit(
            written: target.written,
            reading: chosen,
            example: target.example,
          );
      final canCredit = sibling != null && repo.statForUnit(sibling.id).isSeen;
      scoreId = canCredit ? sibling.id : null;
      scoreCorrect = true;
    }

    if (scoreId != null) {
      context.read<ProgressPersistenceController>().trackKanji(
        repo.recordAnswer(scoreId, correct: scoreCorrect, at: now),
      );
    }
    _logAttempt(
      item: eventUnit,
      correct: legal,
      beat: 'recall',
      now: now,
      chosen: chosen,
      scheduledId: scheduledId,
      scored: scoreId != null,
    );
    _speak(legal ? chosen : target.reading);
    setState(() {
      _graded++;
      if (legal) _correct++;
      _picked = i;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(child: _done ? _summary() : _session()),
    );
  }

  Widget _summary() => SessionSummary(
    // A teach-only first session has nothing graded — show no count (never a
    // hollow 0/0), just the closing fact.
    headline: _graded == 0 ? '' : AppStrings.readingSummary(_correct, _graded),
    note: AppStrings.closingNote(
      widget.units.first.written,
      band: ClosingBand.forHour(DateTime.now().hour),
    ),
    onDone: () => Navigator.of(context).pop(),
  );

  Widget _session() {
    final answered = _picked != null;
    return Column(
      children: [
        const SizedBox(height: 8),
        Text(
          AppStrings.itemProgress(_index + 1, widget.units.length),
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
                if (!_isTeach) ...[const SizedBox(height: 20), _options()],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          // Teach + recall-answered advance with a button; while a recall is
          // still being asked, the option grid is the only action.
          child: (_isTeach || answered)
              ? SizedBox(
                  height: 54,
                  child: FilledButton(
                    onPressed: _isTeach ? _teachNext : _advance,
                    // A teach beat just moves on (an all-teach session has no
                    // results); a recall on the last prompt closes the session.
                    child: Text(
                      !_isTeach && _isLast
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
    final p = _current;
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
    if (_isTeach) {
      return [
        // The kana inks in beneath the word while the sound still rings.
        _InkIn(
          key: ValueKey(_index),
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
    if (_picked == null) {
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
    final q = _question!;
    return AnswerOptionGrid(
      children: [
        for (var i = 0; i < q.options.length; i++)
          AnswerOptionButton(
            label: q.options[i],
            state: _optionState(i),
            fontSize: 34,
            onTap: _picked == null ? () => _answer(i) : null,
          ),
      ],
    );
  }

  OptionState _optionState(int i) {
    if (_picked == null) return OptionState.idle;
    final q = _question!;
    final accepted = _validReadings.contains(q.options[i]);
    if (i == _picked && accepted) return OptionState.correct;
    if (i == _picked) return OptionState.wrong;
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
