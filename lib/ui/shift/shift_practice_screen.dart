// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/shift_drill.dart';
import 'package:kotonoha/ui/core/answer_option_state.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/answer_option_button.dart';
import 'package:kotonoha/ui/core/widgets/session_summary.dart';
import 'package:kotonoha/ui/core/widgets/speak_button.dart';
import 'package:kotonoha/ui/shift/shift_history.dart';
import 'package:kotonoha/ui/shift/shift_persist_notice.dart';
import 'package:kotonoha/ui/shift/shift_practice_viewmodel.dart';
import 'package:provider/provider.dart';

/// Original swap-sentence practice: teach new forms first, then read, then
/// (for action drills) restore the dictionary form and name who / what,
/// then sense. Hints do not leak another check. Free-text is never
/// auto-graded. Evidence is logged per beat and check; word / phrase SRS
/// is never touched.
///
/// A thin View over [ShiftPracticeViewModel]: it owns the speaker, the
/// lifecycle listener, the free-text pad, rendering and navigation. The
/// beats and phases, every check's evidence and write, and the
/// durable-write state are the ViewModel's.
class ShiftPracticeScreen extends StatefulWidget {
  const ShiftPracticeScreen({
    required this.drill,
    this.sourceUrl,
    this.onMore,
    this.clock,
    this.lane = ShiftLane.sameDay,
    this.beats,
    this.firstUnseen = false,
    super.key,
  });

  final ShiftDrill drill;
  final String? sourceUrl;
  final VoidCallback? onMore;
  final DateTime Function()? clock;
  final ShiftLane lane;

  /// Which pair beats this sitting plays. #73 supplies a reserved-shift
  /// list; same-day practice still defaults to base then shift.
  final List<ShiftBeat>? beats;
  final bool firstUnseen;

  static Route<void> route(
    ShiftDrill drill, {
    String? sourceUrl,
    VoidCallback? onMore,
    DateTime Function()? clock,
    ShiftLane lane = ShiftLane.sameDay,
    List<ShiftBeat>? beats,
    bool firstUnseen = false,
  }) => MaterialPageRoute<void>(
    builder: (_) => ShiftPracticeScreen(
      drill: drill,
      sourceUrl: sourceUrl,
      onMore: onMore,
      clock: clock,
      lane: lane,
      beats: beats,
      firstUnseen: firstUnseen,
    ),
  );

  @override
  State<ShiftPracticeScreen> createState() => _ShiftPracticeScreenState();
}

class _ShiftPracticeScreenState extends State<ShiftPracticeScreen> {
  final TextEditingController _note = TextEditingController();
  late final ShiftPracticeViewModel _vm;
  late final SpeechService _speech;
  late final AppLifecycleListener _lifecycle;
  late ShiftBeat _shownBeat;
  int? _ownedPlay;
  bool _playable = true;

  DateTime Function() get _clock => widget.clock ?? DateTime.now;

  String? get _laneCaption {
    if (_vm.isUnsaved) return AppStrings.shiftPersistFailed;
    switch (widget.lane) {
      case ShiftLane.hold:
        return AppStrings.shiftHeldUntilTomorrow;
      case ShiftLane.confirm:
        return widget.firstUnseen
            ? AppStrings.shiftFirstUnseen
            : AppStrings.shiftAlreadyShown;
      case ShiftLane.review:
        return AppStrings.shiftReviewOnly;
      case ShiftLane.sameDay:
        return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _vm = ShiftPracticeViewModel(
      drill: widget.drill,
      analytics: context.read<AnalyticsLog>(),
      persistence: context.read<ProgressPersistenceController>(),
      sessionId: DateTime.now().millisecondsSinceEpoch.toString(),
      sourceUrl: widget.sourceUrl,
      lane: widget.lane,
      beats: widget.beats,
      firstUnseen: widget.firstUnseen,
      clock: widget.clock,
    )..addListener(_onChanged);
    _shownBeat = _vm.beat;
    _speech = context.read<SpeechService>();
    _lifecycle = AppLifecycleListener(
      onInactive: _abandonOwnedPlayback,
      onHide: _abandonOwnedPlayback,
      onPause: _abandonOwnedPlayback,
      onDetach: _abandonOwnedPlayback,
      onResume: () => _playable = true,
    );
    _playable = _foreground;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_vm.start());
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _abandonOwnedPlayback();
    _note.dispose();
    _vm.removeListener(_onChanged);
    _vm.dispose();
    super.dispose();
  }

