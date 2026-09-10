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
import 'package:kotonoha/domain/use_cases/koten_share.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/session_summary.dart';
import 'package:provider/provider.dart';

/// 聞き取り — listen first, recall unaided, reveal, then rehear.
///
/// Playback that is unavailable, failed, interrupted, or cut by leaving the
/// page is not listening evidence: no wrong Attempt, no Leitner move.
/// Reveal-after-reading is allowed, but a grade still requires a completed
/// [SpeechPlaybackResult.played] on this item.
class ListeningScreen extends StatefulWidget {
  const ListeningScreen({
    required this.items,
    required this.title,
    this.clock,
    this.onMore,
    super.key,
  });

  final List<ReadingItem> items;
  final String title;

  /// Injectable clock so reaction time is testable.
  final DateTime Function()? clock;

  /// Opt-in "one more" — a fresh session (home builds it, night-suppressed).
  final VoidCallback? onMore;

  static Route<void> route(
    List<ReadingItem> items,
    String title, {
    VoidCallback? onMore,
  }) => MaterialPageRoute<void>(
    builder: (_) => ListeningScreen(items: items, title: title, onMore: onMore),
  );

  @override
  State<ListeningScreen> createState() => _ListeningScreenState();
}

class _ListeningScreenState extends State<ListeningScreen>
    with WidgetsBindingObserver {
  final String _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
  final Random _rng = Random();

  late final SpeechService _speech;

  int _index = 0;
  bool _revealed = false;
  bool _heard = false;
  bool _playing = false;
  bool _done = false;
  int _correct = 0;
  int _heardAtMs = 0;
  int _playGen = 0;
  SpeechPlaybackResult? _lastPlay;
  KotenLine? _share;

  DateTime Function() get _clock => widget.clock ?? DateTime.now;

  ReadingItem get _current => widget.items[_index];

  /// Speakable form — layout spaces removed.
  String get _say => _current.displayText.replaceAll(' ', '');

  @override
  void initState() {
    super.initState();
    _speech = context.read<SpeechService>();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_play());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_speech.stop());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    unawaited(_interrupt());
  }

  Future<void> _interrupt() async {
    _playGen++;
    await _speech.stop();
    if (!mounted) return;
    setState(() {
      _playing = false;
      _lastPlay = SpeechPlaybackResult.interrupted;
    });
  }

  Future<void> _play() async {
    if (!mounted) return;
    final gen = ++_playGen;
    setState(() => _playing = true);
    final result = await _speech.play(_say);
    if (!mounted || gen != _playGen) return;
    setState(() {
      _playing = false;
      _lastPlay = result;
      if (result == SpeechPlaybackResult.played) {
        _heard = true;
        if (_heardAtMs == 0) {
          _heardAtMs = _clock().millisecondsSinceEpoch;
        }
      }
    });
  }

  void _reveal() {
    setState(() => _revealed = true);
  }

  void _grade(bool correct) {
    if (!_heard) return;
    _advance(record: true, correct: correct);
  }

  void _skipUnheard() {
    if (_heard) return;
    _advance(record: false, correct: false);
  }

  void _advance({required bool record, required bool correct}) {
    final now = _clock();
    if (record) {
      context.read<AnalyticsLog>().recordObserved(
        Attempt(
          ts: now.millisecondsSinceEpoch,
          itemId: _current.displayText,
          itemType: ItemType.word,
          mode: PracticeMode.listening.name,
          correct: correct,
          rtMs: _heardAtMs == 0 ? 0 : now.millisecondsSinceEpoch - _heardAtMs,
          sessionId: _sessionId,
          meta: {
            'romaji': _current.romaji,
            AttemptMeta.playback: SpeechPlaybackResult.played.name,
            AttemptMeta.heard: true,
          },
        ),
      );
      context.read<ProgressPersistenceController>().trackWord(
        context.read<WordProgressRepository>().recordAnswer(
          _current.progressId,
          correct: correct,
          at: now,
        ),
      );
      if (correct) _correct++;
    }
    if (_index + 1 >= widget.items.length) {
      final store = context.read<KanaProgressRepository>();
      _share = KotenShare.pick(
        pool: kKoten,
        seenKanaCount: store.seenCount,
        rng: _rng,
        season: Season.forMonth(now.month),
      );
      setState(() => _done = true);
      unawaited(_speech.stop());
      return;
    }
    setState(() {
      _index++;
      _revealed = false;
      _heard = false;
      _playing = false;
      _heardAtMs = 0;
      _lastPlay = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_play());
    });
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
      headline: AppStrings.listeningSummary(_correct, widget.items.length),
      note: _share == null
          ? AppStrings.closing(widget.items.last.displayText, band: band)
          : null,
      share: _share,
      onDone: () => Navigator.of(context).pop(),
      onMore: band == ClosingBand.day ? widget.onMore : null,
    );
  }

  Widget _question() {
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
                  IconButton.filled(
                    key: const ValueKey<String>('listening-replay'),
                    onPressed: () => unawaited(_play()),
                    iconSize: _revealed ? 34 : 56,
                    tooltip: AppStrings.replaySound,
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.accentSoft,
                      foregroundColor: AppColors.accent,
                      padding: EdgeInsets.all(_revealed ? 14 : 22),
                    ),
                    icon: Icon(
                      _playing
                          ? Icons.graphic_eq_rounded
                          : Icons.volume_up_rounded,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _revealed
                        ? AppStrings.listeningRehear
                        : AppStrings.listeningPrompt,
                    style: const TextStyle(
                      color: AppColors.inkMuted,
                      fontSize: 15,
                    ),
                  ),
                  if (!_revealed) ...[
                    const SizedBox(height: 8),
                    const Text(
                      AppStrings.listeningRecall,
                      style: TextStyle(color: AppColors.inkMuted, fontSize: 14),
                    ),
                  ],
                  if (_revealed) ...[
                    const SizedBox(height: 24),
                    Text(
                      _current.displayText,
                      key: const ValueKey<String>('listening-answer'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 34,
                        height: 1.2,
                        fontWeight: FontWeight.w500,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _current.romaji,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _current.meaning,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 18,
                      ),
                    ),
                  ],
                  if (_blockMessage != null) ...[
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        _blockMessage!,
                        key: const ValueKey<String>('listening-block'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.inkMuted,
                          fontSize: 14,
                          height: 1.5,
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
          child: _controls(),
        ),
      ],
    );
  }

  String? get _blockMessage {
    if (_heard) return null;
    return switch (_lastPlay) {
      SpeechPlaybackResult.unavailable => AppStrings.listeningUnavailable,
      SpeechPlaybackResult.failed => AppStrings.listeningFailed,
      SpeechPlaybackResult.interrupted => AppStrings.listeningInterrupted,
      SpeechPlaybackResult.played => null,
      null => _revealed ? AppStrings.listeningInterrupted : null,
    };
  }

  Widget _controls() {
    if (!_revealed) {
      return SizedBox(
        height: 54,
        width: double.infinity,
        child: FilledButton(
          key: const ValueKey<String>('listening-reveal'),
          onPressed: _reveal,
          child: const Text(AppStrings.listeningReveal),
        ),
      );
    }
    if (_heard) {
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
              onPressed: () => _grade(false),
              child: const Text(AppStrings.listeningMissed),
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
              child: const Text(AppStrings.listeningHeard),
            ),
          ),
        ],
      );
    }
    return SizedBox(
      height: 54,
      width: double.infinity,
      child: OutlinedButton(
        key: const ValueKey<String>('listening-skip'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          side: const BorderSide(color: AppColors.hairline),
          foregroundColor: AppColors.inkMuted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: _skipUnheard,
        child: const Text(AppStrings.listeningSkip),
      ),
    );
  }
}
