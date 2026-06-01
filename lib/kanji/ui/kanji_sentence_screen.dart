// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/kanji/domain/models/kanji_phrase.dart';
import 'package:kotonoha/kanji/ui/ruby_text.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/session_summary.dart';
import 'package:kotonoha/ui/core/widgets/speak_button.dart';
import 'package:provider/provider.dart';

/// The furigana-fade reading bridge: read a short kanji sentence (furigana over
/// each kanji thins out as that reading matures via the kanji practice), then
/// reveal the full kana reading + meaning + audio and self-grade. Records a
/// reading [Attempt]; the per-reading SRS is driven by the kanji practice, not
/// here — this is the consumption side that the kanji work unlocks.
class KanjiSentenceScreen extends StatefulWidget {
  const KanjiSentenceScreen({
    required this.phrases,
    required this.title,
    super.key,
  });

  final List<KanjiPhrase> phrases;
  final String title;

  static Route<void> route(List<KanjiPhrase> phrases, String title) =>
      MaterialPageRoute<void>(
        builder: (_) => KanjiSentenceScreen(phrases: phrases, title: title),
      );

  @override
  State<KanjiSentenceScreen> createState() => _KanjiSentenceScreenState();
}

class _KanjiSentenceScreenState extends State<KanjiSentenceScreen> {
  final String _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
  int _index = 0;
  bool _revealed = false;
  int _correct = 0;
  bool _done = false;

  KanjiPhrase get _current => widget.phrases[_index];

  void _reveal() {
    context.read<SpeechService>().speak(_current.reading);
    setState(() => _revealed = true);
  }

  void _grade(bool correct) {
    final now = DateTime.now();
    context.read<AnalyticsLog>().record(
      Attempt(
        ts: now.millisecondsSinceEpoch,
        itemId: _current.written,
        mode: PracticeMode.reading.name,
        correct: correct,
        sessionId: _sessionId,
        meta: {'reading': _current.reading},
      ),
    );
    if (correct) _correct++;
    if (_index + 1 >= widget.phrases.length) {
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

  Widget _summary() => SessionSummary(
    headline: AppStrings.readingSummary(_correct, widget.phrases.length),
    onDone: () => Navigator.of(context).pop(),
  );

  Widget _question() {
    final repo = context.read<KanjiReadingRepository>();
    return Column(
      children: [
        const SizedBox(height: 8),
        Text(
          '${_index + 1} / ${widget.phrases.length}',
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
                      srsLevelOf: (id) => repo.statForReading(id).srsLevel,
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
                    SpeakButton(text: _current.reading, size: 28),
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
