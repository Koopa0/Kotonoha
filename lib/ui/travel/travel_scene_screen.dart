// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/domain/data/info_drill_dataset.dart';
import 'package:kotonoha/domain/models/reply_drill.dart';
import 'package:kotonoha/domain/use_cases/daily_bridge.dart';
import 'package:kotonoha/domain/use_cases/travel_scene.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/ferry/ferry_screen.dart';
import 'package:kotonoha/ui/info/info_hub_screen.dart';
import 'package:kotonoha/ui/lessons/lessons_screen.dart';
import 'package:kotonoha/ui/listening/listening_screen.dart';
import 'package:kotonoha/ui/reading/reading_screen.dart';
import 'package:kotonoha/ui/reply/reply_hub_screen.dart';
import 'package:kotonoha/ui/travel/travel_scene_hub_viewmodel.dart';
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
///
/// A thin View over [TravelSceneHubViewModel]: it renders the doors and
/// navigates. Which doors are open and how each session behind them is
/// composed are the ViewModel's. The static starters let Home open the
/// same sessions without this hub on the stack.
class TravelSceneHub extends StatefulWidget {
  const TravelSceneHub({required this.scene, this.clock, super.key});

  final TravelSceneId scene;

  /// Injectable so もう一回 is not night-suppressed in route tests.
  final DateTime Function()? clock;

  static Route<void> route(TravelSceneId scene, {DateTime Function()? clock}) =>
      MaterialPageRoute<void>(
        builder: (_) => TravelSceneHub(scene: scene, clock: clock),
        settings: RouteSettings(name: 'travel-scene-${scene.name}'),
      );

  static void startMeet(
    BuildContext context, {
    required TravelSceneId scene,
    DateTime Function()? clock,
    bool replace = false,
    Set<String> excludeProgressIds = const {},
    VoidCallback? onFinished,
  }) => _startMeet(
    context,
    scene: scene,
    clock: clock,
    replace: replace,
    excludeProgressIds: excludeProgressIds,
    onFinished: onFinished,
  );

  static void startRecall(
    BuildContext context, {
    required TravelSceneId scene,
    DateTime Function()? clock,
    bool replace = false,
    Set<String> excludeProgressIds = const {},
    VoidCallback? onFinished,
  }) => _startRecall(
    context,
    scene: scene,
    clock: clock,
    replace: replace,
    excludeProgressIds: excludeProgressIds,
    onFinished: onFinished,
  );

  static void startListen(
    BuildContext context, {
    required TravelSceneId scene,
    DateTime Function()? clock,
    bool replace = false,
    Set<String> excludeProgressIds = const {},
    VoidCallback? onFinished,
  }) => _startListen(
    context,
    scene: scene,
    clock: clock,
    replace: replace,
    excludeProgressIds: excludeProgressIds,
    onFinished: onFinished,
  );

  @override
  State<TravelSceneHub> createState() => _TravelSceneHubState();
}

