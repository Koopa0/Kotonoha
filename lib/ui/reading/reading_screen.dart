// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/data/koten_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/koten.dart';
import 'package:kotonoha/domain/models/reading_item.dart';
import 'package:kotonoha/domain/models/season.dart';
import 'package:kotonoha/domain/use_cases/daily_bridge.dart';
import 'package:kotonoha/domain/use_cases/koten_share.dart';
import 'package:kotonoha/domain/use_cases/particles.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/pull_note.dart';
import 'package:kotonoha/ui/core/widgets/session_summary.dart';
import 'package:kotonoha/ui/core/widgets/speak_button.dart';
import 'package:provider/provider.dart';

/// Contextual reading practice over [ReadingItem]s (the 黙読 sentence track): read
/// the kana, reveal the reading + meaning, hear it (the ear is the real grader),
/// and self-grade. Records a reading [Attempt] to the analytics stream
/// (itemType=word, mode=reading); it deliberately does NOT touch per-kana SRS —
/// reading fluency is a different signal from single-kana recognition.
class ReadingScreen extends StatefulWidget {
  const ReadingScreen({
    required this.items,
    required this.title,
    this.clock,
    this.onMore,
    this.onFinished,
    this.quiet = false,
    this.alreadyTransferredIds = const {},
    super.key,
  });

  final List<ReadingItem> items;
  final String title;

  /// Injectable clock so 凪「もう一回」 and due dates stay testable by day.
  final DateTime Function()? clock;

  /// Opt-in "one more" — a fresh session in place of this one (home builds it,
  /// night-suppressed). Null = hidden.
  final VoidCallback? onMore;

  /// Official close (session summary) — not a mere open or pop.
  final VoidCallback? onFinished;

  /// Silent run: reveal must not speak, and the speaker stays hidden.
  final bool quiet;

  /// Progress ids already covered in this 「もう一回」 grind. A wrap-around
  /// item may be shown again but must not renew SRS.
  final Set<String> alreadyTransferredIds;

  static Route<void> route(
    List<ReadingItem> items,
    String title, {
    VoidCallback? onMore,
    VoidCallback? onFinished,
    DateTime Function()? clock,
    bool quiet = false,
    Set<String> alreadyTransferredIds = const {},
  }) => MaterialPageRoute<void>(
    builder: (_) => ReadingScreen(
      items: items,
      title: title,
      onMore: onMore,
      onFinished: onFinished,
      clock: clock,
      quiet: quiet,
      alreadyTransferredIds: alreadyTransferredIds,
    ),
  );

  @override
  State<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends State<ReadingScreen> {
  final String _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
  final Random _rng = Random();
  late final SpeechService _speech;
  late final AppLifecycleListener _lifecycle;
  int? _ownedPlay;
  bool _playable = true;
  int _index = 0;
  bool _revealed = false;
  bool _unpromptedCommit = false;
  int _correct = 0;
  bool _done = false;

  /// Picked once, at the close — an occasional classical 余韻 (often null).
  KotenLine? _share;

  ReadingItem get _current => widget.items[_index];

  DateTime Function() get _clock => widget.clock ?? DateTime.now;

  /// Speakable form — layout spaces removed.
  String get _say => _current.displayText.replaceAll(' ', '');

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
    if (!mounted || !_playable || !_foreground || widget.quiet) return;
    unawaited(_speech.speak(_say));
    _ownedPlay = _speech.generation;
  }

  void _reveal({required bool unpromptedCommit}) {
    _speak();
    setState(() {
      _revealed = true;
      _unpromptedCommit = unpromptedCommit;
    });
  }

  void _grade({required bool correct, required bool unprompted}) {
    final now = _clock();
    context.read<AnalyticsLog>().recordObserved(
      Attempt(
        ts: now.millisecondsSinceEpoch,
        itemId: _current.displayText,
        itemType: ItemType.word,
        mode: PracticeMode.reading.name,
        correct: correct,
        sessionId: _sessionId,
        meta: {'romaji': _current.romaji, AttemptMeta.prompted: !unprompted},
      ),
    );
    final words = context.read<WordProgressRepository>();
    final persist = context.read<ProgressPersistenceController>();
    final id = _current.progressId;
    final canRenew = DailyBridge.shouldRenew(id, widget.alreadyTransferredIds);
    // Unprompted confirmed-correct is the only climb, and only the first
    // time this grind covers the id. Prompted correct on a new item keeps
    // intake (seen) without mastering. A miss always resets.
    if (!correct) {
      persist.trackWord(words.recordAnswer(id, correct: false, at: now));
    } else if (unprompted && canRenew) {
      persist.trackWord(words.recordAnswer(id, correct: true, at: now));
    } else if (!unprompted && !words.statForItem(id).isSeen) {
      persist.trackWord(words.markIntroduced(id, at: now));
    }
    if (correct) _correct++;
    if (_index + 1 >= widget.items.length) {
      final store = context.read<KanaProgressRepository>();
      _share = KotenShare.pick(
        pool: kKoten,
        seenKanaCount: store.seenCount,
        rng: _rng,
        season: Season.forMonth(now.month),
      );
      setState(() => _done = true);
      widget.onFinished?.call();
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
      headline: AppStrings.readingSummary(_correct, widget.items.length),
      // The classical 余韻 (when picked) replaces the close note — so only
      // compute the note when no share will lead.
      note: _share == null
          ? AppStrings.closing(widget.items.last.displayText, band: band)
          : null,
      share: _share,
      onDone: () => Navigator.of(context).pop(),
      // At night the close grants permission to stop — suppress もう一回 here, at
      // render time, so a session that began in daylight still hides it at dusk.
      onMore: band == ClosingBand.day ? widget.onMore : null,
    );
  }

  Widget _question() {
    // Phrases are longer than words — scale the glyphs down a touch.
    final big = _say.length <= 4;
    return Column(
      children: [
        const SizedBox(height: 8),
        Text(
          AppStrings.itemProgress(_index + 1, widget.items.length),
          style: const TextStyle(
            color: AppColors.inkMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: AppColors.hairline),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 20,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _current.displayText,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: big ? 64 : 44,
                                    height: 1.2,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.ink,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (!_revealed)
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Text(
                                  AppStrings.readPrompt,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: AppColors.inkMuted,
                                    fontSize: 15,
                                  ),
                                ),
                              )
                            else ...[
                              const Divider(height: 36, indent: 48, endIndent: 48),
                              Text(
                                _current.romaji,
                                style: const TextStyle(
                                  fontSize: 26,
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
                              if (!widget.quiet)
                                SpeakButton(text: _say, size: 30, onPlay: _speak),
                              // A quiet 助詞 gloss for each particle in the phrase — pull,
                              // never pushed; role + reading quirk only, never a lesson.
                              for (final p
                                  in Particles.particlesIn(_current.displayText))
                                if (AppStrings.particleGloss(p) case final gloss?)
                                  PullNote(
                                    trigger: AppStrings.particleGlossTrigger,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      child: Text(
                                        gloss,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: AppColors.inkMuted,
                                          height: 1.5,
                                        ),
                                      ),
                                    ),
                                  ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: _revealed
              ? Row(
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
                        onPressed: () => _grade(
                          correct: false,
                          unprompted: _unpromptedCommit,
                        ),
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
                        onPressed: () => _grade(
                          correct: true,
                          unprompted: _unpromptedCommit,
                        ),
                        child: Text(
                          _unpromptedCommit
                              ? AppStrings.iReadIt
                              : AppStrings.iReadAfterHint,
                        ),
                      ),
                    ),
                  ],
                )
              : Row(
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
                ),
        ),
      ],
    );
  }
}
