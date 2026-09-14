// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/placement_check_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/domain/models/placement_check.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/speak_button.dart';
import 'package:kotonoha/ui/placement/placement_check_viewmodel.dart';
import 'package:kotonoha/ui/placement/placement_result_screen.dart';
import 'package:provider/provider.dart';

/// Answer-first check. The reading stays hidden until the learner commits,
/// asks for a hint, or says they do not know. No listening items.
///
/// A thin View over [PlacementCheckViewModel]: it owns the lifecycle
/// listener and what visibility means for the item on screen, renders,
/// and navigates to the results. The draft and its saves, the reveal, the
/// outcome and the graded recall (#41/#43 RT rules, prompted vs.
/// independent) are the ViewModel's.
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
  late final PlacementCheckViewModel _vm;
  late final AppLifecycleListener _lifecycle;
  bool _navigated = false;
  bool _answerable = true;
  AppLifecycleState _lifecycleState =
      WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    _vm = PlacementCheckViewModel(
      draft: widget.draft,
      checks: widget.checks,
      kana: context.read<KanaProgressRepository>(),
      persistence: context.read<ProgressPersistenceController>(),
      recovery: context.read<ProgressRestoreRecoveryController>(),
      analytics: context.read<AnalyticsLog>(),
      clock: widget.clock,
      monotonicMs: widget.monotonicMs,
    )..addListener(_onChanged);
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycleState);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_vm.isEmpty) {
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
    if (!_answerable) _vm.noteUnanswerable();
    _schedulePresentationReport();
  }

  /// Visibility is the view's: what the item can count as while it is on
  /// screen is reported to the ViewModel after each frame.
  void _reportPresentation() {
    if (!mounted || _vm.isEmpty || _vm.isAnswered || _vm.isFinished) return;
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

  void _onChanged() {
    if (!_answerable) _vm.noteUnanswerable();
    _schedulePresentationReport();
    if (_vm.isFinished) _goToResults();
  }

  void _goToResults() {
    if (_navigated) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      PlacementResultScreen.route(draft: _vm.draft, checks: widget.checks),
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
    // Watched for rebuilds only; whether a write is allowed is the
    // ViewModel's call.
    context.watch<ProgressPersistenceController>();
    context.watch<ProgressRestoreRecoveryController>();
    final blocked = _vm.isBlocked;
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.placementTitle)),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _vm,
          builder: (context, _) {
            if (_vm.isEmpty || _vm.isFinished) {
              return const SizedBox.shrink();
            }
            final q = _vm.current;
            final revealed = _vm.isRevealed;
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
                              if (revealed) ...[
                                const SizedBox(height: 8),
                                SpeakButton(text: q.target.character, size: 30),
                              ],
                            ],
                          ),
                        ),
                        if (revealed) ...[
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
                          onPressed: blocked ? null : _vm.advance,
                          child: Text(
                            _vm.isLastQuestion
                                ? AppStrings.seeResults
                                : AppStrings.continueLabel,
                          ),
                        )
                      : _actions(blocked: blocked),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _actions({required bool blocked}) {
    if (_vm.isRevealed) {
      final unprompted = _vm.isUnpromptedCommit;
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
              onPressed: blocked ? null : () => _vm.noteOutcome(correct: false),
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
              onPressed: blocked ? null : () => _vm.noteOutcome(correct: true),
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
                onPressed: blocked ? null : _vm.revealAsHint,
                child: const Text(AppStrings.recallHint),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                ),
                onPressed: blocked ? null : _vm.revealAfterUnpromptedCommit,
                child: const Text(AppStrings.iReadUnprompted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: blocked ? null : _vm.markUnknown,
          style: TextButton.styleFrom(foregroundColor: AppColors.inkMuted),
          child: const Text(AppStrings.placementUnknown),
        ),
      ],
    );
  }
}
