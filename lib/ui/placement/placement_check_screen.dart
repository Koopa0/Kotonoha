// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/placement_check_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/placement_check.dart';
import 'package:kotonoha/domain/models/session_item.dart';
import 'package:kotonoha/domain/use_cases/placement_check.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/speak_button.dart';
import 'package:kotonoha/ui/placement/placement_result_screen.dart';
import 'package:kotonoha/ui/quiz/quiz_viewmodel.dart';
import 'package:provider/provider.dart';

/// Answer-first check. The reading stays hidden until the learner commits,
/// asks for a hint, or says they do not know. Uses [QuizViewModel] as-is
/// (#41/#43 RT rules, prompted vs independent). No listening items.
class PlacementCheckScreen extends StatefulWidget {
  const PlacementCheckScreen({
    required this.draft,
    required this.checks,
    super.key,
    this.clock,
    this.monotonicMs,
  });

  final PlacementDraft draft;
  final PlacementCheckRepository checks;
  final DateTime Function()? clock;
  final int Function()? monotonicMs;

  static Route<void> route({
    required PlacementDraft draft,
    required PlacementCheckRepository checks,
    DateTime Function()? clock,
    int Function()? monotonicMs,
  }) {
    return MaterialPageRoute<void>(
      builder: (_) => PlacementCheckScreen(
        draft: draft,
        checks: checks,
        clock: clock,
        monotonicMs: monotonicMs,
      ),
    );
  }

  @override
  State<PlacementCheckScreen> createState() => _PlacementCheckScreenState();
}

class _PlacementCheckScreenState extends State<PlacementCheckScreen> {
  late PlacementDraft _draft;
  late final QuizViewModel _vm;
  late final AppLifecycleListener _lifecycle;
  bool _navigated = false;
  bool _answerable = true;
  AppLifecycleState _lifecycleState =
      WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
  bool _recallRevealed = false;
  bool _recallUnpromptedCommit = false;

  @override
  void initState() {
    super.initState();
    _draft = widget.draft;
    final store = context.read<KanaProgressRepository>();
    final pending = PlacementCheck.pendingTargets(_draft, store.allKana);
    _vm = QuizViewModel(
      items: [
        for (final question in PlacementCheck.questions(pending))
          SessionItem(question: question, mode: PracticeMode.placementCheck),
      ],
      repository: store,
      persistence: context.read<ProgressPersistenceController>(),
      analytics: context.read<AnalyticsLog>(),
      sessionId: 'placement-${DateTime.now().millisecondsSinceEpoch}',
      clock: widget.clock,
      monotonicMs: widget.monotonicMs,
    )..addListener(_onChanged);
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycleState);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_vm.items.isEmpty) {
        _goToResults();
        return;
      }
      _reportPresentation();
    });
  }

  bool get _isVisible =>
      _lifecycleState == AppLifecycleState.resumed ||
      _lifecycleState == AppLifecycleState.inactive;

  void _onLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    _answerable = state == AppLifecycleState.resumed;
    if (!_answerable) {
      _vm.noteUnanswerable();
      _schedulePresentationReport();
      return;
    }
    _schedulePresentationReport();
  }

  void _reportPresentation() {
    if (!mounted || _vm.items.isEmpty || _vm.isAnswered || _vm.isFinished) {
      return;
    }
    if (!_isVisible) return;
    if (_answerable) {
      _vm.noteAnswerablePresentation();
    } else {
      _vm.noteUnanswerable(stillVisible: true);
    }
  }

  void _schedulePresentationReport() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportPresentation();
    });
  }

  Future<void> _noteOutcome({
    required bool correct,
    required bool unprompted,
  }) async {
    if (_vm.isAnswered || _vm.isFinished || _vm.items.isEmpty) return;
    final kanaId = _vm.current.target.id;
    _vm.gradeRecall(correct: correct, unprompted: unprompted);
    _draft = PlacementCheck.record(
      _draft,
      kanaId,
      PlacementCheck.outcomeFor(correct: correct, unprompted: unprompted),
    );
    await widget.checks.save(_draft);
  }

  void _onChanged() {
    if (!_answerable) {
      _vm.noteUnanswerable();
    }
    _schedulePresentationReport();
    if (!_vm.isAnswered) {
      _recallRevealed = false;
      _recallUnpromptedCommit = false;
    }
    if (_vm.isFinished) {
      _goToResults();
    }
  }

  void _goToResults() {
    if (_navigated) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      PlacementResultScreen.route(draft: _draft, checks: widget.checks),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _vm.removeListener(_onChanged);
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.placementTitle)),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _vm,
          builder: (context, _) {
            if (_vm.items.isEmpty || _vm.isFinished) {
              return const SizedBox.shrink();
            }
            final q = _vm.current;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Text(
                    AppStrings.itemProgress(_vm.index + 1, _vm.total),
                    style: const TextStyle(
                      color: AppColors.inkMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
                    child: Column(
                      children: [
                        const Text(
                          AppStrings.readPrompt,
                          style: TextStyle(
                            color: AppColors.inkMuted,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: AppColors.hairline),
                          ),
                          child: Column(
                            children: [
                              Text(
                                q.prompt,
                                style: const TextStyle(
                                  fontSize: 96,
                                  height: 1.0,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.ink,
                                ),
                              ),
                              if (_recallRevealed) ...[
                                const SizedBox(height: 8),
                                SpeakButton(text: q.target.character, size: 30),
                              ],
                            ],
                          ),
                        ),
                        if (_recallRevealed) ...[
                          const SizedBox(height: 16),
                          Text(
                            q.correctAnswer,
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              color: AppColors.accent,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: _vm.isAnswered
                      ? FilledButton(
                          onPressed: _vm.advance,
                          child: Text(
                            _vm.isLastQuestion
                                ? AppStrings.seeResults
                                : AppStrings.continueLabel,
                          ),
                        )
                      : _actions(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _actions() {
    if (_recallRevealed) {
      final unprompted = _recallUnpromptedCommit;
      return Row(
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
              onPressed: () =>
                  _noteOutcome(correct: false, unprompted: unprompted),
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
              onPressed: () =>
                  _noteOutcome(correct: true, unprompted: unprompted),
              child: Text(
                unprompted ? AppStrings.iReadIt : AppStrings.iReadAfterHint,
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () => setState(() {
                  _recallUnpromptedCommit = false;
                  _recallRevealed = true;
                }),
                child: const Text(AppStrings.recallHint),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                ),
                onPressed: () {
                  _vm.captureUnpromptedRecall();
                  setState(() {
                    _recallUnpromptedCommit = true;
                    _recallRevealed = true;
                  });
                },
                child: const Text(AppStrings.iReadUnprompted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () {
            setState(() {
              _recallUnpromptedCommit = false;
              _recallRevealed = true;
            });
            _noteOutcome(correct: false, unprompted: true);
          },
          style: TextButton.styleFrom(foregroundColor: AppColors.inkMuted),
          child: const Text(AppStrings.placementUnknown),
        ),
      ],
    );
  }
}
