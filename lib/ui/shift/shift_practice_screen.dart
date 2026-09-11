// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/shift_drill.dart';
import 'package:kotonoha/domain/use_cases/shift_session.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/answer_option_button.dart';
import 'package:kotonoha/ui/core/widgets/session_summary.dart';
import 'package:kotonoha/ui/core/widgets/speak_button.dart';
import 'package:kotonoha/ui/shift/shift_history.dart';
import 'package:provider/provider.dart';

/// Original swap-sentence practice: teach new forms first, then read, then
/// (for action drills) restore the dictionary form and name who / what,
/// then sense. Hints do not leak another check. Free-text is never
/// auto-graded. Evidence is logged per beat and check; word / phrase SRS
/// is never touched.
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

enum _Phase {
  intro,
  readCommit,
  readGrade,
  verbAsk,
  verbReveal,
  rolesAsk,
  rolesReveal,
  senseCommit,
  senseGrade,
}

class _ShiftPracticeScreenState extends State<ShiftPracticeScreen> {
  final String _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
  final TextEditingController _note = TextEditingController();
  late final SpeechService _speech;
  late final AppLifecycleListener _lifecycle;
  late final List<ShiftBeat> _beats;
  late ShiftBeat _beat;
  final Set<ShiftBeat> _exposed = <ShiftBeat>{};
  List<ShiftSelfGrade> _history = const [];
  int? _ownedPlay;
  bool _playable = true;
  late _Phase _phase;
  int _introIndex = 0;
  bool _readUnprompted = false;
  bool _readCorrect = false;
  bool _senseUnprompted = false;
  bool _verbPrompted = false;
  bool _rolesPrompted = false;
  String? _pickedVerb;
  String? _pickedActor;
  String? _pickedItem;
  bool _done = false;

  DateTime Function() get _clock => widget.clock ?? DateTime.now;

  ShiftSentence get _sentence => widget.drill.sentenceAt(_beat);

  String get _say => _sentence.kana.replaceAll(' ', '');

  bool get _action => widget.drill.isAction;

  List<ShiftIntroCard> get _intro => widget.drill.introduce;

