// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/reply_drill.dart';
import 'package:kotonoha/ui/core/answer_option_state.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/answer_option_button.dart';
import 'package:kotonoha/ui/core/widgets/answer_option_grid.dart';
import 'package:kotonoha/ui/core/widgets/session_summary.dart';
import 'package:kotonoha/ui/reply/reply_viewmodel.dart';
import 'package:provider/provider.dart';

/// Hear a station ask, pick the intent, pick a short reply.
///
/// Playback success is heard evidence. Seeing Japanese or a meaning hint is
/// recorded separately. A correct tap is never spoken-production evidence,
/// and this room does not write 詞と句 SRS.
///
/// A thin View over [ReplyViewModel]: it owns playback (generations, the
/// owned utterance, in-flight state), the lifecycle listener, rendering and
/// navigation. What a completed play *means*, the picks and every analytics
/// write are the ViewModel's; the view reports play outcomes and interrupts.
class ReplyScreen extends StatefulWidget {
  const ReplyScreen({
    required this.drills,
    this.scene = ReplySceneId.station,
    this.clock,
    this.onMore,
    super.key,
  });

  final List<ReplyDrill> drills;
  final ReplySceneId scene;
  final DateTime Function()? clock;
  final VoidCallback? onMore;

  static Route<void> route(
    List<ReplyDrill> drills, {
    ReplySceneId scene = ReplySceneId.station,
    DateTime Function()? clock,
    VoidCallback? onMore,
  }) => MaterialPageRoute<void>(
    builder: (_) =>
        ReplyScreen(drills: drills, scene: scene, clock: clock, onMore: onMore),
    settings: const RouteSettings(name: 'reply-practice'),
  );

  @override
  State<ReplyScreen> createState() => _ReplyScreenState();
}

class _ReplyScreenState extends State<ReplyScreen> {
  late final ReplyViewModel _vm;
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
    _vm = ReplyViewModel(
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.replyTitle)),
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
      headline: AppStrings.replyClose,
      note: AppStrings.replyCloseNote,
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
    final prompt = _vm.beat == ReplyBeat.intent
        ? switch (widget.scene) {
            ReplySceneId.station => AppStrings.replyIntentPrompt,
            ReplySceneId.clothing ||
            ReplySceneId.restaurant ||
            ReplySceneId.convenience ||
            ReplySceneId.shrine ||
            ReplySceneId.parkQueue => AppStrings.replyClothingIntentPrompt,
            ReplySceneId.help => AppStrings.replyHelpIntentPrompt,
          }
        : AppStrings.replyReplyPrompt;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          current.sceneZh,
          key: const ValueKey<String>('reply-scene'),
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
          key: const ValueKey<String>('reply-replay'),
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
          prompt,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.inkMuted, fontSize: 15),
        ),
        const SizedBox(height: 6),
        const Text(
          AppStrings.replyNotSpeaking,
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
            key: const ValueKey<String>('reply-prompt-kana'),
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
            key: const ValueKey<String>('reply-prompt-meaning'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.ink, fontSize: 16),
          ),
        ],
        if (_blockMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            _blockMessage!,
            key: const ValueKey<String>('reply-block'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.inkMuted,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (_vm.beat == ReplyBeat.intent)
          _choiceColumn(
            options: _vm.intentOrder,
            pick: _vm.intentPick,
            isCorrect: _vm.isIntentCorrect,
            prefix: 'reply-intent',
            onPick: _vm.pickIntent,
          )
        else
          _choiceColumn(
            options: _vm.replyOrder,
            pick: _vm.replyPick,
            isCorrect: _vm.isReplyCorrect,
            prefix: 'reply-choice',
            onPick: _vm.pickReply,
          ),
        if (_vm.replyPick != null) ...[
          const SizedBox(height: 12),
          Text(
            current.replyCorrectMeaning,
            key: const ValueKey<String>('reply-answer-meaning'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.ink, fontSize: 16),
          ),
        ],
      ],
    );
  }

  Widget _choiceColumn({
    required List<String> options,
    required String? pick,
    required bool Function(String) isCorrect,
    required String prefix,
    required void Function(String) onPick,
  }) {
    return AnswerOptionGrid(
      crossAxisCount: 1,
      children: [
        for (final option in options)
          AnswerOptionButton(
            key: ValueKey<String>('$prefix-$option'),
            label: option,
            fontSize: 18,
            state: _optionState(option, pick, isCorrect),
            onTap: pick == null ? () => onPick(option) : null,
          ),
      ],
    );
  }

  OptionState _optionState(
    String option,
    String? pick,
    bool Function(String) isCorrect,
  ) {
    if (pick == null) return OptionState.idle;
    if (isCorrect(option)) {
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
    if (_vm.beat == ReplyBeat.intent && _vm.intentPick == null) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey<String>('reply-hint'),
                  onPressed: _vm.showHint,
                  child: const Text(AppStrings.replyHint),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey<String>('reply-show-text'),
                  onPressed: _vm.showText,
                  child: const Text(AppStrings.replyShowText),
                ),
              ),
            ],
          ),
          if (!_vm.isHeard) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const ValueKey<String>('reply-skip'),
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
    if (_vm.beat == ReplyBeat.intent && _vm.intentPick != null) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          key: const ValueKey<String>('reply-to-answer'),
          onPressed: _vm.toReply,
          child: const Text(AppStrings.replyReplyPrompt),
        ),
      );
    }
    if (_vm.replyPick != null) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          key: const ValueKey<String>('reply-next'),
          onPressed: _vm.advance,
          child: const Text(AppStrings.listeningNext),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
