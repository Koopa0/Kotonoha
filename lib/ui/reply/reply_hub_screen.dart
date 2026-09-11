// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/domain/models/reply_drill.dart';
import 'package:kotonoha/domain/use_cases/reply_session.dart';
import 'package:kotonoha/domain/use_cases/study_set.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/ferry/ferry_screen.dart';
import 'package:kotonoha/ui/lessons/lessons_screen.dart';
import 'package:kotonoha/ui/reading/reading_screen.dart';
import 'package:kotonoha/ui/reply/reply_screen.dart';
import 'package:provider/provider.dart';

/// Learn-then-practice door for station or clothing replies. Isolated from #47
/// [TravelScene] membership and #48 換句.
class ReplyHubScreen extends StatelessWidget {
  const ReplyHubScreen({this.scene = ReplySceneId.station, this.clock, super.key});

  final ReplySceneId scene;
  final DateTime Function()? clock;

  static Route<void> route({
    ReplySceneId scene = ReplySceneId.station,
    DateTime Function()? clock,
  }) =>
      MaterialPageRoute<void>(
        builder: (_) => ReplyHubScreen(scene: scene, clock: clock),
        settings: RouteSettings(name: 'reply-hub-${scene.name}'),
      );

  String get _purpose => switch (scene) {
    ReplySceneId.station => AppStrings.replyPurpose,
    ReplySceneId.clothing => AppStrings.replyClothingPurpose,
  };

  String get _meetHint => switch (scene) {
    ReplySceneId.station => AppStrings.replyMeetHint,
    ReplySceneId.clothing => AppStrings.replyClothingMeetHint,
  };

  String get _meetTitle => switch (scene) {
    ReplySceneId.station => AppStrings.replyMeetTitle,
    ReplySceneId.clothing => AppStrings.replyClothingMeetTitle,
  };

  Set<String> _learnedChars(BuildContext context) =>
      StudySet.learned(context.read<KanaProgressRepository>())
          .map((k) => k.character)
          .toSet();

  ReplySessionView _view(BuildContext context) {
    final kana = context.watch<KanaProgressRepository>();
    final words = context.watch<WordProgressRepository>();
    return ReplySession.inspect(
      scene: scene,
      learnedChars: StudySet.learned(kana).map((k) => k.character).toSet(),
      stats: words.stats,
    );
  }

  @override
  Widget build(BuildContext context) {
    final view = _view(context);
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.replyTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Text(
              _purpose,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 16,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              view.canPractice ? AppStrings.replyReadyHint : _meetHint,
              style: const TextStyle(color: AppColors.inkMuted, height: 1.5),
            ),
            if (view.needsKanaFirst || view.missingUnits.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                AppStrings.replyNeedKana,
                style: TextStyle(color: AppColors.inkMuted, height: 1.5),
              ),
              if (view.missingUnits.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  AppStrings.replyMissingKana(
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
                key: const ValueKey<String>('reply-learn-kana'),
                label: AppStrings.travelSceneLearnAction,
                productName: AppStrings.continueLearning,
                onPressed: () =>
                    Navigator.of(context).push(LessonsScreen.route()),
              ),
            if (view.canMeet) ...[
              if (view.needsKanaFirst || view.missingUnits.isNotEmpty)
                const SizedBox(height: 12),
              _ActionButton(
                key: const ValueKey<String>('reply-meet'),
                label: AppStrings.travelSceneMeetAction,
                productName: AppStrings.ferryEntry,
                onPressed: () => _startMeet(context),
              ),
            ],
            if (view.canPractice) ...[
              const SizedBox(height: 12),
              _ActionButton(
                key: const ValueKey<String>('reply-start'),
                label: AppStrings.replyStartAction,
                productName: AppStrings.replyEntry,
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
    final words = ReplySession.unreadRequiredWords(
      scene: scene,
      learnedChars: learned,
      stats: stats,
    );
    if (words.isNotEmpty) {
      final route = FerryScreen.route(
        words,
        _meetTitle,
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
    final phrases = ReplySession.unreadRequiredPhrases(
      scene: scene,
      learnedChars: learned,
      stats: stats,
    );
    if (phrases.isNotEmpty) {
      final route = ReadingScreen.route(
        phrases,
        _meetTitle,
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
    final leftover = ReplySession.unreadRequired(
      scene: scene,
      learnedChars: learned,
      stats: stats,
    );
    if (leftover.isNotEmpty) {
      _startMeet(context, replace: true);
      return;
    }
    Navigator.of(context).pop();
  }

  void _startPractice(BuildContext context, {bool replace = false}) {
    final drills = ReplySession.compose(
      scene: scene,
      learnedChars: _learnedChars(context),
      rng: Random(),
      stats: context.read<WordProgressRepository>().stats,
    );
    if (drills.isEmpty) return;
    final route = ReplyScreen.route(
      drills,
      scene: scene,
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
                ? Colors.white.withValues(alpha: 0.82)
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
