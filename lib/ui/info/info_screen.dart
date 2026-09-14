// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/info_drill.dart';
import 'package:kotonoha/ui/core/answer_option_state.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/answer_option_button.dart';
import 'package:kotonoha/ui/core/widgets/answer_option_grid.dart';
import 'package:kotonoha/ui/core/widgets/session_summary.dart';
import 'package:kotonoha/ui/info/info_viewmodel.dart';
import 'package:provider/provider.dart';

/// Hear a travel line, pick the heard amount, time, or headcount.
///
/// Playback success is heard evidence. Seeing Japanese or a meaning hint is
/// recorded separately. A correct tap is never spoken-production evidence,
/// and this room does not write 詞と句 SRS.
///
/// A thin View over [InfoViewModel]: it owns playback (generations, the
/// owned utterance, in-flight state), the lifecycle listener, rendering and
/// navigation. What a completed play *means*, the pick and every analytics
/// write are the ViewModel's; the view reports play outcomes and interrupts.
class InfoScreen extends StatefulWidget {
  const InfoScreen({required this.drills, this.clock, this.onMore, super.key});

  final List<InfoDrill> drills;
  final DateTime Function()? clock;
  final VoidCallback? onMore;

  static Route<void> route(
    List<InfoDrill> drills, {
    DateTime Function()? clock,
    VoidCallback? onMore,
  }) => MaterialPageRoute<void>(
    builder: (_) => InfoScreen(drills: drills, clock: clock, onMore: onMore),
    settings: const RouteSettings(name: 'info-practice'),
  );

  @override
  State<InfoScreen> createState() => _InfoScreenState();
}

class _InfoScreenState extends State<InfoScreen> {
  late final InfoViewModel _vm;
  late final SpeechService _speech;
  late final AppLifecycleListener _lifecycle;
  int? _ownedPlay;
  bool _playable = true;
  bool _playing = false;
  int _playGen = 0;
  int _shownIndex = 0;
  bool _closed = false;

  DateTime Function() get _clock => widget.clock ?? DateTime.now;

