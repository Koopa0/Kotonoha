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
    super.key,
  });

  final ShiftDrill drill;
  final String? sourceUrl;
  final VoidCallback? onMore;
  final DateTime Function()? clock;

  static Route<void> route(
    ShiftDrill drill, {
    String? sourceUrl,
    VoidCallback? onMore,
  }) => MaterialPageRoute<void>(
    builder: (_) =>
        ShiftPracticeScreen(drill: drill, sourceUrl: sourceUrl, onMore: onMore),
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
  int? _ownedPlay;
  bool _playable = true;
  ShiftBeat _beat = ShiftBeat.base;
  _Phase _phase = _Phase.readCommit;
  bool _readUnprompted = false;
  bool _senseUnprompted = false;
  bool _done = false;

  DateTime Function() get _clock => widget.clock ?? DateTime.now;

  ShiftSentence get _sentence => widget.drill.sentenceAt(_beat);

  String get _say => _sentence.kana.replaceAll(' ', '');

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
    _playable = _foreground;
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

  void _gradeRead({required bool correct}) {
    _record(ShiftCheck.read, prompted: !_readUnprompted, correct: correct);
    setState(() => _phase = _Phase.senseCommit);
  }

  void _commitSense({required bool unprompted}) {
    setState(() {
      _senseUnprompted = unprompted;
      _phase = _Phase.senseGrade;
    });
  }

  void _gradeSense({required bool correct}) {
    _record(ShiftCheck.sense, prompted: !_senseUnprompted, correct: correct);
    if (_beat == ShiftBeat.base) {
      _note.clear();
      setState(() {
        _beat = ShiftBeat.shift;
        _phase = _Phase.readCommit;
        _readUnprompted = false;
        _senseUnprompted = false;
      });
      return;
    }
    setState(() => _done = true);
  }

  void _record(
    ShiftCheck check, {
    required bool prompted,
    required bool correct,
  }) {
    context.read<AnalyticsLog>().recordObserved(
      ShiftSession.attempt(
        drill: widget.drill,
        beat: _beat,
        check: check,
        prompted: prompted,
        correct: correct,
        sessionId: _sessionId,
        at: _clock(),
        sourceUrl: widget.sourceUrl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.shiftTitle)),
      body: SafeArea(child: _done ? _summary() : _body()),
    );
  }

  Widget _summary() {
    final band = ClosingBand.forHour(_clock().hour);
    return SessionSummary(
      headline: AppStrings.shiftClose,
      note: AppStrings.shiftCloseNote,
      onDone: () => Navigator.of(context).pop(),
      onMore: band == ClosingBand.day ? widget.onMore : null,
    );
  }

  Widget _body() {
    final source = widget.sourceUrl?.trim();
    return Column(
      children: [
        const SizedBox(height: 8),
        Text(
          AppStrings.itemProgress(_beat == ShiftBeat.base ? 1 : 2, 2),
          style: const TextStyle(
            color: AppColors.inkMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (source != null && source.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Text(
              AppStrings.shiftSourceChip(source),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.inkMuted, fontSize: 12),
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
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 44,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_beat == ShiftBeat.shift) ...[
                          Text(
                            widget.drill.change == ShiftChange.noun
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
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _sentence.kana,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 44,
                              height: 1.2,
                              fontWeight: FontWeight.w500,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ..._phaseCopy(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: _actions(),
        ),
      ],
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
          SpeakButton(text: _say, size: 30),
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
