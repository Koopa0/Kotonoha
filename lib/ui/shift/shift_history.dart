// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/domain/models/shift_drill.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';

/// Dated self-grades for one drill. Not a score, streak, or mastery mark.
class ShiftHistoryView extends StatelessWidget {
  const ShiftHistoryView({required this.grades, super.key});

  final List<ShiftSelfGrade> grades;

  @override
  Widget build(BuildContext context) {
    if (grades.isEmpty) return const SizedBox.shrink();
    final groups = <String, List<ShiftSelfGrade>>{};
    for (final grade in grades) {
      groups
          .putIfAbsent('${grade.day}:${grade.beat.name}', () => [])
          .add(grade);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          AppStrings.shiftHistoryTitle,
          style: TextStyle(
            color: AppColors.inkMuted,
            fontWeight: FontWeight.w600,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        for (final entry in groups.entries) ...[
          Text(
            AppStrings.shiftHistoryDay(
              entry.value.first.day,
              entry.value.first.beat,
            ),
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          for (final grade in entry.value)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                _copy(grade),
                style: const TextStyle(color: AppColors.inkMuted, height: 1.45),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  String _copy(ShiftSelfGrade grade) {
    switch (grade.check) {
      case ShiftCheck.read:
        return AppStrings.shiftReadSelfGrade(
          prompted: grade.prompted,
          correct: grade.correct,
        );
      case ShiftCheck.verb:
        return AppStrings.shiftVerbSelfGrade(
          prompted: grade.prompted,
          correct: grade.correct,
        );
      case ShiftCheck.roles:
        return AppStrings.shiftRolesSelfGrade(
          prompted: grade.prompted,
          correct: grade.correct,
        );
      case ShiftCheck.sense:
        return AppStrings.shiftSenseSelfGrade(
          prompted: grade.prompted,
          correct: grade.correct,
          readSupport: grade.readSupport,
        );
    }
  }
}
