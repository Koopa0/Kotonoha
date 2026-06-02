// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/data/koten_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/false_friend.dart';
import 'package:kotonoha/domain/models/koten.dart';
import 'package:kotonoha/domain/models/season.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/domain/use_cases/koten_share.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/pull_note.dart';
import 'package:kotonoha/ui/core/widgets/session_summary.dart';
import 'package:kotonoha/ui/core/widgets/speak_button.dart';
import 'package:provider/provider.dart';

/// 渡し舟 — the Ferry. For a learner whose ear runs ahead of his eye: a word he
/// may already know by sound is ferried across to its written body in three
/// beats — (1) hear it, (2) watch the kana ink in over the still-ringing audio
/// (the binding), (3) read it back unaided. The thesis made mechanical. Records
/// a reading [Attempt] (mode=ferry); reaction time is the read-back.
class FerryScreen extends StatefulWidget {
  const FerryScreen({
    required this.words,
    required this.title,
    this.clock,
    this.onMore,
    super.key,
  });

  final List<Word> words;
  final String title;

  /// Injectable clock so the read-back reaction time is testable.
  final DateTime Function()? clock;

  /// Opt-in "one more" — a fresh session (home builds it, night-suppressed).
  final VoidCallback? onMore;

  static Route<void> route(
    List<Word> words,
    String title, {
    VoidCallback? onMore,
  }) => MaterialPageRoute<void>(
    builder: (_) => FerryScreen(words: words, title: title, onMore: onMore),
  );

  @override
  State<FerryScreen> createState() => _FerryScreenState();
}

enum _Beat { hear, see, readback }

class _FerryScreenState extends State<FerryScreen> {
  final String _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
  final Random _rng = Random();
  int _index = 0;
  _Beat _beat = _Beat.hear;
  int _readbackAtMs = 0;
  int _correct = 0;
  bool _done = false;

  /// Picked once, at the close — an occasional classical 余韻 (often null).
  KotenLine? _share;

  DateTime Function() get _clock => widget.clock ?? DateTime.now;

  Word get _current => widget.words[_index];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _speak());
  }

  void _speak() {
    if (!mounted) return;
    context.read<SpeechService>().speak(_current.kana);
  }

  void _showText() {
    _speak();
    setState(() => _beat = _Beat.see);
  }

  void _readSelf() => setState(() {
    _beat = _Beat.readback;
    // Time only the read-back — the see-beat dwell must not count.
    _readbackAtMs = _clock().millisecondsSinceEpoch;
  });

  void _grade(bool correct) {
    final now = _clock();
    context.read<AnalyticsLog>().record(
      Attempt(
        ts: now.millisecondsSinceEpoch,
        itemId: _current.kana,
        itemType: ItemType.word,
        mode: PracticeMode.ferry.name,
        correct: correct,
        rtMs: now.millisecondsSinceEpoch - _readbackAtMs,
        sessionId: _sessionId,
        meta: {'romaji': _current.romaji},
      ),
    );
    if (correct) _correct++;
    if (_index + 1 >= widget.words.length) {
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
        _beat = _Beat.hear;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _speak());
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
      headline: AppStrings.readingSummary(_correct, widget.words.length),
      // The classical 余韻 (when picked) replaces the close note.
      note: _share == null
          ? AppStrings.closing(widget.words.last.kana, band: band)
          : null,
      share: _share,
      onDone: () => Navigator.of(context).pop(),
      // Night close grants permission to stop — suppress もう一回 at render time.
      onMore: band == ClosingBand.day ? widget.onMore : null,
    );
  }

  Widget _question() {
    final showKana = _beat != _Beat.hear;
    return Column(
      children: [
        const SizedBox(height: 8),
        Text(
          AppStrings.itemProgress(_index + 1, widget.words.length),
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
                  SpeakButton(
                    text: _current.kana,
                    prominent: true,
                    size: showKana ? 34 : 56,
                  ),
                  if (showKana) ...[
                    const SizedBox(height: 24),
                    // The kana inks in — fades and rises into being.
                    _InkIn(
                      key: ValueKey(_index),
                      child: Text(
                        _current.kana,
                        style: const TextStyle(
                          fontSize: 64,
                          height: 1.1,
                          fontWeight: FontWeight.w500,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // The same identity block the reading screen reveals, kept
                    // consistent: romaji (the reading) then meaning (the word
                    // you own). The ear already gave him the sound; these confirm.
                    Text(
                      _current.romaji,
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _current.meaning,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 18,
                      ),
                    ),
                    // 同形異義語: a quiet, on-demand note when the kanji means
                    // something different in Japanese than a Chinese reader
                    // would assume. Pull, never pushed.
                    if (_current.falseFriend != null)
                      _FalseFriendNote(
                        _current.falseFriend!,
                        key: ValueKey(_current.kana),
                      ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    switch (_beat) {
                      _Beat.hear => AppStrings.ferryHear,
                      _Beat.see => AppStrings.ferrySee,
                      _Beat.readback => AppStrings.ferryReadback,
                    },
                    style: const TextStyle(
                      color: AppColors.inkMuted,
                      fontSize: 15,
                    ),
                  ),
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

  Widget _controls() {
    switch (_beat) {
      case _Beat.hear:
        return SizedBox(
          height: 54,
          child: FilledButton(
            onPressed: _showText,
            child: const Text(AppStrings.ferryShowText),
          ),
        );
      case _Beat.see:
        return SizedBox(
          height: 54,
          child: FilledButton(
            onPressed: _readSelf,
            child: const Text(AppStrings.ferryReadSelf),
          ),
        );
      case _Beat.readback:
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
        );
    }
  }
}

/// A pull-not-push 同形異義語 note: a quiet 「日文意思?」 that unfolds one calm line
/// affirming the Japanese meaning — the shared [PullNote] fold.
class _FalseFriendNote extends StatelessWidget {
  const _FalseFriendNote(this.friend, {super.key});

  final FalseFriend friend;

  @override
  Widget build(BuildContext context) {
    return PullNote(
      trigger: AppStrings.falseFriendTrigger,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          AppStrings.falseFriendNote(friend),
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.inkMuted, height: 1.5),
        ),
      ),
    );
  }
}

/// Fades and rises its child into being — ink surfacing on wet paper.
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
