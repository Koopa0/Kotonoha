// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/placement_check_repository.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/lesson.dart';
import 'package:kotonoha/domain/models/placement_check.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/lessons/lessons_screen.dart';
import 'package:kotonoha/ui/placement/placement_result_viewmodel.dart';
import 'package:kotonoha/ui/study/study_screen.dart';
import 'package:provider/provider.dart';

/// Next steps after an explicit check. Lists kana by how they were graded;
/// no rank, XP, or percentage claim.
///
/// A thin View over [PlacementResultViewModel]: it renders the summary and
/// navigates. Applying the confirmed rows, clearing the draft once they
/// are on disk, and waiting out a blocked write are the ViewModel's.
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
  late final PlacementResultViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = PlacementResultViewModel(
      draft: widget.draft,
      checks: widget.checks,
      kana: context.read<KanaProgressRepository>(),
      persistence: context.read<ProgressPersistenceController>(),
      recovery: context.read<ProgressRestoreRecoveryController>(),
    );
    // Apply after the first frame so no owner notifies during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _vm.applyConfirmed();
    });
  }

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
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
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(AppStrings.placementTitle),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _vm,
          builder: (context, _) => _list(dailyReady: _vm.isDailyReady),
        ),
      ),
    );
  }

  Widget _list({required bool dailyReady}) {
    final summary = _vm.summary;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        const Text(
          AppStrings.placementClose,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 19, height: 1.5, color: AppColors.ink),
        ),
        const SizedBox(height: 24),
        if (summary.independent.isNotEmpty)
          _KanaGroup(
            title: AppStrings.placementIndependent,
            kana: summary.independent,
            color: AppColors.successSoft,
            border: AppColors.success,
          ),
        if (summary.prompted.isNotEmpty)
          _KanaGroup(
            title: AppStrings.placementPrompted,
            kana: summary.prompted,
            color: AppColors.warningSoft,
            border: AppColors.warning,
          ),
        if (summary.unknown.isNotEmpty)
          _KanaGroup(
            title: AppStrings.placementForgotten,
            kana: summary.unknown,
            color: AppColors.errorSoft,
            border: AppColors.error,
          ),
        const SizedBox(height: 8),
        if (summary.hasGaps) ...[
          if (summary.gapLessons.length == 1)
            FilledButton(
              onPressed: () => _fill(summary.gapLessons.first),
              child: const Text(AppStrings.placementNextFill),
            )
          else ...[
            FilledButton(
              onPressed: () => _fill(summary.gapLessons.first),
              child: const Text(AppStrings.placementNextFill),
            ),
            const SizedBox(height: 10),
            for (final lesson in summary.gapLessons) ...[
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
