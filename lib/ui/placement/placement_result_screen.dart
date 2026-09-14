// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/placement_check_repository.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/lesson.dart';
import 'package:kotonoha/domain/models/placement_check.dart';
import 'package:kotonoha/domain/use_cases/daily_session.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/placement_check.dart';
import 'package:kotonoha/domain/use_cases/study_set.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/lessons/lessons_screen.dart';
import 'package:kotonoha/ui/study/study_screen.dart';
import 'package:provider/provider.dart';

/// Next steps after an explicit check. Lists kana by how they were graded;
/// no rank, XP, or percentage claim.
class PlacementResultScreen extends StatefulWidget {
  const PlacementResultScreen({
    required this.draft,
    required this.checks,
    super.key,
  });

  final PlacementDraft draft;
  final PlacementCheckRepository checks;

  static Route<void> route({
    required PlacementDraft draft,
    required PlacementCheckRepository checks,
  }) {
    return MaterialPageRoute<void>(
      builder: (_) => PlacementResultScreen(draft: draft, checks: checks),
    );
  }

  @override
  State<PlacementResultScreen> createState() => _PlacementResultScreenState();
}

class _PlacementResultScreenState extends State<PlacementResultScreen> {
  late final PlacementSummary _summary;
  late final ProgressPersistenceController _persistence;
  late final ProgressRestoreRecoveryController _recovery;
  bool _applying = false;
  bool _draftClearIssued = false;
  bool _awaitingRetry = false;

  @override
  void initState() {
    super.initState();
    final store = context.read<KanaProgressRepository>();
    _persistence = context.read<ProgressPersistenceController>();
    _recovery = context.read<ProgressRestoreRecoveryController>();
    _summary = PlacementCheck.summarize(
      draft: widget.draft,
      catalog: Lessons.fromKana(store.allKana),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applyConfirmed(store);
    });
  }

  @override
  void dispose() {
    if (_awaitingRetry) {
      _persistence.removeListener(_onPersistChanged);
      _recovery.removeListener(_onPersistChanged);
    }
    super.dispose();
  }

  void _onPersistChanged() {
    if (!_awaitingRetry || !mounted || _applying || _draftClearIssued) return;
    if (_persistence.hasWriteFailure || _persistence.isRetrying) return;
    if (_recovery.needsRecovery || _recovery.isRetrying) return;
    _awaitingRetry = false;
    _persistence.removeListener(_onPersistChanged);
    _recovery.removeListener(_onPersistChanged);
    _applyConfirmed(context.read<KanaProgressRepository>());
  }

  /// Persist confirmed rows on disk first, then clear the draft. Memory
  /// success is not enough — a failed `learned_units_v1` write must keep
  /// the recoverable draft so cold start can resume results instead of
  /// leaving "draft empty / row unlearned".
  Future<void> _applyConfirmed(KanaProgressRepository store) async {
    if (_applying || _draftClearIssued || !mounted) return;
    if (_recovery.needsRecovery) {
      if (!_awaitingRetry) {
        _awaitingRetry = true;
        _persistence.addListener(_onPersistChanged);
        _recovery.addListener(_onPersistChanged);
      }
      return;
    }
    _applying = true;
    try {
      for (final lesson in _summary.confirmedLessons) {
        final save = store.markUnitLearned(lesson.id);
        _persistence.trackKana(save);
        await save;
      }
      if (!mounted) return;
      _draftClearIssued = true;
      _persistence.trackPlacement(widget.checks.clear());
    } catch (_) {
      // Banner already tracks the kana failure. Keep the draft so retry
      // or a later results visit can finish the pair.
      if (!_awaitingRetry) {
        _awaitingRetry = true;
        _persistence.addListener(_onPersistChanged);
        _recovery.addListener(_onPersistChanged);
      }
    } finally {
      _applying = false;
    }
  }

  void _fill(Lesson lesson) {
    Navigator.of(context).pushReplacement(StudyScreen.route(lesson));
  }

  void _backToLessons() {
    Navigator.of(
      context,
    ).popUntil((r) => r.settings.name == LessonsScreen.routeName || r.isFirst);
  }

  void _backHome() {
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<KanaProgressRepository>();
    final dailyReady = DailySession.isReady(
      StudySet.learned(store),
      stats: store.stats,
      now: DateTime.now(),
    );

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(AppStrings.placementTitle),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            const Text(
              AppStrings.placementClose,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 19, height: 1.5, color: AppColors.ink),
            ),
            const SizedBox(height: 24),
            if (_summary.independent.isNotEmpty)
              _KanaGroup(
                title: AppStrings.placementIndependent,
                kana: _summary.independent,
                color: AppColors.successSoft,
                border: AppColors.success,
              ),
            if (_summary.prompted.isNotEmpty)
              _KanaGroup(
                title: AppStrings.placementPrompted,
                kana: _summary.prompted,
                color: AppColors.warningSoft,
                border: AppColors.warning,
              ),
            if (_summary.unknown.isNotEmpty)
              _KanaGroup(
                title: AppStrings.placementForgotten,
                kana: _summary.unknown,
                color: AppColors.errorSoft,
                border: AppColors.error,
              ),
            const SizedBox(height: 8),
            if (_summary.hasGaps) ...[
              if (_summary.gapLessons.length == 1)
                FilledButton(
                  onPressed: () => _fill(_summary.gapLessons.first),
                  child: const Text(AppStrings.placementNextFill),
                )
              else ...[
                FilledButton(
                  onPressed: () => _fill(_summary.gapLessons.first),
                  child: const Text(AppStrings.placementNextFill),
                ),
                const SizedBox(height: 10),
                for (final lesson in _summary.gapLessons) ...[
                  OutlinedButton(
                    style: _outline(),
                    onPressed: () => _fill(lesson),
                    child: Text(AppStrings.placementFillRow(lesson.title)),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
              const SizedBox(height: 10),
            ],
            if (dailyReady) ...[
              OutlinedButton(
                style: _outline(),
                onPressed: _backHome,
                child: const Text(AppStrings.placementNextDaily),
              ),
              const SizedBox(height: 10),
            ],
            OutlinedButton(
              style: _outline(),
              onPressed: _backToLessons,
              child: const Text(AppStrings.placementNextLessons),
            ),
          ],
        ),
      ),
    );
  }

  ButtonStyle _outline() => OutlinedButton.styleFrom(
    minimumSize: const Size.fromHeight(54),
    side: const BorderSide(color: AppColors.hairline),
    foregroundColor: AppColors.ink,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  );
}

class _KanaGroup extends StatelessWidget {
  const _KanaGroup({
    required this.title,
    required this.kana,
    required this.color,
    required this.border,
  });

  final String title;
  final List<Kana> kana;
  final Color color;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final k in kana)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: border),
                  ),
                  child: Text(
                    k.character,
                    style: const TextStyle(fontSize: 26, color: AppColors.ink),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
