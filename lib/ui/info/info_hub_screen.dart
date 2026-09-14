// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/domain/data/info_drill_dataset.dart';
import 'package:kotonoha/domain/models/info_drill.dart';
import 'package:kotonoha/domain/use_cases/info_session.dart';
import 'package:kotonoha/domain/use_cases/study_set.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/ferry/ferry_screen.dart';
import 'package:kotonoha/ui/info/info_screen.dart';
import 'package:kotonoha/ui/lessons/lessons_screen.dart';
import 'package:kotonoha/ui/reading/reading_screen.dart';
import 'package:provider/provider.dart';

/// Learn-then-practice door for travel amount / time / headcount extraction.
class InfoHubScreen extends StatelessWidget {
  const InfoHubScreen({
    this.clock,
    this.drills,
    this.title = AppStrings.infoTitle,
    this.purpose = AppStrings.infoPurpose,
    this.meetTitle = AppStrings.infoMeetTitle,
    this.entryName = AppStrings.infoEntry,
    super.key,
  });

  final DateTime Function()? clock;
  final List<InfoDrill>? drills;
  final String title;
  final String purpose;
  final String meetTitle;
  final String entryName;

  List<InfoDrill> get _drills => drills ?? kInfoDrills;

  static Route<void> route({
    DateTime Function()? clock,
    List<InfoDrill>? drills,
    String? title,
    String? purpose,
    String? meetTitle,
    String? entryName,
  }) => MaterialPageRoute<void>(
    builder: (_) => InfoHubScreen(
      clock: clock,
      drills: drills,
      title: title ?? AppStrings.infoTitle,
      purpose: purpose ?? AppStrings.infoPurpose,
      meetTitle: meetTitle ?? AppStrings.infoMeetTitle,
      entryName: entryName ?? AppStrings.infoEntry,
    ),
    settings: RouteSettings(
      name: drills == null ? 'info-hub' : 'info-hub-${drills.first.id}',
    ),
  );

  Set<String> _learnedChars(BuildContext context) =>
      StudySet.learned(context.read<KanaProgressRepository>())
          .map((k) => k.character)
          .toSet();

  InfoSessionView _view(BuildContext context) {
    final kana = context.watch<KanaProgressRepository>();
    final words = context.watch<WordProgressRepository>();
    return InfoSession.inspect(
      learnedChars: StudySet.learned(kana).map((k) => k.character).toSet(),
      stats: words.stats,
      drills: _drills,
    );
  }

  @override
  Widget build(BuildContext context) {
    final view = _view(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Text(
              purpose,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 16,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              view.canPractice
                  ? AppStrings.infoReadyHint
                  : AppStrings.infoMeetHint,
              style: const TextStyle(color: AppColors.inkMuted, height: 1.5),
            ),
            if (view.needsKanaFirst || view.missingUnits.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                AppStrings.infoNeedKana,
                style: TextStyle(color: AppColors.inkMuted, height: 1.5),
              ),
              if (view.missingUnits.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  AppStrings.infoMissingKana(
                    view.missingUnits.take(8).join(' '),
                  ),
                  style: const TextStyle(
                    color: AppColors.inkMuted,
                    height: 1.5,
                  ),
                ),
              ],
            ],
            const SizedBox(height: 24),
            if (view.needsKanaFirst || view.missingUnits.isNotEmpty)
              _ActionButton(
                key: const ValueKey<String>('info-learn-kana'),
                label: AppStrings.travelSceneLearnAction,
                productName: AppStrings.continueLearning,
                onPressed: () =>
                    Navigator.of(context).push(LessonsScreen.route()),
              ),
            if (view.canMeet) ...[
              if (view.needsKanaFirst || view.missingUnits.isNotEmpty)
                const SizedBox(height: 12),
              _ActionButton(
                key: const ValueKey<String>('info-meet'),
                label: AppStrings.travelSceneMeetAction,
                productName: AppStrings.ferryEntry,
                onPressed: () => _startMeet(context),
              ),
            ],
            if (view.canPractice) ...[
              const SizedBox(height: 12),
              _ActionButton(
                key: const ValueKey<String>('info-start'),
                label: AppStrings.infoStartAction,
                productName: entryName,
                kind: _ActionKind.outlined,
                onPressed: () => _startPractice(context),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _startMeet(BuildContext context, {bool replace = false}) {
    final learned = _learnedChars(context);
    final stats = context.read<WordProgressRepository>().stats;
    final words = InfoSession.composeIntroWords(
      learnedChars: learned,
      stats: stats,
      drills: _drills,
    );
    if (words.isNotEmpty) {
      final route = FerryScreen.route(
        words,
        meetTitle,
        clock: clock,
        onMore: () => _continueMeet(context),
      );
      unawaited(
        replace
            ? Navigator.of(context).pushReplacement(route)
            : Navigator.of(context).push(route),
      );
      return;
    }
    final phrases = InfoSession.composeIntroPhrases(
      learnedChars: learned,
      stats: stats,
      drills: _drills,
    );
    if (phrases.isNotEmpty) {
      final route = ReadingScreen.route(
        phrases,
        meetTitle,
        clock: clock,
        onMore: () => _continueMeet(context),
      );
      unawaited(
        replace
            ? Navigator.of(context).pushReplacement(route)
            : Navigator.of(context).push(route),
      );
      return;
    }
    if (replace) Navigator.of(context).pop();
  }

  void _continueMeet(BuildContext context) {
    final learned = _learnedChars(context);
    final stats = context.read<WordProgressRepository>().stats;
    final leftover = InfoSession.unreadRequired(
      learnedChars: learned,
      stats: stats,
      drills: _drills,
    );
    if (leftover.isNotEmpty) {
      _startMeet(context, replace: true);
      return;
    }
    Navigator.of(context).pop();
  }

  void _startPractice(BuildContext context, {bool replace = false}) {
    final drills = InfoSession.compose(
      learnedChars: _learnedChars(context),
      rng: Random(),
      stats: context.read<WordProgressRepository>().stats,
      drills: _drills,
    );
    if (drills.isEmpty) return;
    final route = InfoScreen.route(
      drills,
      clock: clock,
      onMore: () => _startPractice(context, replace: true),
    );
    unawaited(
      replace
          ? Navigator.of(context).pushReplacement(route)
          : Navigator.of(context).push(route),
    );
  }
}

enum _ActionKind { filled, outlined }

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.productName,
    required this.onPressed,
    this.kind = _ActionKind.filled,
    super.key,
  });

  final String label;
  final String productName;
  final VoidCallback onPressed;
  final _ActionKind kind;

  @override
  Widget build(BuildContext context) {
    final child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, textAlign: TextAlign.center),
        const SizedBox(height: 2),
        Text(
          productName,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: kind == _ActionKind.filled
                ? AppColors.onButtonMuted
                : AppColors.inkMuted,
          ),
        ),
      ],
    );
    const padding = EdgeInsets.symmetric(horizontal: 16, vertical: 12);
    return switch (kind) {
      _ActionKind.filled => FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          padding: padding,
          minimumSize: const Size(double.infinity, 56),
        ),
        child: child,
      ),
      _ActionKind.outlined => OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: padding,
          minimumSize: const Size(double.infinity, 52),
          side: const BorderSide(color: AppColors.hairline),
          foregroundColor: AppColors.ink,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: child,
      ),
    };
  }
}
