// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/shift_drill.dart';
import 'package:kotonoha/domain/use_cases/shift_session.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/shift/shift_history.dart';
import 'package:kotonoha/ui/shift/shift_practice_screen.dart';
import 'package:provider/provider.dart';

/// Picker for today's stuck point. The learner names a curated focus / drill
/// without editing the Dart corpus. Travel-scene selection stays on #47.
///
/// Next-day hold is optional: same-session practice stays the default start.
/// The reserved sentence is never previewed here.
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
  final String _pickerSessionId = DateTime.now().millisecondsSinceEpoch
      .toString();
  final Set<String> _previewed = <String>{};
  late String _selectedId;
  List<Attempt> _attempts = const [];

  DateTime Function() get _clock => widget.clock ?? DateTime.now;

  List<ShiftFocus> get _focuses => ShiftSession.focuses(drills: _drills);

  List<ShiftDrill> get _drills =>
      widget.drills ?? ShiftSession.focuses().expand((f) => f.drills).toList();

  ShiftPlan _plan(
    ShiftDrill drill, {
    ShiftLane requested = ShiftLane.sameDay,
  }) => ShiftSession.plan(
    drill: drill,
    now: _clock(),
    attempts: _attempts,
    requested: requested,
  );

  @override
  void initState() {
    super.initState();
    _selectedId = _drills.first.id;
    _attempts = widget.attempts ?? const [];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.attempts == null) {
        _reload();
      } else {
        _markVisiblePreviews();
      }
    });
  }

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final log = context.read<AnalyticsLog>();
    final all = await log.all();
    if (!mounted) return;
    setState(() => _attempts = all);
    _markVisiblePreviews();
  }

  void _markVisiblePreviews() {
    final log = context.read<AnalyticsLog>();
    final now = _clock();
    for (final drill in _drills) {
      final plan = _plan(drill);
      final preview = ShiftSession.pickerPreview(plan);
      if (preview == null) continue;
      if (!_previewed.add(drill.id)) continue;
      log.recordObserved(
        ShiftSession.sighting(
          drill: drill,
          beat: ShiftBeat.base,
          kind: ShiftSightKind.preview,
          sessionId: _pickerSessionId,
          at: now,
          lane: plan.lane,
        ),
      );
    }
  }

  Future<void> _start({ShiftLane requested = ShiftLane.sameDay}) async {
    final drill = ShiftSession.drillById(_selectedId, drills: _drills);
    if (drill == null) return;
    final sourceUrl = _source.text.trim();
    final plan = _plan(drill, requested: requested);
    widget.onStarted?.call(drill);
    await Navigator.of(context).push(
      ShiftPracticeScreen.route(
        drill,
        sourceUrl: sourceUrl.isEmpty ? null : sourceUrl,
        clock: widget.clock,
        lane: plan.lane,
        beats: plan.beats,
        firstUnseen: plan.firstUnseen,
        onMore: () => _again(drill, sourceUrl, requested),
      ),
    );
    if (mounted) await _reload();
  }

  void _again(ShiftDrill drill, String sourceUrl, ShiftLane requested) {
    final plan = _plan(drill, requested: requested);
    Navigator.of(context).pushReplacement(
      ShiftPracticeScreen.route(
        drill,
        sourceUrl: sourceUrl.isEmpty ? null : sourceUrl,
        clock: widget.clock,
        lane: plan.lane,
        beats: plan.beats,
        firstUnseen: plan.firstUnseen,
        onMore: () => _again(drill, sourceUrl, requested),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = ShiftSession.drillById(_selectedId, drills: _drills);
    final selectedPlan = selected == null ? null : _plan(selected);
    final holdPlan = selected == null
        ? null
        : _plan(selected, requested: ShiftLane.hold);
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.shiftTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            const Text(
              AppStrings.shiftPickerLead,
              style: TextStyle(
                color: AppColors.ink,
                height: 1.55,
                fontSize: 16,
              ),
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
            for (final focus in _focuses) ...[
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
                        color: drill.id == _selectedId
                            ? AppColors.accent
                            : AppColors.hairline,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => setState(() => _selectedId = drill.id),
                      child: ListTile(
                        title: Text(drill.label),
                        subtitle: Text(_subtitle(_plan(drill))),
                        trailing: Icon(
                          drill.id == _selectedId
                              ? Icons.check_circle_rounded
                              : Icons.circle_outlined,
                          color: drill.id == _selectedId
                              ? AppColors.accent
                              : AppColors.inkMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
            ],
            if (selectedPlan != null) ...[
              if (_statusCopy(selectedPlan) case final status
                  when status.isNotEmpty) ...[
                Text(
                  status,
                  style: const TextStyle(
                    color: AppColors.inkMuted,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              ShiftHistoryView(
                grades: ShiftSession.selfGrades(
                  _attempts,
                  drillId: selectedPlan.drill.id,
                ),
              ),
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
              onPressed: () => _start(),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
              ),
              child: Text(_primaryLabel(selectedPlan)),
            ),
            if (_showHold(selectedPlan, holdPlan)) ...[
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
        ),
      ),
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
    if (plan.holdPending) return AppStrings.shiftHeldUntilTomorrow;
    if (plan.noUnseenVariant) return AppStrings.shiftReviewOnly;
    return '';
  }

  String _primaryLabel(ShiftPlan? plan) {
    if (plan == null) return AppStrings.shiftStart;
    if (plan.lane == ShiftLane.confirm) return AppStrings.shiftConfirmStart;
    if (plan.noUnseenVariant) return AppStrings.shiftReviewStart;
    return AppStrings.shiftStart;
  }

  bool _showHold(ShiftPlan? sameDay, ShiftPlan? hold) {
    if (sameDay == null || hold == null) return false;
    if (sameDay.lane == ShiftLane.confirm) return false;
    if (sameDay.noUnseenVariant && !sameDay.holdPending) return false;
    return hold.shiftSight == ShiftSight.unseen || sameDay.holdPending;
  }
}
