// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/session_summary.dart';
import 'package:kotonoha/ui/core/widgets/speak_button.dart';
import 'package:provider/provider.dart';

/// Handwriting recall: show a romaji prompt, the learner writes the kana on
/// paper (their 習字本), then reveals the answer and self-grades. Combines
/// retrieval + generation + handwriting — the strongest memory path.
class WritingScreen extends StatefulWidget {
  const WritingScreen({required this.targets, required this.title, super.key});

  final List<Kana> targets;
  final String title;

  static Route<void> route(List<Kana> targets, String title) =>
      MaterialPageRoute<void>(
        builder: (_) => WritingScreen(targets: targets, title: title),
      );

  @override
  State<WritingScreen> createState() => _WritingScreenState();
}

class _WritingScreenState extends State<WritingScreen> {
  final String _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
  late final SpeechService _speech;
  late final AppLifecycleListener _lifecycle;
  int? _ownedPlay;
  int _index = 0;
  bool _revealed = false;
  int _correct = 0;
  bool _done = false;

  Kana get _current => widget.targets[_index];

  @override
  void initState() {
    super.initState();
    _speech = context.read<SpeechService>();
    _lifecycle = AppLifecycleListener(
      onInactive: _abandonOwnedPlayback,
      onHide: _abandonOwnedPlayback,
      onPause: _abandonOwnedPlayback,
      onDetach: _abandonOwnedPlayback,
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _abandonOwnedPlayback();
    super.dispose();
  }

  void _abandonOwnedPlayback() {
    final generation = _ownedPlay;
    _ownedPlay = null;
    if (generation != null) {
      unawaited(_speech.stop(generation: generation));
    }
  }

  void _speak() {
    unawaited(_speech.speak(_current.character));
    _ownedPlay = _speech.generation;
  }

  void _grade(bool correct) {
    final now = DateTime.now();
    context.read<ProgressPersistenceController>().trackKana(
      context.read<KanaProgressRepository>().recordAnswer(
        _current,
        correct: correct,
        at: now,
      ),
    );
    context.read<AnalyticsLog>().recordObserved(
      Attempt(
        ts: now.millisecondsSinceEpoch,
        itemId: _current.id,
        mode: PracticeMode.writing.name,
        correct: correct,
        sessionId: _sessionId,
        meta: const {AttemptMeta.direction: 'write'},
      ),
    );
    if (correct) _correct++;
    _abandonOwnedPlayback();
    if (_index + 1 >= widget.targets.length) {
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
    headline: AppStrings.writingSummary(_correct, widget.targets.length),
    note: AppStrings.closingNote(
      widget.targets.first.character,
      band: ClosingBand.forHour(DateTime.now().hour),
    ),
    onDone: () => Navigator.of(context).pop(),
  );

  Widget _question() {
    return Column(
      children: [
        const SizedBox(height: 8),
        Text(
          '${_index + 1} / ${widget.targets.length}',
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
                  Text(
                    _current.romaji,
                    style: const TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                  SpeakButton(
                    text: _current.character,
                    size: 30,
                    onPlay: _speak,
                  ),
                  const SizedBox(height: 12),
                  if (!_revealed)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        AppStrings.writePrompt,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.inkMuted,
                          fontSize: 15,
                        ),
                      ),
                    )
                  else ...[
                    const Divider(height: 40, indent: 40, endIndent: 40),
                    Text(
                      _current.character,
                      style: const TextStyle(
                        fontSize: 120,
                        height: 1.0,
                        color: AppColors.ink,
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
                        child: const Text(AppStrings.iMissed),
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
                        child: const Text(AppStrings.iGotIt),
                      ),
                    ),
                  ],
                )
              : SizedBox(
                  height: 54,
                  child: FilledButton(
                    onPressed: () => setState(() => _revealed = true),
                    child: const Text(AppStrings.revealAnswer),
                  ),
                ),
        ),
      ],
    );
  }
}
