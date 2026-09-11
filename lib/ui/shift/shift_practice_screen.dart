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
import 'package:kotonoha/ui/core/widgets/session_summary.dart';
import 'package:kotonoha/ui/core/widgets/speak_button.dart';
import 'package:kotonoha/ui/shift/shift_history.dart';
import 'package:provider/provider.dart';

/// Original swap-sentence practice: read first, then sense / who-modifies-whom.
/// Hints do not leak the other check. Free-text is never auto-graded. Evidence
/// is logged per beat and check; word / phrase SRS is never touched.
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

enum _Phase { readCommit, readGrade, senseCommit, senseGrade }

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
  _Phase _phase = _Phase.readCommit;
  bool _readUnprompted = false;
  bool _readCorrect = false;
  bool _senseUnprompted = false;
  bool _done = false;

  DateTime Function() get _clock => widget.clock ?? DateTime.now;

  ShiftSentence get _sentence => widget.drill.sentenceAt(_beat);

  String get _say => _sentence.kana.replaceAll(' ', '');

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

  void _speak() {
    if (!mounted || !_playable || !_foreground) return;
    unawaited(_speech.speak(_say));
    _ownedPlay = _speech.generation;
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
      _phase = _Phase.senseCommit;
    });
  }

  /// Support already on screen at the sense grade.
  ///
  /// [_readUnprompted] is the pre-reveal attempt; [_readCorrect] is the
  /// post-reveal self-grade. Independent only when both hold. A failed
  /// check has already revealed the reading, so the sense row is prompted.
  String _readSupportAtSenseGrade() {
    if (_readUnprompted && _readCorrect) {
      return ShiftReadSupport.independent;
    }
    return ShiftReadSupport.prompted;
  }

  void _commitSense({required bool unprompted}) {
    setState(() {
      _senseUnprompted = unprompted;
      _phase = _Phase.senseGrade;
    });
  }

  Future<void> _gradeSense({required bool correct}) async {
    await _record(
      ShiftCheck.sense,
      prompted: !_senseUnprompted,
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
                              : widget.drill.change == ShiftChange.noun
                              ? AppStrings.shiftBridgeNoun
                              : AppStrings.shiftBridgeModifier,
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

  List<Widget> _phaseCopy() {
    switch (_phase) {
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
          const Text(
            AppStrings.shiftSensePrompt,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.inkMuted, height: 1.5),
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

  Widget _actions() {
    switch (_phase) {
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
