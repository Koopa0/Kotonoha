// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/placement_check_repository.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/lesson.dart';
import 'package:kotonoha/domain/models/placement_check.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/domain/use_cases/placement_check.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/placement/placement_check_screen.dart';
import 'package:kotonoha/ui/placement/placement_result_screen.dart';
import 'package:provider/provider.dart';

/// The learner names rows they have already met. Beginners stay on 手解き;
/// this screen never marks a row fluent by itself.
class PlacementScopeScreen extends StatefulWidget {
  const PlacementScopeScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const PlacementScopeScreen());

  @override
  State<PlacementScopeScreen> createState() => _PlacementScopeScreenState();
}

class _PlacementScopeScreenState extends State<PlacementScopeScreen> {
  PlacementCheckRepository? _checks;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final repo = await PlacementCheckRepository.load();
    if (!mounted) {
      repo.dispose();
      return;
    }
    setState(() => _checks = repo);
  }

  @override
  void dispose() {
    _checks?.dispose();
    super.dispose();
  }

  Future<void> _startNew(List<Lesson> catalog) async {
    final repo = _checks;
    if (repo == null) return;
    final selected = [
      for (final lesson in catalog)
        if (_selected.contains(lesson.id)) lesson,
    ];
    final draft = PlacementCheck.start(selected);
    if (draft == null) return;
    await repo.save(draft);
    if (!mounted) return;
    _openCheck(draft);
  }

  void _resume() {
    final draft = _checks?.draft;
    if (draft == null || !draft.hasProgress) return;
    if (draft.isComplete) {
      Navigator.of(context)
          .push(PlacementResultScreen.route(draft: draft, checks: _checks!));
      return;
    }
    if (draft.isInProgress) _openCheck(draft);
  }

  Future<void> _discardAndStay() async {
    await _checks?.clear();
    if (mounted) setState(() {});
  }

  void _openCheck(PlacementDraft draft) {
    Navigator.of(context)
        .push(PlacementCheckScreen.route(draft: draft, checks: _checks!));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<KanaProgressRepository>();
    final catalog = Lessons.fromKana(store.allKana);
    final hira = catalog.where((l) => l.script == KanaScript.hiragana).toList();
    final kata = catalog.where((l) => l.script == KanaScript.katakana).toList();
    final draft = _checks?.draft;
    final canResume = draft != null && draft.hasProgress;
    final canStart = _selected.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.placementTitle)),
      body: SafeArea(
        child: Column(
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
                      finished: draft.isComplete,
                      onResume: _resume,
                      onDiscard: _discardAndStay,
                    ),
                  ],
                  if (hira.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const _SectionHeader(AppStrings.hiraganaSection),
                    for (final lesson in hira) ...[
                      _ScopeTile(
                        lesson: lesson,
                        learned: store.isUnitLearned(lesson.id),
                        selected: _selected.contains(lesson.id),
                        onChanged: (on) => setState(() {
                          if (on) {
                            _selected.add(lesson.id);
                          } else {
                            _selected.remove(lesson.id);
                          }
                        }),
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
                        learned: store.isUnitLearned(lesson.id),
                        selected: _selected.contains(lesson.id),
                        onChanged: (on) => setState(() {
                          if (on) {
                            _selected.add(lesson.id);
                          } else {
                            _selected.remove(lesson.id);
                          }
                        }),
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
                    onPressed: canStart ? () => _startNew(catalog) : null,
                    child: const Text(AppStrings.placementStart),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
  final VoidCallback onResume;
  final VoidCallback onDiscard;

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
