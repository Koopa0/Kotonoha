// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/session_summary.dart';
import 'package:kotonoha/ui/core/widgets/speak_button.dart';
import 'package:kotonoha/ui/writing/writing_viewmodel.dart';
import 'package:provider/provider.dart';

/// Handwriting recall: show a romaji prompt, the learner writes the kana on
/// paper (their 習字本), then reveals the answer and self-grades. Combines
/// retrieval + generation + handwriting — the strongest memory path.
///
/// A thin View over [WritingViewModel]: it owns the speaker and the
/// lifecycle listener, renders, and navigates. The reveal, the self-grade
/// and every schedule or analytics write are the ViewModel's.
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
  late final WritingViewModel _vm;
  late final SpeechService _speech;
  late final AppLifecycleListener _lifecycle;
  int? _ownedPlay;
  int _shownIndex = 0;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _vm = WritingViewModel(
      targets: widget.targets,
      kana: context.read<KanaProgressRepository>(),
      persistence: context.read<ProgressPersistenceController>(),
      analytics: context.read<AnalyticsLog>(),
      sessionId: DateTime.now().millisecondsSinceEpoch.toString(),
    )..addListener(_onChanged);
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
    _vm.removeListener(_onChanged);
    _vm.dispose();
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
    unawaited(_speech.speak(_vm.current.character));
    _ownedPlay = _speech.generation;
  }

  /// A grade leaves the kana behind: the owned utterance goes with it,
  /// whether the next kana or the close follows.
  void _onChanged() {
    if (_vm.isFinished) {
      if (_closed) return;
      _closed = true;
      _abandonOwnedPlayback();
      return;
    }
    if (_vm.index == _shownIndex) return;
    _shownIndex = _vm.index;
    _abandonOwnedPlayback();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _vm,
          builder: (context, _) => _vm.isFinished ? _summary() : _question(),
        ),
      ),
    );
  }

  Widget _summary() => SessionSummary(
    headline: AppStrings.writingSummary(_vm.correctCount, _vm.total),
    note: AppStrings.closingNote(
      widget.targets.first.character,
      band: ClosingBand.forHour(DateTime.now().hour),
    ),
    onDone: () => Navigator.of(context).pop(),
  );

  Widget _question() {
    final current = _vm.current;
    final revealed = _vm.isRevealed;
    return Column(
      children: [
        const SizedBox(height: 8),
        Text(
          '${_vm.index + 1} / ${_vm.total}',
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
                    current.romaji,
                    style: const TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                  SpeakButton(
                    text: current.character,
                    size: 30,
                    onPlay: _speak,
                  ),
                  const SizedBox(height: 12),
                  if (!revealed)
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
                      current.character,
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
          child: revealed
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
                        onPressed: () => _vm.grade(correct: false),
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
                        onPressed: () => _vm.grade(correct: true),
                        child: const Text(AppStrings.iGotIt),
                      ),
                    ),
                  ],
                )
              : SizedBox(
                  height: 54,
                  child: FilledButton(
                    onPressed: _vm.reveal,
                    child: const Text(AppStrings.revealAnswer),
                  ),
                ),
        ),
      ],
    );
  }
}