  String? get _laneCaption {
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
    _speech = context.read<SpeechService>();
    _lifecycle = AppLifecycleListener(
      onInactive: _abandonOwnedPlayback,
      onHide: _abandonOwnedPlayback,
      onPause: _abandonOwnedPlayback,
      onDetach: _abandonOwnedPlayback,
      onResume: () => _playable = true,
    );
    _beats = List<ShiftBeat>.of(
      widget.beats ?? const [ShiftBeat.base, ShiftBeat.shift],
    );
    _beat = _beats.first;
    _playable = _foreground;
    _phase = _intro.isEmpty ? _Phase.readCommit : _Phase.intro;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reserveIfNeeded();
      _markPracticeSight();
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _abandonOwnedPlayback();
    _note.dispose();
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

  void _speak() => _speakText(_say);

  void _advanceIntro() {
    if (_introIndex + 1 < _intro.length) {
      setState(() => _introIndex += 1);
      return;
    }
    setState(() => _phase = _Phase.readCommit);
  }

  void _commitRead({required bool unprompted}) {
    _speak();
    setState(() {
      _readUnprompted = unprompted;
      _phase = _Phase.readGrade;
    });
  }

  void _reserveIfNeeded() {
    if (widget.lane != ShiftLane.hold) return;
    context.read<AnalyticsLog>().recordObserved(
      ShiftSession.reservation(
        drill: widget.drill,
        sessionId: _sessionId,
        at: _clock(),
        sourceUrl: widget.sourceUrl,
      ),
    );
  }

  void _markPracticeSight() {
    if (!_exposed.add(_beat)) return;
    context.read<AnalyticsLog>().recordObserved(
      ShiftSession.sighting(
        drill: widget.drill,
        beat: _beat,
        kind: ShiftSightKind.practice,
        sessionId: _sessionId,
        at: _clock(),
        lane: widget.lane,
        sourceUrl: widget.sourceUrl,
      ),
    );
  }

  Future<void> _loadHistory() async {
    final all = await context.read<AnalyticsLog>().all();
    if (!mounted) return;
    setState(() {
      _history = ShiftSession.selfGrades(all, drillId: widget.drill.id);
    });
  }

  void _gradeRead({required bool correct}) {
    unawaited(
      _record(ShiftCheck.read, prompted: !_readUnprompted, correct: correct),
    );
    setState(() {
      _readCorrect = correct;
      _phase = _action ? _Phase.verbAsk : _Phase.senseCommit;
    });
  }

  void _hintVerb() {
    setState(() => _verbPrompted = true);
  }

  void _pickVerb(String choice) {
    if (_pickedVerb != null) return;
    final correct = ShiftSession.gradesVerb(choice, _sentence);
    unawaited(
      _record(ShiftCheck.verb, prompted: _verbPrompted, correct: correct),
    );
    setState(() {
      _pickedVerb = choice;
      _phase = _Phase.verbReveal;
    });
  }

  void _afterVerb() {
    setState(() => _phase = _Phase.rolesAsk);
  }

  void _hintRoles() {
    setState(() => _rolesPrompted = true);
  }

  void _selectActor(String choice) {
    if (_phase != _Phase.rolesAsk) return;
    setState(() => _pickedActor = choice);
  }

  void _selectItem(String choice) {
    if (_phase != _Phase.rolesAsk) return;
    setState(() => _pickedItem = choice);
  }

  void _lockRoles() {
    final actor = _pickedActor;
    final item = _pickedItem;
    if (actor == null || item == null) return;
    final correct = ShiftSession.gradesRoles(
      actor: actor,
      item: item,
      sentence: _sentence,
    );
    unawaited(
      _record(ShiftCheck.roles, prompted: _rolesPrompted, correct: correct),
    );
    setState(() => _phase = _Phase.rolesReveal);
  }

  void _afterRoles() {
    setState(() => _phase = _Phase.senseCommit);
  }

  /// Reading support on screen when the sense check is graded — not the
  /// pre-reveal commit alone, and not the roles Chinese gloss.
  String _readSupportAtSenseGrade() {
    if (_readUnprompted && _readCorrect) {
      return ShiftReadSupport.independent;
    }
    return ShiftReadSupport.prompted;
  }

  void _commitSense({required bool unprompted}) {
    setState(() {
      _senseUnprompted = unprompted && !_rolesPrompted;
      _phase = _Phase.senseGrade;
    });
  }

  Future<void> _gradeSense({required bool correct}) async {
    await _record(
      ShiftCheck.sense,
      prompted: ShiftSession.sensePrompted(
        askedSenseHint: !_senseUnprompted,
        sawRolesGloss: _rolesPrompted,
      ),
      correct: correct,
      readSupport: _readSupportAtSenseGrade(),
    );
    if (!mounted) return;
    final next = _beats.indexOf(_beat) + 1;
    if (next < _beats.length) {
      _note.clear();
      setState(() {
        _beat = _beats[next];
        _phase = _Phase.readCommit;
        _readUnprompted = false;
        _readCorrect = false;
        _senseUnprompted = false;
        _verbPrompted = false;
        _rolesPrompted = false;
        _pickedVerb = null;
        _pickedActor = null;
        _pickedItem = null;
      });
      _markPracticeSight();
      return;
    }
    setState(() => _done = true);
    unawaited(_loadHistory());
  }

  /// Waits for the log to accept the row. A durable fault still keeps the
  /// attempt in memory; More must read [AnalyticsLog.all], not assume persist.
  Future<void> _record(
    ShiftCheck check, {
    required bool prompted,
    required bool correct,
    String? readSupport,
  }) async {
    try {
      await context.read<AnalyticsLog>().record(
        ShiftSession.attempt(
          drill: widget.drill,
          beat: _beat,
          check: check,
          prompted: prompted,
          correct: correct,
          sessionId: _sessionId,
          at: _clock(),
          sourceUrl: widget.sourceUrl,
          lane: widget.lane,
          readSupport: readSupport,
        ),
      );
    } on Object {
      // Memory retains the row; [unpersistedCount] stays honest.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: const Text(AppStrings.shiftTitle)),
      body: SafeArea(child: _done ? _summary() : _body()),
    );
  }

  Widget _summary() {
    final band = ClosingBand.forHour(_clock().hour);
    final holdNote = widget.lane == ShiftLane.hold
        ? '${AppStrings.shiftCloseNote}\n\n${AppStrings.shiftHeldUntilTomorrow}'
        : AppStrings.shiftCloseNote;
    return Column(
      children: [
        if (_history.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: ShiftHistoryView(grades: _history),
          ),
        Expanded(
          child: SessionSummary(
            headline: AppStrings.shiftClose,
            note: holdNote,
            onDone: () => Navigator.of(context).pop(),
            onMore: band == ClosingBand.day ? widget.onMore : null,
          ),
        ),
      ],
    );
  }

  Widget _body() {
    if (_phase == _Phase.intro) return _introBody();
    final source = widget.sourceUrl?.trim();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        children: [
          Column(
            children: [
              Text(
                AppStrings.itemProgress(
                  _beats.indexOf(_beat) + 1,
                  _beats.length,
                ),
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
                      if (_beat == ShiftBeat.shift) ...[
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
                        _sentence.kana,
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
    final card = _intro[_introIndex];
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
                          _introIndex + 1,
                          _intro.length,
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
                      onPressed: _advanceIntro,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                      ),
                      child: Text(
                        _introIndex + 1 < _intro.length
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
    switch (_phase) {
      case _Phase.intro:
        return const [];
      case _Phase.readCommit:
        return const [
          Text(
            AppStrings.readPrompt,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.inkMuted, fontSize: 15),
          ),
        ];
      case _Phase.readGrade:
        return [
          const Divider(height: 28, indent: 28, endIndent: 28),
          Text(
            _sentence.romaji,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
            ),
          ),
          SpeakButton(text: _say, size: 30, onPlay: _speak),
        ];
      case _Phase.verbAsk:
      case _Phase.verbReveal:
        return [
          Text(
            _sentence.romaji,
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
          if (_verbPrompted || _phase == _Phase.verbReveal) ...[
            const SizedBox(height: 8),
            Text(
              widget.drill.formHint,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.inkMuted, height: 1.5),
            ),
          ],
          const SizedBox(height: 12),
          for (final choice in _sentence.verbChoices)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AnswerOptionButton(
                label: choice,
                fontSize: 22,
                state: _verbState(choice),
                onTap: _pickedVerb == null ? () => _pickVerb(choice) : null,
              ),
            ),
        ];
      case _Phase.rolesAsk:
      case _Phase.rolesReveal:
        return [
          Text(
            _sentence.romaji,
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
          if (_rolesPrompted) ...[
            const SizedBox(height: 8),
            Text(
              _sentence.relation,
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
          for (final choice in _sentence.actorChoices)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AnswerOptionButton(
                label: choice,
                fontSize: 22,
                state: _roleState(
                  choice,
                  picked: _pickedActor,
                  answer: _sentence.actor,
                  revealed: _phase == _Phase.rolesReveal,
                ),
                onTap: _phase == _Phase.rolesAsk
                    ? () => _selectActor(choice)
                    : null,
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            AppStrings.shiftRolesWhat,
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          for (final choice in _sentence.itemChoices)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AnswerOptionButton(
                label: choice,
                fontSize: 22,
                state: _roleState(
                  choice,
                  picked: _pickedItem,
                  answer: _sentence.item,
                  revealed: _phase == _Phase.rolesReveal,
                ),
                onTap: _phase == _Phase.rolesAsk
                    ? () => _selectItem(choice)
                    : null,
              ),
            ),
        ];
      case _Phase.senseCommit:
        return [
          Text(
            _sentence.romaji,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _action
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
      case _Phase.senseGrade:
        return [
          const Divider(height: 28, indent: 28, endIndent: 28),
          Text(
            _sentence.meaning,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, color: AppColors.ink),
          ),
          const SizedBox(height: 8),
          Text(
            _sentence.relation,
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
    if (_pickedVerb == null) return OptionState.idle;
    final ok = ShiftSession.gradesVerb(choice, _sentence);
    if (choice == _pickedVerb) {
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
    switch (_phase) {
      case _Phase.intro:
        return const SizedBox.shrink();
      case _Phase.readCommit:
        return _pair(
          outlined: AppStrings.recallHint,
          filled: AppStrings.iReadUnprompted,
          onOutlined: () => _commitRead(unprompted: false),
          onFilled: () => _commitRead(unprompted: true),
        );
      case _Phase.readGrade:
        return _pair(
          outlined: AppStrings.iCouldnt,
          filled: _readUnprompted
              ? AppStrings.iReadIt
              : AppStrings.iReadAfterHint,
          danger: true,
          onOutlined: () => _gradeRead(correct: false),
          onFilled: () => _gradeRead(correct: true),
        );
      case _Phase.verbAsk:
        return _verbPrompted
            ? const SizedBox.shrink()
            : OutlinedButton(
                onPressed: _hintVerb,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                ),
                child: const Text(AppStrings.shiftVerbHint),
              );
      case _Phase.verbReveal:
        return FilledButton(
          onPressed: _afterVerb,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
          child: const Text(AppStrings.shiftContinue),
        );
      case _Phase.rolesAsk:
        return Column(
          children: [
            if (!_rolesPrompted)
              OutlinedButton(
                onPressed: _hintRoles,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                ),
                child: const Text(AppStrings.shiftRolesHint),
              ),
            if (!_rolesPrompted) const SizedBox(height: 12),
            FilledButton(
              onPressed: _pickedActor != null && _pickedItem != null
                  ? _lockRoles
                  : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
              ),
              child: const Text(AppStrings.shiftRolesReady),
            ),
          ],
        );
      case _Phase.rolesReveal:
        return FilledButton(
          onPressed: _afterRoles,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
          child: const Text(AppStrings.shiftContinue),
        );
      case _Phase.senseCommit:
        return _pair(
          outlined: AppStrings.shiftSenseHint,
          filled: AppStrings.shiftSenseReady,
          onOutlined: () => _commitSense(unprompted: false),
          onFilled: () => _commitSense(unprompted: true),
        );
      case _Phase.senseGrade:
        return _pair(
          outlined: AppStrings.shiftSenseMiss,
          filled: _senseUnprompted
              ? AppStrings.shiftSenseOk
              : AppStrings.shiftSenseOkAfterHint,
          danger: true,
          onOutlined: () => _gradeSense(correct: false),
          onFilled: () => _gradeSense(correct: true),
        );
    }
  }

  Widget _pair({
    required String outlined,
    required String filled,
    required VoidCallback onOutlined,
    required VoidCallback onFilled,
    bool danger = false,
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
            onPressed: onOutlined,
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
            onPressed: onFilled,
            child: Text(filled, textAlign: TextAlign.center),
          ),
        ),
      ],
    );
  }
}
