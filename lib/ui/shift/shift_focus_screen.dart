// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/domain/models/shift_drill.dart';
import 'package:kotonoha/domain/use_cases/shift_session.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/shift/shift_practice_screen.dart';

/// Picker for today's stuck point. The learner names a curated focus / drill
/// without editing the Dart corpus. Travel-scene selection stays on #47.
class ShiftFocusScreen extends StatefulWidget {
  const ShiftFocusScreen({super.key, this.drills, this.onStarted});

  /// Injectable catalogue for tests; defaults to the human-checked slice.
  final List<ShiftDrill>? drills;

  /// Test seam: called after a session is pushed.
  final ValueChanged<ShiftDrill>? onStarted;

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const ShiftFocusScreen());

  @override
  State<ShiftFocusScreen> createState() => _ShiftFocusScreenState();
}

class _ShiftFocusScreenState extends State<ShiftFocusScreen> {
  final TextEditingController _source = TextEditingController();
  late String _selectedId;

  List<ShiftFocus> get _focuses => ShiftSession.focuses(drills: _drills);

  List<ShiftDrill> get _drills =>
      widget.drills ?? ShiftSession.focuses().expand((f) => f.drills).toList();

  @override
  void initState() {
    super.initState();
    _selectedId = _drills.first.id;
  }

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  void _start() {
    final drill = ShiftSession.drillById(_selectedId, drills: _drills);
    if (drill == null) return;
    final sourceUrl = _source.text.trim();
    widget.onStarted?.call(drill);
    Navigator.of(context).push(
      ShiftPracticeScreen.route(
        drill,
        sourceUrl: sourceUrl.isEmpty ? null : sourceUrl,
        onMore: () => _again(drill, sourceUrl),
      ),
    );
  }

  void _again(ShiftDrill drill, String sourceUrl) {
    Navigator.of(context).pushReplacement(
      ShiftPracticeScreen.route(
        drill,
        sourceUrl: sourceUrl.isEmpty ? null : sourceUrl,
        onMore: () => _again(drill, sourceUrl),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                        subtitle: Text(drill.base.kana),
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
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
              ),
              child: const Text(AppStrings.shiftStart),
            ),
          ],
        ),
      ),
    );
  }
}
