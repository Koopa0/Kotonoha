// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/domain/data/info_drill_dataset.dart';
import 'package:kotonoha/domain/models/reply_drill.dart';
import 'package:kotonoha/domain/use_cases/daily_bridge.dart';
import 'package:kotonoha/domain/use_cases/study_set.dart';
import 'package:kotonoha/domain/use_cases/travel_scene.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/ferry/ferry_screen.dart';
import 'package:kotonoha/ui/info/info_hub_screen.dart';
import 'package:kotonoha/ui/lessons/lessons_screen.dart';
import 'package:kotonoha/ui/listening/listening_screen.dart';
import 'package:kotonoha/ui/reading/reading_screen.dart';
import 'package:kotonoha/ui/reply/reply_hub_screen.dart';
import 'package:provider/provider.dart';

/// Picker for travel purposes. Isolated from 渡し舟 / 黙読 / #48 精讀入口.
class TravelSceneScreen extends StatelessWidget {
  const TravelSceneScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    builder: (_) => const TravelSceneScreen(),
    settings: const RouteSettings(name: 'travel-scene'),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.travelSceneTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            const Text(
              AppStrings.travelSceneSubtitle,
              style: TextStyle(color: AppColors.inkMuted, height: 1.5),
            ),
            const SizedBox(height: 16),
            _SceneCard(
              key: const ValueKey<String>('travel-scene-transport'),
              label: AppStrings.travelSceneTransport,
              purpose: AppStrings.travelScenePurposeTransport,
              onTap: () =>
                  Navigator.of(context)
                      .push(TravelSceneHub.route(TravelSceneId.transport)),
            ),
            const SizedBox(height: 12),
            _SceneCard(
              key: const ValueKey<String>('travel-scene-clothing'),
              label: AppStrings.travelSceneClothing,
              purpose: AppStrings.travelScenePurposeClothing,
              onTap: () =>
                  Navigator.of(context)
                      .push(TravelSceneHub.route(TravelSceneId.clothing)),
            ),
            const SizedBox(height: 12),
            _SceneCard(
              key: const ValueKey<String>('travel-scene-shrine'),
              label: AppStrings.travelSceneShrine,
              purpose: AppStrings.travelScenePurposeShrine,
              onTap: () =>
                  Navigator.of(context)
                      .push(TravelSceneHub.route(TravelSceneId.shrine)),
            ),
            const SizedBox(height: 12),
            _SceneCard(
              key: const ValueKey<String>('travel-scene-park'),
              label: AppStrings.travelSceneParkQueue,
              purpose: AppStrings.travelScenePurposeParkQueue,
              onTap: () =>
                  Navigator.of(context)
                      .push(TravelSceneHub.route(TravelSceneId.parkQueue)),
            ),
            const SizedBox(height: 12),
            _SceneCard(
              key: const ValueKey<String>('travel-scene-restaurant'),
              label: AppStrings.travelSceneRestaurant,
              purpose: AppStrings.travelScenePurposeRestaurant,
              onTap: () =>
                  Navigator.of(context)
                      .push(TravelSceneHub.route(TravelSceneId.restaurant)),
            ),
            const SizedBox(height: 12),
            _SceneCard(
              key: const ValueKey<String>('travel-scene-convenience'),
              label: AppStrings.travelSceneConvenience,
              purpose: AppStrings.travelScenePurposeConvenience,
              onTap: () =>
                  Navigator.of(context)
                      .push(TravelSceneHub.route(TravelSceneId.convenience)),
            ),
            const SizedBox(height: 12),
            _SceneCard(
              key: const ValueKey<String>('travel-scene-hotel'),
              label: AppStrings.travelSceneHotel,
              purpose: AppStrings.travelScenePurposeHotel,
              onTap: () =>
                  Navigator.of(context)
                      .push(TravelSceneHub.route(TravelSceneId.hotel)),
            ),
            const SizedBox(height: 12),
            _SceneCard(
              key: const ValueKey<String>('travel-scene-info'),
              label: AppStrings.infoAction,
              purpose: AppStrings.infoPurpose,
              onTap: () => Navigator.of(context).push(InfoHubScreen.route()),
            ),
          ],
        ),
      ),
    );
  }
}

/// Purpose + gated 先學 / 見面 / 回想 / 聽力. Choosing the scene writes nothing.
class TravelSceneHub extends StatelessWidget {
  const TravelSceneHub({required this.scene, this.clock, super.key});

  final TravelSceneId scene;

  /// Injectable so もう一回 is not night-suppressed in route tests.
  final DateTime Function()? clock;

