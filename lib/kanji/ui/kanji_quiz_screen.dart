// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/kanji/domain/models/kanji_entry.dart';
import 'package:kotonoha/kanji/domain/models/kanji_reading_question.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_reading_quiz.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_session.dart';
import 'package:kotonoha/kanji/kanji_mode.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/answer_option_button.dart';
import 'package:kotonoha/ui/core/widgets/session_summary.dart';
import 'package:kotonoha/ui/core/widgets/speak_button.dart';
import 'package:provider/provider.dart';

/// 漢字の声 — honest kanji reading. A never-seen reading is TAUGHT ear-first
/// (hear it, watch the kana ink in, the meaning as quiet context); a seen
/// reading is RECALLed cold by choosing the reading from four real same-kind
/// readings of OTHER kanji, with the meaning HIDDEN until after the choice — so
/// the meaning a 漢字-literate reader already owns can't stand in for the reading
/// he must produce. No score on screen, no clock (latencyMs stays null); the
/// per-reading Leitner advances either way.
class KanjiQuizScreen extends StatefulWidget {
  KanjiQuizScreen({
    required this.prompts,
    required this.title,
    Random? rng,
    super.key,
  }) : rng = rng ?? Random();

  final List<KanjiPrompt> prompts;
  final String title;

  /// Injected so option order is deterministic under test.
  final Random rng;

  static Route<void> route(List<KanjiPrompt> prompts, String title) =>
      MaterialPageRoute<void>(
        builder: (_) => KanjiQuizScreen(prompts: prompts, title: title),
      );

  @override
  State<KanjiQuizScreen> createState() => _KanjiQuizScreenState();
}

class _KanjiQuizScreenState extends State<KanjiQuizScreen> {
  final String _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
  int _index = 0;
  bool _done = false;

  // Captured once on entering a prompt: a teach beat flips isSeen, so the route
  // must not be re-derived from the live stat mid-beat. Each readingId appears
  // at most once per session (KanjiSession.compose is one-pass), so a reading is
  // taught XOR recalled in a session — teach-before-test holds by construction.
  bool _isTeach = true;
  KanjiReadingQuestion? _question; // recall only
  int? _picked; // recall: chosen option index, null until committed

  int _graded = 0; // recall beats answered
  int _correct = 0; // recall beats answered correctly

  KanjiPrompt get _current => widget.prompts[_index];
  String get _spoken => _current.reading.exampleWord ?? _current.reading.text;
  bool get _isLast => _index + 1 >= widget.prompts.length;

  @override
  void initState() {
    super.initState();
    _route();
    WidgetsBinding.instance.addPostFrameCallback((_) => _speakIfTeach());
  }

  void _route() {
    final repo = context.read<KanjiReadingRepository>();
    final p = _current;
    _isTeach = !repo.statForReading(p.readingId).isSeen;
    _picked = null;
    _question = _isTeach
        ? null
        : const KanjiReadingQuiz().buildQuestion(
            p.entry,
            p.reading,
            repo.allKanji,
            widget.rng,
          );
  }

