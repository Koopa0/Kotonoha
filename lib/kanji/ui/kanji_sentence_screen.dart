// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/use_cases/daily_bridge.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/kanji/domain/models/kanji_phrase.dart';
import 'package:kotonoha/kanji/ui/ruby_text.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/session_summary.dart';
import 'package:kotonoha/ui/core/widgets/speak_button.dart';
import 'package:provider/provider.dart';

/// Sentence reading in real written Japanese — the home of the grammar-pattern
/// spine. Read the sentence (furigana over each kanji thins out as that reading
/// matures in 漢字の声), then reveal the full kana reading + meaning + audio and
/// self-grade.
///
/// TWO schedules meet here and stay separate: the per-READING kanji SRS is
/// driven by 漢字の声 (this screen never touches it — it only consumes its
/// maturity to fade furigana), while the per-SENTENCE schedule is this
/// screen's own, a cold self-graded read recorded against
/// `WordProgressRepository`. So re-reading a sentence never inflates a kanji
/// reading's mastery, and mastering a reading never marks a sentence reviewed.
class KanjiSentenceScreen extends StatefulWidget {
  const KanjiSentenceScreen({
    required this.phrases,
    required this.title,
    this.clock,
    this.onMore,
    this.alreadyTransferredIds = const {},
    super.key,
  });

  final List<KanjiPhrase> phrases;
  final String title;

  /// Injectable clock so 凪「もう一回」 and due dates stay testable by day.
  final DateTime Function()? clock;

  /// Opt-in "one more" — a fresh session (home builds it, night-suppressed).
  final VoidCallback? onMore;

  /// Progress ids already covered in this 「もう一回」 grind. A wrap-around
  /// sentence may be shown again but must not renew SRS.
  final Set<String> alreadyTransferredIds;

  static Route<void> route(
    List<KanjiPhrase> phrases,
    String title, {
    VoidCallback? onMore,
    DateTime Function()? clock,
    Set<String> alreadyTransferredIds = const {},
  }) => MaterialPageRoute<void>(
    builder: (_) => KanjiSentenceScreen(
      phrases: phrases,
      title: title,
      clock: clock,
      onMore: onMore,
      alreadyTransferredIds: alreadyTransferredIds,
    ),
  );

  @override
  State<KanjiSentenceScreen> createState() => _KanjiSentenceScreenState();
}

class _KanjiSentenceScreenState extends State<KanjiSentenceScreen> {
  final String _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
  late final SpeechService _speech;
  late final AppLifecycleListener _lifecycle;
  int? _ownedPlay;
  bool _playable = true;
  int _index = 0;
  bool _revealed = false;
  bool _unpromptedCommit = false;
  int _correct = 0;
  bool _done = false;

  KanjiPhrase get _current => widget.phrases[_index];

  DateTime Function() get _clock => widget.clock ?? DateTime.now;

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

  void _speak() {
    if (!mounted || !_playable || !_foreground) return;
    unawaited(_speech.speak(_current.reading));
    _ownedPlay = _speech.generation;
  }

  void _reveal({required bool unpromptedCommit}) {
    _speak();
    setState(() {
      _revealed = true;
      _unpromptedCommit = unpromptedCommit;
    });
  }

  bool _independentRecall({required bool unprompted}) {
    final repo = context.read<KanjiReadingRepository>();
    // The commit button is only half the evidence: first-teach furigana
    // already on the card is reading support, even if the learner pressed
    // 「讀得出來」. Mature readings (opacity 0) stay independent.
    final rubySupport = RubyText.hasVisibleReadingSupport(
      _current,
      (id) => repo.statForUnit(id).srsLevel,
    );
    return unprompted && !rubySupport;
  }

