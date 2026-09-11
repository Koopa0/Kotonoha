// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/info_drill.dart';
import 'package:kotonoha/domain/use_cases/reply_session.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/answer_option_button.dart';
import 'package:kotonoha/ui/core/widgets/answer_option_grid.dart';
import 'package:kotonoha/ui/core/widgets/session_summary.dart';
import 'package:provider/provider.dart';

/// Hear a travel line, pick the heard amount, time, or headcount.
///
/// Playback success is heard evidence. Seeing Japanese or a meaning hint is
/// recorded separately. A correct tap is never spoken-production evidence,
/// and this room does not write 詞と句 SRS.
class InfoScreen extends StatefulWidget {
  const InfoScreen({
    required this.drills,
    this.clock,
    this.onMore,
    super.key,
  });

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
  final String _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
  final Random _rng = Random();

  late final SpeechService _speech;
  late final AppLifecycleListener _lifecycle;
  int? _ownedPlay;
  bool _playable = true;

  int _index = 0;
  bool _heard = false;
  bool _sawText = false;
  bool _hinted = false;
  bool _playing = false;
  bool _done = false;
  String? _answerPick;
  int _heardAtMs = 0;
  int _playGen = 0;
  SpeechPlaybackResult? _lastPlay;
  late List<String> _answerOrder;

  DateTime Function() get _clock => widget.clock ?? DateTime.now;

  InfoDrill get _current => widget.drills[_index];

