// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/word_progress_repository.dart';
import 'package:kotonoha/domain/models/reply_drill.dart';
import 'package:kotonoha/domain/use_cases/reply_session.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/ferry/ferry_screen.dart';
import 'package:kotonoha/ui/lessons/lessons_screen.dart';
import 'package:kotonoha/ui/reading/reading_screen.dart';
import 'package:kotonoha/ui/reply/reply_hub_viewmodel.dart';
import 'package:kotonoha/ui/reply/reply_screen.dart';
import 'package:provider/provider.dart';

/// Learn-then-practice door for station or clothing replies. Isolated from #47
/// [TravelScene] membership and #48 換句.
///
/// A thin View over [ReplyHubViewModel]: it renders the doors and navigates.
/// Which doors are open and how each session behind them is composed are
/// the ViewModel's.
class ReplyHubScreen extends StatefulWidget {
  const ReplyHubScreen({
    this.scene = ReplySceneId.station,
    this.clock,
    super.key,
  });

  final ReplySceneId scene;
  final DateTime Function()? clock;

  static Route<void> route({
    ReplySceneId scene = ReplySceneId.station,
    DateTime Function()? clock,
  }) => MaterialPageRoute<void>(
    builder: (_) => ReplyHubScreen(scene: scene, clock: clock),
    settings: RouteSettings(name: 'reply-hub-${scene.name}'),
  );

  @override
  State<ReplyHubScreen> createState() => _ReplyHubScreenState();
}

class _ReplyHubScreenState extends State<ReplyHubScreen> {
  late final ReplyHubViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = ReplyHubViewModel(
      scene: widget.scene,
      kana: context.read<KanaProgressRepository>(),
      words: context.read<WordProgressRepository>(),
    );
  }

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  String get _purpose => switch (widget.scene) {
    ReplySceneId.station => AppStrings.replyPurpose,
    ReplySceneId.clothing => AppStrings.replyClothingPurpose,
    ReplySceneId.restaurant => AppStrings.replyRestaurantPurpose,
    ReplySceneId.convenience => AppStrings.replyConveniencePurpose,
    ReplySceneId.shrine => AppStrings.replyShrinePurpose,
    ReplySceneId.parkQueue => AppStrings.replyParkPurpose,
    ReplySceneId.help => AppStrings.replyHelpPurpose,
  };

  String get _meetHint => switch (widget.scene) {
    ReplySceneId.station => AppStrings.replyMeetHint,
    ReplySceneId.clothing => AppStrings.replyClothingMeetHint,
    ReplySceneId.restaurant => AppStrings.replyRestaurantMeetHint,
    ReplySceneId.convenience => AppStrings.replyConvenienceMeetHint,
    ReplySceneId.shrine => AppStrings.replyShrineMeetHint,
    ReplySceneId.parkQueue => AppStrings.replyParkMeetHint,
    ReplySceneId.help => AppStrings.replyHelpMeetHint,
  };

  String get _meetTitle => switch (widget.scene) {
    ReplySceneId.station => AppStrings.replyMeetTitle,
    ReplySceneId.clothing => AppStrings.replyClothingMeetTitle,
    ReplySceneId.restaurant => AppStrings.replyRestaurantMeetTitle,
    ReplySceneId.convenience => AppStrings.replyConvenienceMeetTitle,
    ReplySceneId.shrine => AppStrings.replyShrineMeetTitle,
    ReplySceneId.parkQueue => AppStrings.replyParkMeetTitle,
    ReplySceneId.help => AppStrings.replyHelpMeetTitle,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.replyTitle)),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _vm,
          builder: (context, _) => _doors(_vm.view),
        ),
      ),
    );
  }

  Widget _doors(ReplySessionView view) {
    return ListView(
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
              AppStrings.replyMissingKana(view.missingUnits.take(8).join(' ')),
              style: const TextStyle(color: AppColors.inkMuted, height: 1.5),
            ),
          ],
        ],
        const SizedBox(height: 24),
        if (view.needsKanaFirst || view.missingUnits.isNotEmpty)
          _ActionButton(
            key: const ValueKey<String>('reply-learn-kana'),
            label: AppStrings.travelSceneLearnAction,
            productName: AppStrings.continueLearning,
            onPressed: () => Navigator.of(context).push(LessonsScreen.route()),
          ),
        if (view.canMeet) ...[
          if (view.needsKanaFirst || view.missingUnits.isNotEmpty)
            const SizedBox(height: 12),
          _ActionButton(
            key: const ValueKey<String>('reply-meet'),
            label: AppStrings.travelSceneMeetAction,
            productName: AppStrings.ferryEntry,
            onPressed: _startMeet,
          ),
        ],
        if (view.canPractice) ...[
          const SizedBox(height: 12),
          _ActionButton(
            key: const ValueKey<String>('reply-start'),
            label: AppStrings.replyStartAction,
            productName: AppStrings.replyEntry,
            kind: _ActionKind.outlined,
            onPressed: _startPractice,
          ),
        ],
      ],
    );
  }

  void _startMeet({bool replace = false}) {
    final words = _vm.composeIntroWords();
    if (words.isNotEmpty) {
      final route = FerryScreen.route(
        words,
        _meetTitle,
        clock: widget.clock,
        onMore: _continueMeet,
      );
      unawaited(
        replace
            ? Navigator.of(context).pushReplacement(route)
            : Navigator.of(context).push(route),
      );
      return;
    }
    final phrases = _vm.composeIntroPhrases();
    if (phrases.isNotEmpty) {
      final route = ReadingScreen.route(
        phrases,
        _meetTitle,
        clock: widget.clock,
        onMore: _continueMeet,
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

  void _continueMeet() {
    if (_vm.hasUnreadRequired) {
      _startMeet(replace: true);
      return;
    }
    Navigator.of(context).pop();
  }

  void _startPractice({bool replace = false}) {
    final drills = _vm.composePractice();
    if (drills.isEmpty) return;
    final route = ReplyScreen.route(
      drills,
      scene: widget.scene,
      clock: widget.clock,
      onMore: () => _startPractice(replace: true),
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