  void _grade({required bool correct, required bool unprompted}) {
    final now = _clock();
    final independent = _independentRecall(unprompted: unprompted);
    context.read<AnalyticsLog>().recordObserved(
      Attempt(
        ts: now.millisecondsSinceEpoch,
        itemId: _current.written,
        itemType: ItemType.kanji,
        mode: PracticeMode.reading.name,
        correct: correct,
        sessionId: _sessionId,
        meta: {'reading': _current.reading, AttemptMeta.prompted: !independent},
      ),
    );
    // The sentence's own schedule — a cold self-graded read. (The per-reading
    // kanji SRS belongs to 漢字の声 and is deliberately untouched here.)
    // Independent confirmed-correct is the only climb, and only the first
    // time this grind covers the id. Supported correct on a new item keeps
    // intake (seen) without mastering. A miss always resets.
    final words = context.read<WordProgressRepository>();
    final persist = context.read<ProgressPersistenceController>();
    final id = _current.progressId;
    final canRenew = DailyBridge.shouldRenew(id, widget.alreadyTransferredIds);
    if (!correct) {
      persist.trackWord(words.recordAnswer(id, correct: false, at: now));
    } else if (independent && canRenew) {
      persist.trackWord(words.recordAnswer(id, correct: true, at: now));
    } else if (!independent && !words.statForItem(id).isSeen) {
      persist.trackWord(words.markIntroduced(id, at: now));
    }
    if (correct) _correct++;
    if (_index + 1 >= widget.phrases.length) {
      setState(() => _done = true);
    } else {
      setState(() {
        _index++;
        _revealed = false;
        _unpromptedCommit = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(child: _done ? _summary() : _question()),
    );
  }

  Widget _summary() {
    final band = ClosingBand.forHour(_clock().hour);
    return SessionSummary(
      headline: AppStrings.readingSummary(_correct, widget.phrases.length),
      note: AppStrings.closing(widget.phrases.last.written, band: band),
      onDone: () => Navigator.of(context).pop(),
      // Night close grants permission to stop — suppress もう一回 at render time.
      onMore: band == ClosingBand.day ? widget.onMore : null,
    );
  }

  Widget _question() {
    final repo = context.read<KanjiReadingRepository>();
    return Column(
      children: [
        const SizedBox(height: 8),
        Text(
          AppStrings.itemProgress(_index + 1, widget.phrases.length),
          style: const TextStyle(
            color: AppColors.inkMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(24),
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
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: RubyText(
                      phrase: _current,
                      srsLevelOf: (id) => repo.statForUnit(id).srsLevel,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!_revealed)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        AppStrings.kanjiSentencePrompt,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.inkMuted,
                          fontSize: 14,
                        ),
                      ),
                    )
                  else ...[
                    const Divider(height: 36, indent: 48, endIndent: 48),
                    Text(
                      _current.reading,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _current.meaning,
                      style: const TextStyle(
                        fontSize: 18,
                        color: AppColors.ink,
                      ),
                    ),
                    SpeakButton(
                      text: _current.reading,
                      size: 28,
                      onPlay: _speak,
                    ),
                  ],
                  const Spacer(),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: _revealed ? _gradeControls() : _revealControls(),
        ),
      ],
    );
  }

  Widget _revealControls() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: () => _reveal(unpromptedCommit: false),
            child: const Text(AppStrings.recallHint),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
            ),
            onPressed: () => _reveal(unpromptedCommit: true),
            child: const Text(AppStrings.iReadUnprompted),
          ),
        ),
      ],
    );
  }

  Widget _gradeControls() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              side: const BorderSide(color: AppColors.error),
              foregroundColor: AppColors.error,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: () =>
                _grade(correct: false, unprompted: _unpromptedCommit),
            child: const Text(AppStrings.iCouldnt),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.success,
              minimumSize: const Size.fromHeight(54),
            ),
            onPressed: () =>
                _grade(correct: true, unprompted: _unpromptedCommit),
            child: Text(
              _unpromptedCommit
                  ? AppStrings.iReadIt
                  : AppStrings.iReadAfterHint,
            ),
          ),
        ),
      ],
    );
  }
}
