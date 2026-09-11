// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/lesson.dart';
import 'package:kotonoha/domain/use_cases/lessons.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/placement/placement_scope_screen.dart';
import 'package:kotonoha/ui/study/study_screen.dart';
import 'package:provider/provider.dart';

/// Lists the gojūon rows as sequential lessons, showing which are learned.
class LessonsScreen extends StatelessWidget {
  const LessonsScreen({super.key});

  /// Named so the lesson-test result screen can pop back here.
  static const String routeName = 'lessons';

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (_) => const LessonsScreen(),
    settings: const RouteSettings(name: routeName),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.lessonsTitle)),
      body: SafeArea(
        child: Consumer<KanaProgressRepository>(
          builder: (context, store, _) {
            final lessons = Lessons.fromKana(store.allKana);
            final hira = lessons
                .where((l) => l.script == KanaScript.hiragana)
                .toList();
            final kata = lessons
                .where((l) => l.script == KanaScript.katakana)
                .toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                const _PlacementEntry(),
                const SizedBox(height: 20),
                if (hira.isNotEmpty) ...[
                  const _SectionHeader(AppStrings.hiraganaSection),
                  for (final l in hira) ...[
                    _LessonTile(lesson: l, learned: store.isUnitLearned(l.id)),
                    const SizedBox(height: 12),
                  ],
                ],
                if (kata.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const _SectionHeader(AppStrings.katakanaSection),
                  for (final l in kata) ...[
                    _LessonTile(lesson: l, learned: store.isUnitLearned(l.id)),
                    const SizedBox(height: 12),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PlacementEntry extends StatelessWidget {
  const _PlacementEntry();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: const CircleAvatar(
          radius: 26,
          backgroundColor: AppColors.accentSoft,
          child: Icon(Icons.visibility_outlined, color: AppColors.accent),
        ),
        title: const Text(
          AppStrings.placementEntry,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: AppColors.ink,
          ),
        ),
        subtitle: const Text(
          AppStrings.placementEntrySubtitle,
          style: TextStyle(color: AppColors.inkMuted, fontSize: 14),
        ),
        trailing: const Icon(Icons.chevron_right, color: AppColors.inkMuted),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        onTap: () => Navigator.of(context).push(PlacementScopeScreen.route()),
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
      padding: const EdgeInsets.only(top: 8, bottom: 12),
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

class _LessonTile extends StatelessWidget {
  const _LessonTile({required this.lesson, required this.learned});

  final Lesson lesson;
  final bool learned;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          radius: 26,
          backgroundColor: learned
              ? AppColors.successSoft
              : AppColors.accentSoft,
          child: Text(
            lesson.representative,
            style: TextStyle(
              fontSize: 26,
              color: learned ? AppColors.success : AppColors.accent,
            ),
          ),
        ),
        title: Text(
          lesson.title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: AppColors.ink,
          ),
        ),
        subtitle: Text(
          lesson.kana.map((k) => k.character).join(' '),
          style: const TextStyle(color: AppColors.inkMuted, fontSize: 15),
        ),
        trailing: learned
            ? const Icon(Icons.check_circle_rounded, color: AppColors.success)
            : const Icon(Icons.chevron_right, color: AppColors.inkMuted),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        onTap: () => Navigator.of(context).push(StudyScreen.route(lesson)),
      ),
    );
  }
}