  bool get _foreground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  @override
  void initState() {
    super.initState();
    _vm = InfoViewModel(
      drills: widget.drills,
      analytics: context.read<AnalyticsLog>(),
      sessionId: DateTime.now().millisecondsSinceEpoch.toString(),
      clock: widget.clock,
    )..addListener(_onChanged);
    _speech = context.read<SpeechService>();
    _lifecycle = AppLifecycleListener(
      onInactive: _onBackgrounded,
      onHide: _onBackgrounded,
      onPause: _onBackgrounded,
      onDetach: _onBackgrounded,
      onResume: _onResumed,
    );
    _playable = _foreground;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _vm.isFinished) return;
      _scheduleAutoplay();
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _abandonPlayback();
    _vm.removeListener(_onChanged);
    _vm.dispose();
    super.dispose();
  }

  void _onBackgrounded() {
    _playable = false;
    _interrupt();
  }

  void _onResumed() {
    _playable = true;
  }

  void _abandonPlayback() {
    _playGen++;
    final generation = _ownedPlay;
    _ownedPlay = null;
    if (generation != null) {
      unawaited(_speech.stop(generation: generation));
    }
  }

  void _interrupt() {
    _abandonPlayback();
    _vm.noteInterrupted();
    if (!mounted) return;
    setState(() => _playing = false);
  }

  void _scheduleAutoplay() {
    if (!mounted || _vm.isFinished) return;
    if (!_playable || !_foreground) return;
    unawaited(_play());
  }

  /// Session transitions are the ViewModel's; what they mean for the
  /// utterance is the view's. A new drill drops the old play and auto-plays
  /// once it has a frame; the close leaves the last utterance behind.
  void _onChanged() {
    if (_vm.isFinished) {
      if (_closed) return;
      _closed = true;
      _abandonPlayback();
      return;
    }
    if (_vm.index == _shownIndex) return;
    _shownIndex = _vm.index;
    _abandonPlayback();
    setState(() => _playing = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _vm.isFinished) return;
      _scheduleAutoplay();
    });
  }

  Future<void> _play() async {
    if (!mounted || _vm.isFinished) return;
    if (!_playable || !_foreground) return;
    final itemIndex = _vm.index;
    final gen = ++_playGen;
    setState(() => _playing = true);
    final pending = _speech.play(_vm.current.say);
    _ownedPlay = _speech.generation;
    final result = await pending;
    if (!mounted ||
        _vm.isFinished ||
        gen != _playGen ||
        _vm.index != itemIndex) {
      return;
    }
    setState(() => _playing = false);
    _vm.notePlayback(itemIndex: itemIndex, result: result);
  }

  String _promptFor(InfoKind kind) => switch (kind) {
    InfoKind.amount => AppStrings.infoAmountPrompt,
    InfoKind.time => AppStrings.infoTimePrompt,
    InfoKind.personCount => AppStrings.infoPersonPrompt,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.infoTitle)),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _vm,
          builder: (context, _) => _vm.isFinished ? _summary() : _question(),
        ),
      ),
    );
  }

  Widget _summary() {
    final band = ClosingBand.forHour(_clock().hour);
    return SessionSummary(
      headline: AppStrings.infoClose,
      note: AppStrings.infoCloseNote,
      onDone: () => Navigator.of(context).pop(),
      onMore: band == ClosingBand.day ? widget.onMore : null,
    );
  }

  Widget _question() {
    return Column(
      children: [
        const SizedBox(height: 8),
        Text(
          AppStrings.itemProgress(_vm.index + 1, _vm.total),
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
                        child: _cardBody(),
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
          child: _controls(),
        ),
      ],
    );
  }

  Widget _cardBody() {
    final current = _vm.current;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          current.sceneZh,
          key: const ValueKey<String>('info-scene'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.ink,
            fontSize: 15,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        IconButton.filled(
          key: const ValueKey<String>('info-replay'),
          onPressed: () => unawaited(_play()),
          iconSize: 48,
          tooltip: AppStrings.replaySound,
          style: IconButton.styleFrom(
            backgroundColor: AppColors.accentSoft,
            foregroundColor: AppColors.accent,
            padding: const EdgeInsets.all(18),
          ),
          icon: Icon(
            _playing ? Icons.graphic_eq_rounded : Icons.volume_up_rounded,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _promptFor(current.kind),
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.inkMuted, fontSize: 15),
        ),
        const SizedBox(height: 6),
        const Text(
          AppStrings.infoNotSpeaking,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.inkMuted,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        if (_vm.sawText) ...[
          const SizedBox(height: 16),
          Text(
            current.promptKana,
            key: const ValueKey<String>('info-prompt-kana'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 28,
              height: 1.2,
              fontWeight: FontWeight.w500,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            current.promptRomaji,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.accent,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (_vm.hinted) ...[
          const SizedBox(height: 8),
          Text(
            current.promptMeaning,
            key: const ValueKey<String>('info-prompt-meaning'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.ink, fontSize: 16),
          ),
        ],
        if (_blockMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            _blockMessage!,
            key: const ValueKey<String>('info-block'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.inkMuted,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
        const SizedBox(height: 16),
        AnswerOptionGrid(
          crossAxisCount: 1,
          children: [
            for (final option in _vm.answerOrder)
              AnswerOptionButton(
                key: ValueKey<String>('info-choice-$option'),
                label: option,
                fontSize: 18,
                state: _optionState(option),
                onTap: _vm.isAnswered ? null : () => _vm.pickAnswer(option),
              ),
          ],
        ),
      ],
    );
  }

  OptionState _optionState(String option) {
    final pick = _vm.answerPick;
    if (pick == null) return OptionState.idle;
    if (_vm.isCorrect(option)) {
      return option == pick ? OptionState.correct : OptionState.revealed;
    }
    if (option == pick) return OptionState.wrong;
    return OptionState.dimmed;
  }

  String? get _blockMessage {
    if (_vm.isHeard) return null;
    return switch (_vm.lastPlay) {
      SpeechPlaybackResult.unavailable => AppStrings.listeningUnavailable,
      SpeechPlaybackResult.failed => AppStrings.listeningFailed,
      SpeechPlaybackResult.interrupted => AppStrings.listeningInterrupted,
      SpeechPlaybackResult.played => null,
      null => null,
    };
  }

  Widget _controls() {
    if (!_vm.isAnswered) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey<String>('info-hint'),
                  onPressed: _vm.showHint,
                  child: const Text(AppStrings.infoHint),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey<String>('info-show-text'),
                  onPressed: _vm.showText,
                  child: const Text(AppStrings.infoShowText),
                ),
              ),
            ],
          ),
          if (!_vm.isHeard) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const ValueKey<String>('info-skip'),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.hairline),
                  foregroundColor: AppColors.inkMuted,
                ),
                onPressed: _vm.skipUnheard,
                child: const Text(AppStrings.listeningSkip),
              ),
            ),
          ],
        ],
      );
    }
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        key: const ValueKey<String>('info-next'),
        onPressed: _vm.advance,
        child: const Text(AppStrings.listeningNext),
      ),
    );
  }
}