  bool get _foreground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  void _abandonOwnedPlayback() {
    _playable = false;
    final generation = _ownedPlay;
    _ownedPlay = null;
    if (generation != null) {
      unawaited(_speech.stop(generation: generation));
    }
  }

  void _speakText(String kana) {
    if (!mounted || !_playable || !_foreground) return;
    unawaited(_speech.speak(kana.replaceAll(' ', '')));
    _ownedPlay = _speech.generation;
  }

  void _speak() => _speakText(_vm.say);

  /// The reading commit sounds the sentence — a comfort after the commit,
  /// never evidence, so it stays the view's.
  void _commitRead({required bool unprompted}) {
    _speak();
    _vm.commitRead(unprompted: unprompted);
  }

  /// A new beat starts with an empty pad; everything else re-renders.
  void _onChanged() {
    if (_vm.beat == _shownBeat) return;
    _shownBeat = _vm.beat;
    _note.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: const Text(AppStrings.shiftTitle)),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _vm,
          builder: (context, _) => _vm.isFinished ? _summary() : _body(),
        ),
      ),
    );
  }

  Widget _summary() {
    final band = ClosingBand.forHour(_clock().hour);
    final holdNote = widget.lane == ShiftLane.hold && !_vm.isUnsaved
        ? '${AppStrings.shiftCloseNote}\n\n${AppStrings.shiftHeldUntilTomorrow}'
        : AppStrings.shiftCloseNote;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              children: [
                if (_vm.history.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: ShiftHistoryView(grades: _vm.history),
                  ),
                if (_vm.isUnsaved)
                  ShiftPersistNotice(
                    retrying: _vm.isRetrying,
                    onRetry: () => unawaited(_vm.retryPersist()),
                  ),
                SessionSummary(
                  headline: AppStrings.shiftClose,
                  note: holdNote,
                  onDone: () => Navigator.of(context).pop(),
                  onMore: band == ClosingBand.day ? widget.onMore : null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _body() {
    if (_vm.phase == ShiftPhase.intro) return _introBody();
    final source = widget.sourceUrl?.trim();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        children: [
          Column(
            children: [
              Text(
                AppStrings.itemProgress(_vm.beatIndex + 1, _vm.beats.length),
                style: const TextStyle(
                  color: AppColors.inkMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (source != null && source.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    AppStrings.shiftSourceChip(source),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.inkMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
              if (_laneCaption != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _laneCaption!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.inkMuted,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                  child: Column(
                    children: [
                      if (_vm.beat == ShiftBeat.shift) ...[
                        Text(
                          widget.lane == ShiftLane.confirm
                              ? AppStrings.shiftConfirmLead
                              : _bridgeCopy(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.inkMuted,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      Text(
                        _vm.sentence.kana,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 44,
                          height: 1.2,
                          fontWeight: FontWeight.w500,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ..._phaseCopy(),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Padding(padding: const EdgeInsets.only(top: 16), child: _actions()),
        ],
      ),
    );
  }

  Widget _introBody() {
    final card = _vm.intro[_vm.introIndex];
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    children: [
                      Text(
                        AppStrings.shiftIntroProgress(
                          _vm.introIndex + 1,
                          _vm.intro.length,
                        ),
                        style: const TextStyle(
                          color: AppColors.inkMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        AppStrings.shiftIntroLead,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.inkMuted,
                          height: 1.55,
                        ),
                      ),
                      const SizedBox(height: 16),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: AppColors.hairline),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                          child: Column(
                            children: [
                              Text(
                                card.title,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(height: 16),
                              for (final line in card.lines) ...[
                                Text(
                                  line.kana,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 36,
                                    height: 1.2,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  line.romaji,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.accent,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  line.meaning,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: AppColors.ink,
                                    height: 1.45,
                                  ),
                                ),
                                if (line.note.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      line.note,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: AppColors.inkMuted,
                                        height: 1.45,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                SpeakButton(
                                  text: line.kana.replaceAll(' ', ''),
                                  size: 28,
                                  onPlay: () => _speakText(line.kana),
                                ),
                                const SizedBox(height: 16),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: FilledButton(
                      onPressed: _vm.advanceIntro,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                      ),
                      child: Text(
                        _vm.introIndex + 1 < _vm.intro.length
                            ? AppStrings.shiftIntroNext
                            : AppStrings.shiftIntroDone,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _bridgeCopy() {
    switch (widget.drill.change) {
      case ShiftChange.noun:
        return AppStrings.shiftBridgeNoun;
      case ShiftChange.modifier:
        return AppStrings.shiftBridgeModifier;
      case ShiftChange.actor:
        return AppStrings.shiftBridgeActor;
      case ShiftChange.item:
        return AppStrings.shiftBridgeItem;
    }
  }

  List<Widget> _phaseCopy() {
    switch (_vm.phase) {
      case ShiftPhase.intro:
        return const [];
      case ShiftPhase.readCommit:
        return const [
          Text(
            AppStrings.readPrompt,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.inkMuted, fontSize: 15),
          ),
        ];
      case ShiftPhase.readGrade:
        return [
          const Divider(height: 28, indent: 28, endIndent: 28),
          Text(
            _vm.sentence.romaji,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
            ),
          ),
          SpeakButton(text: _vm.say, size: 30, onPlay: _speak),
        ];
      case ShiftPhase.verbAsk:
      case ShiftPhase.verbReveal:
        return [
          Text(
            _vm.sentence.romaji,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            AppStrings.shiftVerbPrompt,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.inkMuted, height: 1.5),
          ),
          if (_vm.verbPrompted || _vm.phase == ShiftPhase.verbReveal) ...[
            const SizedBox(height: 8),
            Text(
              widget.drill.formHint,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.inkMuted, height: 1.5),
            ),
          ],
          const SizedBox(height: 12),
          for (final choice in _vm.sentence.verbChoices)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AnswerOptionButton(
                label: choice,
                fontSize: 22,
                state: _verbState(choice),
                onTap: _vm.pickedVerb == null
                    ? () => _vm.pickVerb(choice)
                    : null,
              ),
            ),
        ];
      case ShiftPhase.rolesAsk:
      case ShiftPhase.rolesReveal:
        return [
          Text(
            _vm.sentence.romaji,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            AppStrings.shiftRolesPrompt,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.inkMuted, height: 1.5),
          ),
          if (_vm.rolesPrompted) ...[
            const SizedBox(height: 8),
            Text(
              _vm.sentence.relation,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.inkMuted, height: 1.5),
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            AppStrings.shiftRolesWho,
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          for (final choice in _vm.sentence.actorChoices)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AnswerOptionButton(
                label: choice,
                fontSize: 22,
                state: _roleState(
                  choice,
                  picked: _vm.pickedActor,
                  answer: _vm.sentence.actor,
                  revealed: _vm.phase == ShiftPhase.rolesReveal,
                ),
                onTap: _vm.phase == ShiftPhase.rolesAsk
                    ? () => _vm.selectActor(choice)
                    : null,
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            AppStrings.shiftRolesWhat,
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          for (final choice in _vm.sentence.itemChoices)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AnswerOptionButton(
                label: choice,
                fontSize: 22,
                state: _roleState(
                  choice,
                  picked: _vm.pickedItem,
                  answer: _vm.sentence.item,
                  revealed: _vm.phase == ShiftPhase.rolesReveal,
                ),
                onTap: _vm.phase == ShiftPhase.rolesAsk
                    ? () => _vm.selectItem(choice)
                    : null,
              ),
            ),
        ];
      case ShiftPhase.senseCommit:
        return [
          Text(
            _vm.sentence.romaji,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _vm.isAction
                ? AppStrings.shiftActionSensePrompt
                : AppStrings.shiftSensePrompt,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.inkMuted, height: 1.5),
          ),
          const SizedBox(height: 8),
          const Text(
            AppStrings.shiftSelfGradeNote,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.inkMuted,
              height: 1.5,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: AppStrings.shiftSensePadHint,
            ),
          ),
        ];
      case ShiftPhase.senseGrade:
        return [
          const Divider(height: 28, indent: 28, endIndent: 28),
          Text(
            _vm.sentence.meaning,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, color: AppColors.ink),
          ),
          const SizedBox(height: 8),
          Text(
            _vm.sentence.relation,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.inkMuted, height: 1.5),
          ),
          const SizedBox(height: 10),
          const Text(
            AppStrings.shiftSelfGradeNote,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.inkMuted,
              height: 1.5,
              fontSize: 13,
            ),
          ),
        ];
    }
  }

  OptionState _verbState(String choice) {
    if (_vm.pickedVerb == null) return OptionState.idle;
    final ok = _vm.isVerbCorrect(choice);
    if (choice == _vm.pickedVerb) {
      return ok ? OptionState.correct : OptionState.wrong;
    }
    return ok ? OptionState.revealed : OptionState.dimmed;
  }

  OptionState _roleState(
    String choice, {
    required String? picked,
    required String answer,
    required bool revealed,
  }) {
    if (!revealed) {
      return choice == picked ? OptionState.correct : OptionState.idle;
    }
    if (choice == answer) {
      return choice == picked ? OptionState.correct : OptionState.revealed;
    }
    if (choice == picked) return OptionState.wrong;
    return OptionState.dimmed;
  }

  Widget _actions() {
    switch (_vm.phase) {
      case ShiftPhase.intro:
        return const SizedBox.shrink();
      case ShiftPhase.readCommit:
        return _pair(
          outlined: AppStrings.recallHint,
          filled: AppStrings.iReadUnprompted,
          onOutlined: () => _commitRead(unprompted: false),
          onFilled: () => _commitRead(unprompted: true),
        );
      case ShiftPhase.readGrade:
        return _pair(
          outlined: AppStrings.iCouldnt,
          filled: _vm.readUnprompted
              ? AppStrings.iReadIt
              : AppStrings.iReadAfterHint,
          danger: true,
          onOutlined: () => _vm.gradeRead(correct: false),
          onFilled: () => _vm.gradeRead(correct: true),
        );
      case ShiftPhase.verbAsk:
        return _vm.verbPrompted
            ? const SizedBox.shrink()
            : OutlinedButton(
                onPressed: _vm.hintVerb,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                ),
                child: const Text(AppStrings.shiftVerbHint),
              );
      case ShiftPhase.verbReveal:
        return FilledButton(
          onPressed: _vm.afterVerb,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
          child: const Text(AppStrings.shiftContinue),
        );
      case ShiftPhase.rolesAsk:
        return Column(
          children: [
            if (!_vm.rolesPrompted)
              OutlinedButton(
                onPressed: _vm.hintRoles,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                ),
                child: const Text(AppStrings.shiftRolesHint),
              ),
            if (!_vm.rolesPrompted) const SizedBox(height: 12),
            FilledButton(
              onPressed: _vm.canLockRoles ? _vm.lockRoles : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
              ),
              child: const Text(AppStrings.shiftRolesReady),
            ),
          ],
        );
      case ShiftPhase.rolesReveal:
        return FilledButton(
          onPressed: _vm.afterRoles,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
          child: const Text(AppStrings.shiftContinue),
        );
      case ShiftPhase.senseCommit:
        return _pair(
          outlined: AppStrings.shiftSenseHint,
          filled: AppStrings.shiftSenseReady,
          onOutlined: () => _vm.commitSense(unprompted: false),
          onFilled: () => _vm.commitSense(unprompted: true),
        );
      case ShiftPhase.senseGrade:
        return _pair(
          outlined: AppStrings.shiftSenseMiss,
          filled: _vm.senseUnprompted
              ? AppStrings.shiftSenseOk
              : AppStrings.shiftSenseOkAfterHint,
          danger: true,
          enabled: !_vm.isSenseGrading,
          onOutlined: () => unawaited(_vm.gradeSense(correct: false)),
          onFilled: () => unawaited(_vm.gradeSense(correct: true)),
        );
    }
  }

  Widget _pair({
    required String outlined,
    required String filled,
    required VoidCallback onOutlined,
    required VoidCallback onFilled,
    bool danger = false,
    bool enabled = true,
  }) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              side: danger ? const BorderSide(color: AppColors.error) : null,
              foregroundColor: danger ? AppColors.error : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: enabled ? onOutlined : null,
            child: Text(outlined, textAlign: TextAlign.center),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: danger ? AppColors.success : null,
              minimumSize: const Size.fromHeight(54),
            ),
            onPressed: enabled ? onFilled : null,
            child: Text(filled, textAlign: TextAlign.center),
          ),
        ),
      ],
    );
  }
}