  static Route<void> route(TravelSceneId scene, {DateTime Function()? clock}) =>
      MaterialPageRoute<void>(
        builder: (_) => TravelSceneHub(scene: scene, clock: clock),
        settings: RouteSettings(name: 'travel-scene-${scene.name}'),
      );

  DateTime Function() get _now => clock ?? DateTime.now;

  String get _label => switch (scene) {
    TravelSceneId.transport => AppStrings.travelSceneTransport,
    TravelSceneId.clothing => AppStrings.travelSceneClothing,
    TravelSceneId.shrine => AppStrings.travelSceneShrine,
    TravelSceneId.parkQueue => AppStrings.travelSceneParkQueue,
    TravelSceneId.restaurant => AppStrings.travelSceneRestaurant,
    TravelSceneId.convenience => AppStrings.travelSceneConvenience,
    TravelSceneId.hotel => AppStrings.travelSceneHotel,
  };

  String get _purpose => switch (scene) {
    TravelSceneId.transport => AppStrings.travelScenePurposeTransport,
    TravelSceneId.clothing => AppStrings.travelScenePurposeClothing,
    TravelSceneId.shrine => AppStrings.travelScenePurposeShrine,
    TravelSceneId.parkQueue => AppStrings.travelScenePurposeParkQueue,
    TravelSceneId.restaurant => AppStrings.travelScenePurposeRestaurant,
    TravelSceneId.convenience => AppStrings.travelScenePurposeConvenience,
    TravelSceneId.hotel => AppStrings.travelScenePurposeHotel,
  };

  ReplySceneId? get _replyScene => switch (scene) {
    TravelSceneId.clothing => ReplySceneId.clothing,
    TravelSceneId.restaurant => ReplySceneId.restaurant,
    TravelSceneId.convenience => ReplySceneId.convenience,
    TravelSceneId.transport ||
    TravelSceneId.shrine ||
    TravelSceneId.parkQueue ||
    TravelSceneId.hotel => null,
  };

  Set<String> _learnedChars(BuildContext context) =>
      StudySet.learned(context.read<KanaProgressRepository>())
          .map((k) => k.character)
          .toSet();

  TravelSceneView _view(BuildContext context) {
    final kana = context.watch<KanaProgressRepository>();
    final words = context.watch<WordProgressRepository>();
    return TravelScene.inspect(
      scene: scene,
      learnedChars: StudySet.learned(kana).map((k) => k.character).toSet(),
      stats: words.stats,
    );
  }