  bool get _foreground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  @override
  void initState() {
    super.initState();
    _speech = context.read<SpeechService>();
    _shuffleChoices();
    _lifecycle = AppLifecycleListener(
      onInactive: _onBackgrounded,
      onHide: _onBackgrounded,
      onPause: _onBackgrounded,
      onDetach: _onBackgrounded,
      onResume: _onResumed,
    );
    _playable = _foreground;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _done) return;
      _scheduleAutoplay();
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _abandonPlayback();
    super.dispose();
  }

  void _onBackgrounded() {
    _playable = false;
    unawaited(_interrupt());
  }

  void _onResumed() {
    _playable = true;
  }

  void _shuffleChoices() {
    _answerOrder = List<String>.of(_current.answerChoices)..shuffle(_rng);
  }

  void _abandonPlayback() {
    _playGen++;
    final generation = _ownedPlay;
    _ownedPlay = null;
    if (generation != null) {
      unawaited(_speech.stop(generation: generation));
    }
  }

  Future<void> _interrupt() async {
    _abandonPlayback();
    if (!mounted) return;
    setState(() {
      _playing = false;
      _lastPlay = SpeechPlaybackResult.interrupted;
    });
  }

  void _scheduleAutoplay() {
    if (!mounted || _done) return;
    if (!_playable || !_foreground) return;
    unawaited(_play());
  }

  Future<void> _play() async {
    if (!mounted || _done) return;
    if (!_playable || !_foreground) return;
    final itemId = _current.id;
    final gen = ++_playGen;
    setState(() => _playing = true);
    final pending = _speech.play(_current.say);
    _ownedPlay = _speech.generation;
    final result = await pending;
    if (!mounted || _done || gen != _playGen || _current.id != itemId) {
      return;
    }
    setState(() {
      _playing = false;
      _lastPlay = result;
      if (result != SpeechPlaybackResult.played) return;
      _heard = true;
      if (_heardAtMs == 0) {
        _heardAtMs = _clock().millisecondsSinceEpoch;
      }
    });
  }

  String _promptFor(InfoKind kind) => switch (kind) {
    InfoKind.amount => AppStrings.infoAmountPrompt,
    InfoKind.time => AppStrings.infoTimePrompt,
    InfoKind.personCount => AppStrings.infoPersonPrompt,
  };

  void _pickAnswer(String choice) {
    if (_answerPick != null) return;
    final correct = choice == _current.correctAnswer;
    final evidence = ReplyEvidence.classify(
      heard: _heard,
      sawText: _sawText,
      usedHint: _hinted,
      correct: correct,
    );
    _log(choice: choice, evidence: evidence);
    setState(() => _answerPick = choice);
  }

  void _log({required String choice, required String evidence}) {
    final now = _clock();
    final scored = _heard;
    final correct =
        evidence == ReplyEvidence.independent ||
        evidence == ReplyEvidence.peeked ||
        evidence == ReplyEvidence.hinted;
    context.read<AnalyticsLog>().recordObserved(
      Attempt(
        ts: now.millisecondsSinceEpoch,
        itemId: _current.id,
        itemType: ItemType.word,
        mode: PracticeMode.info.name,
        correct: scored && correct,
        rtMs: scored && _heardAtMs != 0
            ? now.millisecondsSinceEpoch - _heardAtMs
            : 0,
        sessionId: _sessionId,
        meta: {
          AttemptMeta.beat: _current.kind.name,
          AttemptMeta.evidence: evidence,
          AttemptMeta.heard: _heard,
          AttemptMeta.prompted: _sawText,
          AttemptMeta.hinted: _hinted,
          AttemptMeta.scored: scored,
          AttemptMeta.playback:
              (_lastPlay ?? SpeechPlaybackResult.interrupted).name,
          if (!correct && choice.isNotEmpty) AttemptMeta.distractor: choice,
        },
      ),
    );
  }

  void _advance() {
    if (_index + 1 >= widget.drills.length) {
      _abandonPlayback();
      setState(() => _done = true);
      return;
    }
    _abandonPlayback();
    setState(() {
      _index++;
      _heard = false;
      _sawText = false;
      _hinted = false;
      _playing = false;
      _answerPick = null;
      _heardAtMs = 0;
      _lastPlay = null;
      _shuffleChoices();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _done) return;
      _scheduleAutoplay();
    });
  }

  void _skipUnheard() {
    if (_heard || _answerPick != null) return;
    _log(choice: '', evidence: ReplyEvidence.unheard);
    _advance();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.infoTitle)),
      body: SafeArea(child: _done ? _summary() : _question()),
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
          AppStrings.itemProgress(_index + 1, widget.drills.length),
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
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _current.sceneZh,
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
          _promptFor(_current.kind),
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
        if (_sawText) ...[
          const SizedBox(height: 16),
          Text(
            _current.promptKana,
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
            _current.promptRomaji,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.accent,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (_hinted) ...[
          const SizedBox(height: 8),
          Text(
            _current.promptMeaning,
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
            for (final option in _answerOrder)
              AnswerOptionButton(
                key: ValueKey<String>('info-choice-$option'),
                label: option,
                fontSize: 18,
                state: _optionState(option),
                onTap: _answerPick == null ? () => _pickAnswer(option) : null,
              ),
          ],
        ),
      ],
    );
  }

  OptionState _optionState(String option) {
    final pick = _answerPick;
    final correct = _current.correctAnswer;
    if (pick == null) return OptionState.idle;
    if (option == correct) {
      return option == pick ? OptionState.correct : OptionState.revealed;
    }
    if (option == pick) return OptionState.wrong;
    return OptionState.dimmed;
  }

  String? get _blockMessage {
    if (_heard) return null;
    return switch (_lastPlay) {
      SpeechPlaybackResult.unavailable => AppStrings.listeningUnavailable,
      SpeechPlaybackResult.failed => AppStrings.listeningFailed,
      SpeechPlaybackResult.interrupted => AppStrings.listeningInterrupted,
      SpeechPlaybackResult.played => null,
      null => null,
    };
  }

  Widget _controls() {
    if (_answerPick == null) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey<String>('info-hint'),
                  onPressed: () => setState(() => _hinted = true),
                  child: const Text(AppStrings.infoHint),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey<String>('info-show-text'),
                  onPressed: () => setState(() => _sawText = true),
                  child: const Text(AppStrings.infoShowText),
                ),
              ),
            ],
          ),
          if (!_heard) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const ValueKey<String>('info-skip'),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.hairline),
                  foregroundColor: AppColors.inkMuted,
                ),
                onPressed: _skipUnheard,
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
        onPressed: _advance,
        child: const Text(AppStrings.listeningNext),
      ),
    );
  }
}
