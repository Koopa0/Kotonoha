// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/shift_drill.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/shift/shift_focus_viewmodel.dart';
import 'package:kotonoha/ui/shift/shift_history.dart';
import 'package:kotonoha/ui/shift/shift_persist_notice.dart';
import 'package:kotonoha/ui/shift/shift_practice_screen.dart';
import 'package:provider/provider.dart';

/// Picker for today's stuck point. The learner names a curated focus / drill
/// without editing the Dart corpus. Travel-scene selection stays on #47.
///
/// Next-day hold is optional: same-session practice stays the default start.
/// The reserved sentence is never previewed here.
///
/// A thin View over [ShiftFocusViewModel]: it renders the list, keeps the
/// source field, and navigates. The plans, the preview sightings and the
/// durable-write state are the ViewModel's.
class ShiftFocusScreen extends StatefulWidget {
  const ShiftFocusScreen({
    super.key,
    this.drills,
    this.onStarted,
    this.clock,
    this.attempts,
  });

  /// Injectable catalogue for tests; defaults to the human-checked slice.
  final List<ShiftDrill>? drills;

  /// Test seam: called after a session is pushed.
  final ValueChanged<ShiftDrill>? onStarted;

  /// Injectable clock so day-0 / day-1 confirm is testable.
  final DateTime Function()? clock;

  /// Test seam: skip the analytics load when the stream is already known.
  final List<Attempt>? attempts;

  static Route<void> route({DateTime Function()? clock}) =>
      MaterialPageRoute<void>(builder: (_) => ShiftFocusScreen(clock: clock));

  @override
  State<ShiftFocusScreen> createState() => _ShiftFocusScreenState();
}

class _ShiftFocusScreenState extends State<ShiftFocusScreen> {
  final TextEditingController _source = TextEditingController();
  late final ShiftFocusViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = ShiftFocusViewModel(
      analytics: context.read<AnalyticsLog>(),
      persistence: context.read<ProgressPersistenceController>(),
      drills: widget.drills,
      attempts: widget.attempts,
      clock: widget.clock,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_vm.load());
    });
  }

  @override
  void dispose() {
    _source.dispose();
    _vm.dispose();
    super.dispose();
  }

  Future<void> _start({ShiftLane requested = ShiftLane.sameDay}) async {
    final drill = _vm.selected;
    if (drill == null) return;
    final sourceUrl = _source.text.trim();
    final plan = _vm.plan(drill, requested: requested);
    widget.onStarted?.call(drill);
    await Navigator.of(context).push(
      ShiftPracticeScreen.route(
        drill,
        sourceUrl: sourceUrl.isEmpty ? null : sourceUrl,
        clock: widget.clock,
        lane: plan.lane,
        beats: plan.beats,
        firstUnseen: plan.firstUnseen,
        onMore: () => unawaited(_again(drill, sourceUrl, requested)),
      ),
    );
    if (mounted) await _vm.reload();
  }

  Future<void> _again(
    ShiftDrill drill,
    String sourceUrl,
    ShiftLane requested,
  ) async {
    await _vm.refreshAttempts();
    if (!mounted) return;
    final plan = _vm.plan(drill, requested: requested);
    await Navigator.of(context).pushReplacement(
      ShiftPracticeScreen.route(
        drill,
        sourceUrl: sourceUrl.isEmpty ? null : sourceUrl,
        clock: widget.clock,
        lane: plan.lane,
        beats: plan.beats,
        firstUnseen: plan.firstUnseen,
        onMore: () => unawaited(_again(drill, sourceUrl, requested)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.shiftTitle)),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _vm,
          builder: (context, _) => _picker(),
        ),
      ),
    );
  }

  Widget _picker() {
    final selectedPlan = _vm.selectedPlan;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        const Text(
          AppStrings.shiftPickerLead,
          style: TextStyle(color: AppColors.ink, height: 1.55, fontSize: 16),
        ),
        const SizedBox(height: 12),
        const Text(
          AppStrings.shiftPickerBoundary,
          style: TextStyle(color: AppColors.inkMuted, height: 1.55),
        ),
        const SizedBox(height: 10),
        const Text(
          AppStrings.shiftSelfGradeNote,
          style: TextStyle(color: AppColors.inkMuted, height: 1.55),
        ),
        const SizedBox(height: 20),
        for (final focus in _vm.focuses) ...[
          Text(
            focus.title,
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          for (final drill in focus.drills)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: AppColors.card,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: drill.id == _vm.selectedId
                        ? AppColors.accent
                        : AppColors.hairline,
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _vm.select(drill.id),
                  child: ListTile(
                    title: Text(drill.label),
                    subtitle: Text(_subtitle(_vm.plan(drill))),
                    trailing: Icon(
                      drill.id == _vm.selectedId
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      color: drill.id == _vm.selectedId
                          ? AppColors.accent
                          : AppColors.inkMuted,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
        ],
        if (_vm.isUnsaved)
          ShiftPersistNotice(
            retrying: _vm.isRetrying,
            onRetry: () => unawaited(_vm.retryPersist()),
          ),
        if (selectedPlan != null) ...[
          if (_statusCopy(selectedPlan) case final status
              when status.isNotEmpty) ...[
            Text(
              status,
              style: const TextStyle(color: AppColors.inkMuted, height: 1.55),
            ),
            const SizedBox(height: 16),
          ],
          ShiftHistoryView(grades: _vm.selfGradesFor(selectedPlan.drill.id)),
        ],
        TextField(
          controller: _source,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: AppStrings.shiftSourceLabel,
            hintText: AppStrings.shiftSourceHint,
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _start,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
          child: Text(_primaryLabel(selectedPlan)),
        ),
        if (_vm.showHold) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => _start(requested: ShiftLane.hold),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
            ),
            child: Text(
              selectedPlan?.holdPending == true
                  ? AppStrings.shiftHoldContinue
                  : AppStrings.shiftHoldStart,
            ),
          ),
        ],
      ],
    );
  }

  String _subtitle(ShiftPlan plan) {
    if (plan.lane == ShiftLane.confirm) {
      return plan.firstUnseen
          ? AppStrings.shiftFirstUnseen
          : AppStrings.shiftAlreadyShown;
    }
    if (plan.noUnseenVariant) return AppStrings.shiftReviewOnly;
    return plan.drill.base.kana;
  }

  String _statusCopy(ShiftPlan plan) {
    if (plan.lane == ShiftLane.confirm) {
      return plan.firstUnseen
          ? AppStrings.shiftConfirmDue
          : AppStrings.shiftAlreadyShown;
    }
    if (plan.shiftSight == ShiftSight.unknown) {
      return AppStrings.shiftSightUnknown;
    }
    if (plan.holdPending) {
      return _vm.isUnsaved
          ? AppStrings.shiftPersistFailed
          : AppStrings.shiftHeldUntilTomorrow;
    }
    if (plan.noUnseenVariant) return AppStrings.shiftReviewOnly;
    return '';
  }

  String _primaryLabel(ShiftPlan? plan) {
    if (plan == null) return AppStrings.shiftStart;
    if (plan.lane == ShiftLane.confirm) return AppStrings.shiftConfirmStart;
    if (plan.noUnseenVariant) return AppStrings.shiftReviewStart;
    return AppStrings.shiftStart;
  }
}
