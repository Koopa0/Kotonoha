// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/data/kana_dataset.dart';
import 'package:kotonoha/domain/data/koten_dataset.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/koten.dart';
import 'package:kotonoha/domain/models/season.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/domain/use_cases/kana_tokenizer.dart';
import 'package:kotonoha/domain/use_cases/koten_share.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/session_summary.dart';
import 'package:kotonoha/ui/core/widgets/speak_button.dart';
import 'package:provider/provider.dart';

/// 文字を起こす — dictation. Hear a word, then ASSEMBLE it from kana tiles (its
/// own kana plus a few distractors). This is the production / encoding rep the
/// learner is otherwise missing — recognition tells you nothing about whether he
/// can call the written shape up himself. Records a [Attempt] (mode=dictation),
/// rtMs = time to assemble.
class DictationScreen extends StatefulWidget {
  const DictationScreen({
    required this.words,
    required this.title,
    this.clock,
    this.onMore,
    super.key,
  });

  final List<Word> words;
  final String title;

  /// Injectable clock so the assembled-word reaction time is testable.
  final DateTime Function()? clock;

  /// Opt-in "one more" — a fresh session (home builds it, night-suppressed).
  final VoidCallback? onMore;

  static Route<void> route(
    List<Word> words,
    String title, {
    VoidCallback? onMore,
  }) => MaterialPageRoute<void>(
    builder: (_) => DictationScreen(words: words, title: title, onMore: onMore),
  );

  @override
  State<DictationScreen> createState() => _DictationScreenState();
}

class _DictationScreenState extends State<DictationScreen> {
  final String _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
  final Random _rng = Random();

  /// Picked once, at the close — an occasional classical 余韻 (often null).
  KotenLine? _share;
  int _index = 0;
  List<String> _tiles = const [];
  List<bool> _used = const [];
  final List<int> _picked = [];
  bool _checked = false;
  bool _wasCorrect = false;
  int _correct = 0;
  bool _done = false;
  int _shownAtMs = 0;

  Word get _current => widget.words[_index];

  DateTime Function() get _clock => widget.clock ?? DateTime.now;

  /// The word split into learning-unit tiles (きゃ stays one tile, っ/ー are
  /// their own tiles) — assembly works in the units the learner reads in.
  List<String> get _targetChars => KanaTokenizer.tokenize(_current.kana);

  @override
  void initState() {
    super.initState();
    _setup();
    WidgetsBinding.instance.addPostFrameCallback((_) => _speak());
  }

  void _setup() {
    final chars = _targetChars;
    // Distractor tiles come from the word's own script — cross-script tiles
    // would give the answer away by shape alone.
    final distractorPool = _current.script == KanaScript.katakana
        ? kKatakanaGojuon
        : kHiraganaGojuon;
    final distractors =
        (distractorPool
                .map((k) => k.character)
                .where((c) => !chars.contains(c))
                .toList()
              ..shuffle(_rng))
            .take(3);
    _tiles = [...chars, ...distractors]..shuffle(_rng);
    _used = List<bool>.filled(_tiles.length, false);
    _picked.clear();
    _checked = false;
    _shownAtMs = _clock().millisecondsSinceEpoch;
  }

  void _speak() {
    if (!mounted) return;
    context.read<SpeechService>().speak(_current.kana);
  }

  void _tapTile(int i) {
    if (_used[i] || _checked) return;
    setState(() {
      _used[i] = true;
      _picked.add(i);
    });
    if (_picked.length == _targetChars.length) _check();
  }

  void _clear() {
    setState(() {
      for (final i in _picked) {
        _used[i] = false;
      }
      _picked.clear();
    });
  }

  void _check() {
    final built = _picked.map((i) => _tiles[i]).join();
    final correct = built == _current.kana;
    final now = _clock();
    context.read<AnalyticsLog>().record(
      Attempt(
        ts: now.millisecondsSinceEpoch,
        itemId: _current.kana,
        itemType: ItemType.word,
        mode: PracticeMode.dictation.name,
        correct: correct,
        rtMs: now.millisecondsSinceEpoch - _shownAtMs,
        sessionId: _sessionId,
        meta: {'romaji': _current.romaji},
      ),
    );
    // 文字起こし is the words' objective schedule authority: assembled right
    // or not, no self-grade involved.
    context.read<ProgressPersistenceController>().trackWord(
      context.read<WordProgressRepository>().recordAnswer(
        _current.progressId,
        correct: correct,
        at: now,
      ),
    );
    if (correct) _correct++;
    setState(() {
      _checked = true;
      _wasCorrect = correct;
    });
    _speak();
  }

  void _next() {
    if (_index + 1 >= widget.words.length) {
      final store = context.read<KanaProgressRepository>();
      _share = KotenShare.pick(
        pool: kKoten,
        seenKanaCount: store.seenCount,
        rng: _rng,
        season: Season.forMonth(_clock().month),
      );
      setState(() => _done = true);
    } else {
      setState(() {
        _index++;
        _setup();
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
    final target = _targetChars;
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
        const SizedBox(height: 24),
        SpeakButton(text: _current.kana, prominent: true, size: 40),
        const SizedBox(height: 8),
        const Text(
          AppStrings.dictationPrompt,
          style: TextStyle(color: AppColors.inkMuted, fontSize: 14),
        ),
        const SizedBox(height: 28),
        // Answer slots.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < target.length; i++)
              _Slot(
                char: i < _picked.length ? _tiles[_picked[i]] : null,
                state: !_checked
                    ? _SlotState.building
                    : (_wasCorrect ? _SlotState.right : _SlotState.wrong),
              ),
          ],
        ),
        const Spacer(),
        if (!_checked)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var i = 0; i < _tiles.length; i++)
                  if (!_used[i])
                    _Tile(label: _tiles[i], onTap: () => _tapTile(i)),
              ],
            ),
          )
        else
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The same identity block the reading & ferry reveals show. On a
              // miss, lead with the answer's kana; romaji + meaning follow.
              if (!_wasCorrect) ...[
                Text(
                  _current.kana,
                  style: const TextStyle(
                    fontSize: 34,
                    height: 1.1,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 6),
              ],
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
                style: const TextStyle(color: AppColors.ink, fontSize: 18),
              ),
            ],
          ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: _checked
              ? SizedBox(
                  height: 54,
                  child: FilledButton(
                    onPressed: _next,
                    child: const Text(AppStrings.dictationNext),
                  ),
                )
              : SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      side: const BorderSide(color: AppColors.hairline),
                      foregroundColor: AppColors.inkMuted,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _picked.isEmpty ? null : _clear,
                    child: const Text(AppStrings.dictationClear),
                  ),
                ),
        ),
      ],
    );
  }
}

enum _SlotState { building, right, wrong }

class _Slot extends StatelessWidget {
  const _Slot({required this.char, required this.state});

  final String? char;
  final _SlotState state;

  @override
  Widget build(BuildContext context) {
    final border = switch (state) {
      _SlotState.building => AppColors.hairline,
      _SlotState.right => AppColors.success,
      _SlotState.wrong => AppColors.error,
    };
    return Container(
      width: 52,
      height: 64,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: 1.5),
      ),
      child: Text(
        char ?? '',
        style: const TextStyle(
          fontSize: 30,
          color: AppColors.ink,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accentSoft,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 28,
              color: AppColors.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