  @override
  Widget build(BuildContext context) {
    final view = _view(context);
    return Scaffold(
      appBar: AppBar(title: Text(_label)),
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
              view.canRecall
                  ? AppStrings.travelSceneReadyHint
                  : AppStrings.travelSceneMeetHint,
              style: const TextStyle(color: AppColors.inkMuted, height: 1.5),
            ),
            if (view.unreadable.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                AppStrings.travelSceneNeedKana,
                style: TextStyle(color: AppColors.inkMuted, height: 1.5),
              ),
              if (view.missingUnits.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  AppStrings.travelSceneMissingKana(
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
            if (view.needsKanaFirst || view.unreadable.isNotEmpty)
              _ActionButton(
                key: const ValueKey<String>('travel-learn-kana'),
                label: AppStrings.travelSceneLearnAction,
                productName: AppStrings.continueLearning,
                onPressed: () =>
                    Navigator.of(context).push(LessonsScreen.route()),
              ),
            if (view.canMeet) ...[
              if (view.needsKanaFirst || view.unreadable.isNotEmpty)
                const SizedBox(height: 12),
              _ActionButton(
                key: const ValueKey<String>('travel-meet'),
                label: AppStrings.travelSceneMeetAction,
                productName: AppStrings.ferryEntry,
                onPressed: () => _startMeet(context),
              ),
            ],
            if (view.canRecall) ...[
              const SizedBox(height: 12),
              _ActionButton(
                key: const ValueKey<String>('travel-recall'),
                label: AppStrings.travelSceneRecallAction,
                productName: AppStrings.sentenceEntry,
                kind: _ActionKind.outlined,
                onPressed: () => _startRecall(context),
              ),
            ],
            if (view.canListen) ...[
              const SizedBox(height: 12),
              _ActionButton(
                key: const ValueKey<String>('travel-listen'),
                label: AppStrings.travelSceneListenAction,
                productName: AppStrings.listeningEntry,
                kind: _ActionKind.outlined,
                onPressed: () => _startListen(context),
              ),
            ],
            if (scene == TravelSceneId.hotel) ...[
              const SizedBox(height: 12),
              _ActionButton(
                key: const ValueKey<String>('travel-hotel-info'),
                label: AppStrings.infoAction,
                productName: AppStrings.infoHotelEntry,
                kind: _ActionKind.outlined,
                onPressed: () => Navigator.of(context).push(
                  InfoHubScreen.route(
                    clock: clock,
                    drills: kHotelInfoDrills,
                    title: AppStrings.travelSceneHotel,
                    purpose: AppStrings.infoHotelPurpose,
                    meetTitle: AppStrings.infoHotelMeetTitle,
                    entryName: AppStrings.infoHotelEntry,
                  ),
                ),
              ),
            ],
            if (_replyScene != null) ...[
              const SizedBox(height: 12),
              _ActionButton(
                key: const ValueKey<String>('travel-reply'),
                label: AppStrings.replyAction,
                productName: AppStrings.replyEntry,
                kind: _ActionKind.outlined,
                onPressed: () => Navigator.of(
                  context,
                ).push(ReplyHubScreen.route(scene: _replyScene!, clock: clock)),
              ),
            ],
            if (scene == TravelSceneId.shrine) ...[
              const SizedBox(height: 12),
              _ActionButton(
                key: const ValueKey<String>('travel-reply-shrine'),
                label: AppStrings.replyAction,
                productName: AppStrings.replyEntry,
                kind: _ActionKind.outlined,
                onPressed: () => Navigator.of(context).push(
                  ReplyHubScreen.route(
                    scene: ReplySceneId.shrine,
                    clock: clock,
                  ),
                ),
              ),
            ],
            if (scene == TravelSceneId.parkQueue) ...[
              const SizedBox(height: 12),
              _ActionButton(
                key: const ValueKey<String>('travel-reply-park'),
                label: AppStrings.replyAction,
                productName: AppStrings.replyEntry,
                kind: _ActionKind.outlined,
                onPressed: () => Navigator.of(context).push(
                  ReplyHubScreen.route(
                    scene: ReplySceneId.parkQueue,
                    clock: clock,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _ActionButton(
                key: const ValueKey<String>('travel-reply-help'),
                label: AppStrings.replyHelpAction,
                productName: AppStrings.replyHelpEntry,
                kind: _ActionKind.outlined,
                onPressed: () => Navigator.of(context).push(
                  ReplyHubScreen.route(
                    scene: ReplySceneId.help,
                    clock: clock,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static void startMeet(
    BuildContext context, {
    required TravelSceneId scene,
    DateTime Function()? clock,
    bool replace = false,
    Set<String> excludeProgressIds = const {},
    VoidCallback? onFinished,
  }) {
    final hub = TravelSceneHub(scene: scene, clock: clock);
    hub._startMeet(
      context,
      replace: replace,
      excludeProgressIds: excludeProgressIds,
      onFinished: onFinished,
    );
  }

  static void startRecall(
    BuildContext context, {
    required TravelSceneId scene,
    DateTime Function()? clock,
    bool replace = false,
    Set<String> excludeProgressIds = const {},
    VoidCallback? onFinished,
  }) {
    final hub = TravelSceneHub(scene: scene, clock: clock);
    hub._startRecall(
      context,
      replace: replace,
      excludeProgressIds: excludeProgressIds,
      onFinished: onFinished,
    );
  }

  static void startListen(
    BuildContext context, {
    required TravelSceneId scene,
    DateTime Function()? clock,
    bool replace = false,
    Set<String> excludeProgressIds = const {},
    VoidCallback? onFinished,
  }) {
    final hub = TravelSceneHub(scene: scene, clock: clock);
    hub._startListen(
      context,
      replace: replace,
      excludeProgressIds: excludeProgressIds,
      onFinished: onFinished,
    );
  }

  void _startMeet(
    BuildContext context, {
    bool replace = false,
    Set<String> excludeProgressIds = const {},
    VoidCallback? onFinished,
  }) {
    final learned = _learnedChars(context);
    final stats = context.read<WordProgressRepository>().stats;
    final now = _now();
    final words = TravelScene.composeIntroWords(
      scene: scene,
      learnedChars: learned,
      rng: Random(),
      now: now,
      stats: stats,
      excludeProgressIds: excludeProgressIds,
    );
    if (words.isNotEmpty) {
      final nextExclude = DailyBridge.nextExclude(
        previous: excludeProgressIds,
        transfer: words,
      );
      final route = FerryScreen.route(
        words,
        AppStrings.travelSceneMeetTitle(_label),
        clock: clock,
        onMore: () =>
            _continueOrFinishMeet(context, excludeProgressIds: nextExclude),
        onFinished: onFinished,
      );
      unawaited(
        replace
            ? Navigator.of(context).pushReplacement(route)
            : Navigator.of(context).push(route),
      );
      return;
    }
    final phrases = TravelScene.composeIntroPhrases(
      scene: scene,
      learnedChars: learned,
      rng: Random(),
      now: now,
      stats: stats,
      excludeProgressIds: excludeProgressIds,
    );
    if (phrases.isNotEmpty) {
      final nextExclude = DailyBridge.nextExclude(
        previous: excludeProgressIds,
        transfer: phrases,
      );
      final route = ReadingScreen.route(
        phrases,
        AppStrings.travelSceneMeetTitle(_label),
        alreadyTransferredIds: excludeProgressIds,
        onMore: () =>
            _continueOrFinishMeet(context, excludeProgressIds: nextExclude),
        onFinished: onFinished,
      );
      unawaited(
        replace
            ? Navigator.of(context).pushReplacement(route)
            : Navigator.of(context).push(route),
      );
      return;
    }
    if (replace) {
      Navigator.of(context).pop();
    }
  }

  /// Leftover unread scene items continue 先見面. An empty pool pops back
  /// to the hub so もう一回 is never a dead control, and never pads or
  /// re-introduces to climb mastery.
  void _continueOrFinishMeet(
    BuildContext context, {
    required Set<String> excludeProgressIds,
  }) {
    final learned = _learnedChars(context);
    final stats = context.read<WordProgressRepository>().stats;
    final now = _now();
    final more = TravelScene.hasMoreIntro(
      scene: scene,
      learnedChars: learned,
      rng: Random(),
      now: now,
      stats: stats,
      excludeProgressIds: excludeProgressIds,
    );
    if (more) {
      _startMeet(
        context,
        replace: true,
        excludeProgressIds: excludeProgressIds,
      );
      return;
    }
    Navigator.of(context).pop();
  }

  void _startRecall(
    BuildContext context, {
    bool replace = false,
    Set<String> excludeProgressIds = const {},
    VoidCallback? onFinished,
  }) {
    final items = TravelScene.composeReview(
      scene: scene,
      learnedChars: _learnedChars(context),
      rng: Random(),
      now: _now(),
      stats: context.read<WordProgressRepository>().stats,
      excludeProgressIds: excludeProgressIds,
    );
    if (items.isEmpty) return;
    final nextExclude = DailyBridge.nextExclude(
      previous: excludeProgressIds,
      transfer: items,
    );
    final route = ReadingScreen.route(
      items,
      AppStrings.travelSceneRecallTitle(_label),
      alreadyTransferredIds: excludeProgressIds,
      onMore: () =>
          _startRecall(context, replace: true, excludeProgressIds: nextExclude),
      onFinished: onFinished,
    );
    unawaited(
      replace
          ? Navigator.of(context).pushReplacement(route)
          : Navigator.of(context).push(route),
    );
  }

  void _startListen(
    BuildContext context, {
    bool replace = false,
    Set<String> excludeProgressIds = const {},
    VoidCallback? onFinished,
  }) {
    final items = TravelScene.composeReview(
      scene: scene,
      learnedChars: _learnedChars(context),
      rng: Random(),
      now: _now(),
      stats: context.read<WordProgressRepository>().stats,
      excludeProgressIds: excludeProgressIds,
    );
    if (items.isEmpty) return;
    final nextExclude = DailyBridge.nextExclude(
      previous: excludeProgressIds,
      transfer: items,
    );
    final route = ListeningScreen.route(
      items,
      AppStrings.travelSceneListenTitle(_label),
      clock: clock,
      alreadyTransferredIds: excludeProgressIds,
      onMore: () =>
          _startListen(context, replace: true, excludeProgressIds: nextExclude),
      onFinished: onFinished,
    );
    unawaited(
      replace
          ? Navigator.of(context).pushReplacement(route)
          : Navigator.of(context).push(route),
    );
  }
}

class _SceneCard extends StatelessWidget {
  const _SceneCard({
    required this.label,
    required this.purpose,
    this.onTap,
    super.key,
  });

  final String label;
  final String purpose;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Semantics(
          button: enabled,
          enabled: enabled,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          purpose,
                          style: const TextStyle(color: AppColors.inkMuted),
                        ),
                      ],
                    ),
                  ),
                  if (enabled)
                    const Icon(Icons.chevron_right, color: AppColors.inkMuted),
                ],
              ),
            ),
          ),
        ),
      ),
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