class _TravelSceneHubState extends State<TravelSceneHub> {
  late final TravelSceneHubViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = TravelSceneHubViewModel(
      scene: widget.scene,
      kana: context.read<KanaProgressRepository>(),
      words: context.read<WordProgressRepository>(),
      clock: widget.clock,
    );
  }

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  TravelSceneId get _scene => widget.scene;

  ReplySceneId? get _replyScene => switch (_scene) {
    TravelSceneId.transport => ReplySceneId.station,
    TravelSceneId.clothing => ReplySceneId.clothing,
    TravelSceneId.restaurant => ReplySceneId.restaurant,
    TravelSceneId.convenience => ReplySceneId.convenience,
    TravelSceneId.shrine ||
    TravelSceneId.parkQueue ||
    TravelSceneId.hotel => null,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_sceneLabel(_scene))),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _vm,
          builder: (context, _) => _doors(_vm.view),
        ),
      ),
    );
  }

  Widget _doors(TravelSceneView view) {
    final clock = widget.clock;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        Text(
          _scenePurpose(_scene),
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
              style: const TextStyle(color: AppColors.inkMuted, height: 1.5),
            ),
          ],
        ],
        const SizedBox(height: 24),
        if (view.needsKanaFirst || view.unreadable.isNotEmpty)
          _ActionButton(
            key: const ValueKey<String>('travel-learn-kana'),
            label: AppStrings.travelSceneLearnAction,
            productName: AppStrings.continueLearning,
            onPressed: () => Navigator.of(context).push(LessonsScreen.route()),
          ),
        if (view.canMeet) ...[
          if (view.needsKanaFirst || view.unreadable.isNotEmpty)
            const SizedBox(height: 12),
          _ActionButton(
            key: const ValueKey<String>('travel-meet'),
            label: AppStrings.travelSceneMeetAction,
            productName: AppStrings.ferryEntry,
            onPressed: () => _startMeet(context, scene: _scene, clock: clock),
          ),
        ],
        if (view.canRecall) ...[
          const SizedBox(height: 12),
          _ActionButton(
            key: const ValueKey<String>('travel-recall'),
            label: AppStrings.travelSceneRecallAction,
            productName: AppStrings.sentenceEntry,
            kind: _ActionKind.outlined,
            onPressed: () => _startRecall(context, scene: _scene, clock: clock),
          ),
        ],
        if (view.canListen) ...[
          const SizedBox(height: 12),
          _ActionButton(
            key: const ValueKey<String>('travel-listen'),
            label: AppStrings.travelSceneListenAction,
            productName: AppStrings.listeningEntry,
            kind: _ActionKind.outlined,
            onPressed: () => _startListen(context, scene: _scene, clock: clock),
          ),
        ],
        if (_scene == TravelSceneId.hotel) ...[
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
            onPressed: () => Navigator.of(context)
                .push(ReplyHubScreen.route(scene: _replyScene!, clock: clock)),
          ),
        ],
        if (_scene == TravelSceneId.shrine) ...[
          const SizedBox(height: 12),
          _ActionButton(
            key: const ValueKey<String>('travel-reply-shrine'),
            label: AppStrings.replyAction,
            productName: AppStrings.replyEntry,
            kind: _ActionKind.outlined,
            onPressed: () => Navigator.of(context).push(
              ReplyHubScreen.route(scene: ReplySceneId.shrine, clock: clock),
            ),
          ),
        ],
        if (_scene == TravelSceneId.parkQueue) ...[
          const SizedBox(height: 12),
          _ActionButton(
            key: const ValueKey<String>('travel-reply-park'),
            label: AppStrings.replyAction,
            productName: AppStrings.replyEntry,
            kind: _ActionKind.outlined,
            onPressed: () => Navigator.of(context).push(
              ReplyHubScreen.route(scene: ReplySceneId.parkQueue, clock: clock),
            ),
          ),
          const SizedBox(height: 12),
          _ActionButton(
            key: const ValueKey<String>('travel-reply-help'),
            label: AppStrings.replyHelpAction,
            productName: AppStrings.replyHelpEntry,
            kind: _ActionKind.outlined,
            onPressed: () => Navigator.of(context).push(
              ReplyHubScreen.route(scene: ReplySceneId.help, clock: clock),
            ),
          ),
        ],
      ],
    );
  }
}

String _sceneLabel(TravelSceneId scene) => switch (scene) {
  TravelSceneId.transport => AppStrings.travelSceneTransport,
  TravelSceneId.clothing => AppStrings.travelSceneClothing,
  TravelSceneId.shrine => AppStrings.travelSceneShrine,
  TravelSceneId.parkQueue => AppStrings.travelSceneParkQueue,
  TravelSceneId.restaurant => AppStrings.travelSceneRestaurant,
  TravelSceneId.convenience => AppStrings.travelSceneConvenience,
  TravelSceneId.hotel => AppStrings.travelSceneHotel,
};

String _scenePurpose(TravelSceneId scene) => switch (scene) {
  TravelSceneId.transport => AppStrings.travelScenePurposeTransport,
  TravelSceneId.clothing => AppStrings.travelScenePurposeClothing,
  TravelSceneId.shrine => AppStrings.travelScenePurposeShrine,
  TravelSceneId.parkQueue => AppStrings.travelScenePurposeParkQueue,
  TravelSceneId.restaurant => AppStrings.travelScenePurposeRestaurant,
  TravelSceneId.convenience => AppStrings.travelScenePurposeConvenience,
  TravelSceneId.hotel => AppStrings.travelScenePurposeHotel,
};

/// A one-shot composer for a session started outside the hub (Home) or
/// from a 「もう一回」 closure: reads the owners once, composes, and leaves no
/// listener behind.
TravelSceneHubViewModel _composerFor(
  BuildContext context,
  TravelSceneId scene,
  DateTime Function()? clock,
) => TravelSceneHubViewModel(
  scene: scene,
  kana: context.read<KanaProgressRepository>(),
  words: context.read<WordProgressRepository>(),
  clock: clock,
);

void _push(BuildContext context, Route<void> route, {required bool replace}) {
  unawaited(
    replace
        ? Navigator.of(context).pushReplacement(route)
        : Navigator.of(context).push(route),
  );
}

