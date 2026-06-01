// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/kanji/data/repositories/kanji_reading_repository.dart';
import 'package:kotonoha/kanji/domain/models/kanji_entry.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_session.dart';
import 'package:kotonoha/kanji/kanji_mode.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/speak_button.dart';
import 'package:provider/provider.dart';

/// Kanji reading recall: show a kanji + its on/kun cue, the learner recalls the
/// reading, then reveals the kana reading + example word + audio and self-grades.
/// Records a per-reading [Attempt] (itemType=kanji) and drives the per-reading
/// Leitner via [KanjiReadingRepository]. Meaning is shown only as quiet context —
/// it's never graded (the learner already owns it).
class KanjiQuizScreen extends StatefulWidget {
  const KanjiQuizScreen({
    required this.prompts,
    required this.title,
    super.key,
  });

  final List<KanjiPrompt> prompts;
  final String title;

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
  bool _revealed = false;
  int _correct = 0;
  bool _done = false;

  KanjiPrompt get _current => widget.prompts[_index];

  String get _spoken => _current.reading.exampleWord ?? _current.reading.text;

  void _reveal() {
    context.read<SpeechService>().speak(_spoken);
    setState(() => _revealed = true);
  }

  void _grade(bool correct) {
    final now = DateTime.now();
    final p = _current;
    context.read<KanjiReadingRepository>().recordAnswer(
      p.readingId,
      correct: correct,
      at: now,
    );
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
        },
      ),
    );
    if (correct) _correct++;
    if (_index + 1 >= widget.prompts.length) {
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppStrings.readingSummary(_correct, widget.prompts.length),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(AppStrings.done),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _question() {
    final p = _current;
    final kindLabel = p.reading.kind == ReadingKind.on
        ? AppStrings.kanjiOnyomi
        : AppStrings.kanjiKunyomi;
    final others = p.entry.readings
        .where((r) => r.text != p.reading.text)
        .map((r) => r.text)
        .join('・');
    return Column(
      children: [
        const SizedBox(height: 8),
        Text(
          '${_index + 1} / ${widget.prompts.length}',
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
                  // The on/kun cue tells the learner which reading to recall.
                  _KindChip(label: kindLabel),
                  const SizedBox(height: 16),
                  Text(
                    p.entry.char,
                    style: const TextStyle(
                      fontSize: 96,
                      height: 1.0,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    p.entry.meaningZh,
                    style: const TextStyle(
                      color: AppColors.inkMuted,
                      fontSize: 15,
                    ),
                  ),
                  if (!_revealed)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        AppStrings.kanjiPrompt,
                        style: TextStyle(
                          color: AppColors.inkMuted,
                          fontSize: 14,
                        ),
                      ),
                    )
                  else ...[
                    const Divider(height: 36, indent: 48, endIndent: 48),
                    Text(
                      p.reading.text,
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                    if (p.reading.exampleWord != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${p.reading.exampleWord}'
                          '${p.reading.exampleMeaning != null ? '・${p.reading.exampleMeaning}' : ''}',
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    SpeakButton(text: _spoken, size: 28),
                    if (others.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          AppStrings.kanjiAlsoReads(others),
                          style: const TextStyle(
                            color: AppColors.inkMuted,
                            fontSize: 13,
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
                    child: const Text(AppStrings.kanjiReveal),
                  ),
                ),
        ),
      ],
    );
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
