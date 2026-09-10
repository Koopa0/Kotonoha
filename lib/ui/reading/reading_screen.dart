// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

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
    this.onMore,
    super.key,
  });

  final List<ReadingItem> items;
  final String title;

  /// Opt-in "one more" — a fresh session in place of this one (home builds it,
  /// night-suppressed). Null = hidden.
  final VoidCallback? onMore;

  static Route<void> route(
    List<ReadingItem> items,
    String title, {
    VoidCallback? onMore,
  }) => MaterialPageRoute<void>(
    builder: (_) => ReadingScreen(items: items, title: title, onMore: onMore),
  );

  @override
  State<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends State<ReadingScreen> {
  final String _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
  final Random _rng = Random();
  int _index = 0;
  bool _revealed = false;
  int _correct = 0;
  bool _done = false;

  /// Picked once, at the close — an occasional classical 余韻 (often null).
  KotenLine? _share;

  ReadingItem get _current => widget.items[_index];

  /// Speakable form — layout spaces removed.
  String get _say => _current.displayText.replaceAll(' ', '');

  void _reveal() {
    context.read<SpeechService>().speak(_say);
    setState(() => _revealed = true);
  }

  void _grade(bool correct) {
    final now = DateTime.now();
    context.read<AnalyticsLog>().recordObserved(
      Attempt(
        ts: now.millisecondsSinceEpoch,
        itemId: _current.displayText,
        itemType: ItemType.word,
        mode: PracticeMode.reading.name,
        correct: correct,
        sessionId: _sessionId,
        meta: {'romaji': _current.romaji},
      ),
    );
    // 黙読 is a schedule authority for its items: the cold self-graded read
    // advances (or resets) the item's Leitner box.
    context.read<ProgressPersistenceController>().trackWord(
      context.read<WordProgressRepository>().recordAnswer(
        _current.progressId,
        correct: correct,
        at: now,
      ),
    );
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
    } else {
      setState(() {
        _index++;
        _revealed = false;
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
    final band = ClosingBand.forHour(DateTime.now().hour);
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
                    padding: const EdgeInsets.symmetric(horizontal: 20),
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
                      padding: EdgeInsets.symmetric(horizontal: 24),
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
                    SpeakButton(text: _say, size: 30),
                    // A quiet 助詞 gloss for each particle in the phrase — pull,
                    // never pushed; role + reading quirk only, never a lesson.
                    for (final p in Particles.particlesIn(_current.displayText))
                      if (AppStrings.particleGloss(p) case final gloss?)
                        PullNote(
                          trigger: AppStrings.particleGlossTrigger,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
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
                  const Spacer(),
                ],
              ),
            ),
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
                        onPressed: () => _grade(false),
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
                        onPressed: () => _grade(true),
                        child: const Text(AppStrings.iReadIt),
                      ),
                    ),
                  ],
                )
              : SizedBox(
                  height: 54,
                  child: FilledButton(
                    onPressed: _reveal,
                    child: const Text(AppStrings.revealAnswer),
                  ),
                ),
        ),
      ],
    );
  }
}
