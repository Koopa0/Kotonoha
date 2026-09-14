// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/placement_check_repository.dart';
import 'package:kotonoha/domain/models/lesson.dart';
import 'package:kotonoha/domain/models/placement_check.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/persistence/progress_restore_recovery_controller.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/placement/placement_check_screen.dart';
import 'package:kotonoha/ui/placement/placement_result_screen.dart';
import 'package:kotonoha/ui/placement/placement_scope_viewmodel.dart';
import 'package:provider/provider.dart';

/// The learner names rows they have already met. Beginners stay on 手解き;
/// this screen never marks a row fluent by itself.
///
/// A thin View over [PlacementScopeViewModel]: it renders the rows and
/// navigates on each command's outcome. The selection, the draft's start /
/// resume / discard and whether writes are allowed are the ViewModel's.
class PlacementScopeScreen extends StatefulWidget {
  const PlacementScopeScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const PlacementScopeScreen());

  @override
  State<PlacementScopeScreen> createState() => _PlacementScopeScreenState();
}

class _PlacementScopeScreenState extends State<PlacementScopeScreen> {
  late final PlacementScopeViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = PlacementScopeViewModel(
      kana: context.read<KanaProgressRepository>(),
      checks: context.read<PlacementCheckRepository>(),
      persistence: context.read<ProgressPersistenceController>(),
      recovery: context.read<ProgressRestoreRecoveryController>(),
    );
  }

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  Future<void> _startNew() async {
    final draft = await _vm.startNew();
    if (!mounted || draft == null) return;
    _openCheck(draft);
  }

  void _resume() {
    switch (_vm.resume()) {
      case PlacementResume.results:
        Navigator.of(context).push(
          PlacementResultScreen.route(draft: _vm.draft, checks: _vm.checks),
        );
      case PlacementResume.check:
        _openCheck(_vm.draft);
      case null:
        return;
    }
  }

  void _openCheck(PlacementDraft draft) {
    Navigator.of(context)
        .push(PlacementCheckScreen.route(draft: draft, checks: _vm.checks));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.placementTitle)),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _vm,
          builder: (context, _) => _body(),
        ),
      ),
    );
  }

  Widget _body() {
    final hira = _vm.hiragana;
    final kata = _vm.katakana;
    final blocked = _vm.isBlocked;
    final canResume = _vm.canResume;
    final canStart = _vm.canStart;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            children: [
              const Text(
                AppStrings.placementIntro,
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 16,
                  height: 1.55,
                ),
              ),
              if (canResume) ...[
                const SizedBox(height: 16),
                _ResumeCard(
                  finished: _vm.isResumeFinished,
                  onResume: blocked ? null : _resume,
                  onDiscard: blocked ? null : _vm.discardAndStay,
                ),
              ],
              if (hira.isNotEmpty) ...[
                const SizedBox(height: 20),
                const _SectionHeader(AppStrings.hiraganaSection),
                for (final lesson in hira) ...[
                  _ScopeTile(
                    lesson: lesson,
                    learned: _vm.isUnitLearned(lesson.id),
                    selected: _vm.isSelected(lesson.id),
                    onChanged: (on) => _vm.setSelected(lesson.id, selected: on),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
              if (kata.isNotEmpty) ...[
                const SizedBox(height: 8),
                const _SectionHeader(AppStrings.katakanaSection),
                for (final lesson in kata) ...[
                  _ScopeTile(
                    lesson: lesson,
                    learned: _vm.isUnitLearned(lesson.id),
                    selected: _vm.isSelected(lesson.id),
                    onChanged: (on) => _vm.setSelected(lesson.id, selected: on),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!canStart)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    AppStrings.placementNeedSelection,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.inkMuted),
                  ),
                ),
              FilledButton(
                onPressed: canStart ? _startNew : null,
                child: const Text(AppStrings.placementStart),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({
    required this.finished,
    required this.onResume,
    required this.onDiscard,
  });

  final bool finished;
  final VoidCallback? onResume;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              AppStrings.placementResumeHint,
              style: TextStyle(color: AppColors.ink, fontSize: 15, height: 1.5),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onResume,
              child: Text(
                finished
                    ? AppStrings.placementSeeResult
                    : AppStrings.placementResume,
              ),
            ),
            TextButton(
              onPressed: onDiscard,
              style: TextButton.styleFrom(foregroundColor: AppColors.inkMuted),
              child: const Text(AppStrings.placementStartNew),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
      ),
    );
  }
}

class _ScopeTile extends StatelessWidget {
  const _ScopeTile({
    required this.lesson,
    required this.learned,
    required this.selected,
    required this.onChanged,
  });

  final Lesson lesson;
  final bool learned;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: CheckboxListTile(
        value: selected,
        onChanged: (on) => onChanged(on ?? false),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        secondary: CircleAvatar(
          radius: 24,
          backgroundColor: learned
              ? AppColors.successSoft
              : AppColors.accentSoft,
          child: Text(
            lesson.representative,
            style: TextStyle(
              fontSize: 22,
              color: learned ? AppColors.success : AppColors.accent,
            ),
          ),
        ),
        title: Text(
          lesson.title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 17,
            color: AppColors.ink,
          ),
        ),
        subtitle: Text(
          lesson.kana.map((k) => k.character).join(' '),
          style: const TextStyle(color: AppColors.inkMuted, fontSize: 14),
        ),
      ),
    );
  }
}