  // Ear-first: the reading is heard on a teach beat. Recall stays silent until
  // the learner has chosen (cold), so the sound can't give the answer away.
  void _speakIfTeach() {
    if (_isTeach && mounted) context.read<SpeechService>().speak(_spoken);
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
  }) {
    final p = _current;
    context.read<AnalyticsLog>().record(
      Attempt(
        ts: now.millisecondsSinceEpoch,
        itemId: p.readingId,
        itemType: ItemType.kanji,
        mode: KanjiMode.kanjiReading.name,
        correct: correct,
        sessionId: _sessionId,
        meta: {
          'kanji': p.entry.char,
          'reading': p.reading.text,
          'kind': p.reading.kind.name,
          // Separates honest encodes from graded recalls in the stream, so a
          // teach exposure is never read as a passed test.
          'beat': beat,
          'chosen': ?chosen,
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
        _current.readingId,
        correct: true,
        at: now,
      ),
    );
    _logAttempt(correct: true, beat: 'teach', now: now);
    _advance();
  }

  // RECALL pick: graded but untimed (latencyMs null — no clock; see _teachNext),
  // then the sound confirms AFTER the choice.
  void _answer(int i) {
    if (_picked != null) return;
    final now = DateTime.now();
    final correct = i == _question!.correctIndex;
    context.read<ProgressPersistenceController>().trackKanji(
      context.read<KanjiReadingRepository>().recordAnswer(
        _current.readingId,
        correct: correct,
        at: now,
      ),
    );
    _logAttempt(
      correct: correct,
      beat: 'recall',
      now: now,
      chosen: _question!.options[i],
    );
    context.read<SpeechService>().speak(_spoken);
    setState(() {
      _graded++;
      if (correct) _correct++;
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
      widget.prompts.first.entry.char,
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
          AppStrings.itemProgress(_index + 1, widget.prompts.length),
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
          _KindChip(
            label: p.reading.kind == ReadingKind.on
                ? AppStrings.kanjiOnyomi
                : AppStrings.kanjiKunyomi,
          ),
          const SizedBox(height: 16),
          Text(
            p.entry.char,
            style: const TextStyle(
              fontSize: 96,
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

  // What the card reveals depends on the beat. TEACH shows everything (encode).
  // RECALL while ASKING shows nothing but the prompt — the meaning he owns and
  // the reading itself are absent, not merely dimmed. RECALL once ANSWERED
  // reveals the reading + example + meaning as confirmation.
  List<Widget> _cardDetail(KanjiPrompt p) {
    final r = p.reading;
    if (_isTeach) {
      return [
        // The kana inks in beneath the kanji while the sound still rings.
        _InkIn(
          key: ValueKey(_index),
          child: Text(
            r.text,
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
            ),
          ),
        ),
        if (r.exampleWord != null) ...[
          const SizedBox(height: 8),
          Text(
            '${r.exampleWord}'
            '${r.exampleMeaning != null ? '・${r.exampleMeaning}' : ''}',
            style: const TextStyle(color: AppColors.ink, fontSize: 16),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          p.entry.meaningZh,
          style: const TextStyle(color: AppColors.inkMuted, fontSize: 15),
        ),
        const SizedBox(height: 12),
        SpeakButton(text: _spoken, size: 28),
        const SizedBox(height: 12),
        const Text(
          AppStrings.kanjiTeachHint,
          style: TextStyle(color: AppColors.inkMuted, fontSize: 15),
        ),
      ];
    }
    if (_picked == null) {
      return const [
        SizedBox(height: 4),
        Text(
          AppStrings.kanjiChooseReading,
          style: TextStyle(color: AppColors.inkMuted, fontSize: 15),
        ),
      ];
    }
    return [
      const Divider(height: 36, indent: 48, endIndent: 48),
      Text(
        r.text,
        style: const TextStyle(
          fontSize: 40,
          fontWeight: FontWeight.w700,
          color: AppColors.accent,
        ),
      ),
      if (r.exampleWord != null) ...[
        const SizedBox(height: 4),
        Text(
          '${r.exampleWord}'
          '${r.exampleMeaning != null ? '・${r.exampleMeaning}' : ''}',
          style: const TextStyle(color: AppColors.ink, fontSize: 16),
        ),
      ],
      const SizedBox(height: 6),
      Text(
        p.entry.meaningZh,
        style: const TextStyle(color: AppColors.inkMuted, fontSize: 15),
      ),
      const SizedBox(height: 4),
      SpeakButton(text: _spoken, size: 28),
    ];
  }

  Widget _options() {
    final q = _question!;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.6,
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
    if (i == _picked && i == q.correctIndex) return OptionState.correct;
    if (i == _picked) return OptionState.wrong;
    if (i == q.correctIndex) return OptionState.revealed;
    return OptionState.dimmed;
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.accent,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
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