void _startMeet(
  BuildContext context, {
  required TravelSceneId scene,
  DateTime Function()? clock,
  bool replace = false,
  Set<String> excludeProgressIds = const {},
  VoidCallback? onFinished,
}) {
  final composer = _composerFor(context, scene, clock);
  final words = composer.composeIntroWords(
    excludeProgressIds: excludeProgressIds,
  );
  if (words.isNotEmpty) {
    composer.dispose();
    final nextExclude = DailyBridge.nextExclude(
      previous: excludeProgressIds,
      transfer: words,
    );
    _push(
      context,
      FerryScreen.route(
        words,
        AppStrings.travelSceneMeetTitle(_sceneLabel(scene)),
        clock: clock,
        onMore: () => _continueOrFinishMeet(
          context,
          scene: scene,
          clock: clock,
          excludeProgressIds: nextExclude,
        ),
        onFinished: onFinished,
      ),
      replace: replace,
    );
    return;
  }
  final phrases = composer.composeIntroPhrases(
    excludeProgressIds: excludeProgressIds,
  );
  composer.dispose();
  if (phrases.isNotEmpty) {
    final nextExclude = DailyBridge.nextExclude(
      previous: excludeProgressIds,
      transfer: phrases,
    );
    _push(
      context,
      ReadingScreen.route(
        phrases,
        AppStrings.travelSceneMeetTitle(_sceneLabel(scene)),
        clock: clock,
        alreadyTransferredIds: excludeProgressIds,
        onMore: () => _continueOrFinishMeet(
          context,
          scene: scene,
          clock: clock,
          excludeProgressIds: nextExclude,
        ),
        onFinished: onFinished,
      ),
      replace: replace,
    );
    return;
  }
  if (replace) Navigator.of(context).pop();
}

/// Leftover unread scene items continue 先見面. An empty pool pops back
/// to the hub so もう一回 is never a dead control, and never pads or
/// re-introduces to climb mastery.
void _continueOrFinishMeet(
  BuildContext context, {
  required TravelSceneId scene,
  required DateTime Function()? clock,
  required Set<String> excludeProgressIds,
}) {
  final composer = _composerFor(context, scene, clock);
  final more = composer.hasMoreIntro(excludeProgressIds: excludeProgressIds);
  composer.dispose();
  if (more) {
    _startMeet(
      context,
      scene: scene,
      clock: clock,
      replace: true,
      excludeProgressIds: excludeProgressIds,
    );
    return;
  }
  Navigator.of(context).pop();
}

void _startRecall(
  BuildContext context, {
  required TravelSceneId scene,
  DateTime Function()? clock,
  bool replace = false,
  Set<String> excludeProgressIds = const {},
  VoidCallback? onFinished,
}) {
  final composer = _composerFor(context, scene, clock);
  final items = composer.composeReview(excludeProgressIds: excludeProgressIds);
  composer.dispose();
  if (items.isEmpty) return;
  final nextExclude = DailyBridge.nextExclude(
    previous: excludeProgressIds,
    transfer: items,
  );
  _push(
    context,
    ReadingScreen.route(
      items,
      AppStrings.travelSceneRecallTitle(_sceneLabel(scene)),
      clock: clock,
      alreadyTransferredIds: excludeProgressIds,
      onMore: () => _startRecall(
        context,
        scene: scene,
        clock: clock,
        replace: true,
        excludeProgressIds: nextExclude,
      ),
      onFinished: onFinished,
    ),
    replace: replace,
  );
}

void _startListen(
  BuildContext context, {
  required TravelSceneId scene,
  DateTime Function()? clock,
  bool replace = false,
  Set<String> excludeProgressIds = const {},
  VoidCallback? onFinished,
}) {
  final composer = _composerFor(context, scene, clock);
  final items = composer.composeReview(excludeProgressIds: excludeProgressIds);
  composer.dispose();
  if (items.isEmpty) return;
  final nextExclude = DailyBridge.nextExclude(
    previous: excludeProgressIds,
    transfer: items,
  );
  _push(
    context,
    ListeningScreen.route(
      items,
      AppStrings.travelSceneListenTitle(_sceneLabel(scene)),
      clock: clock,
      alreadyTransferredIds: excludeProgressIds,
      onMore: () => _startListen(
        context,
        scene: scene,
        clock: clock,
        replace: true,
        excludeProgressIds: nextExclude,
      ),
      onFinished: onFinished,
    ),
    replace: replace,
  );
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
