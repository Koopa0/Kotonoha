// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:provider/provider.dart';

/// Hosts the ONE calm, cross-route persistence surface above the app's
/// navigator (mounted in `MaterialApp.builder`, so it survives route changes
/// and only ever shows a single banner). It appears only when a progress write
/// failed — offering a retry — or when a store recovered at startup — an honest,
/// session-dismissible notice. Normal saving stays completely silent.
///
/// It also drains pending writes on a lifecycle hide/pause/detach — best-effort
/// only, never a promise the OS lets it finish before a kill.
class PersistenceBanner extends StatefulWidget {
  const PersistenceBanner({required this.child, super.key});

  final Widget child;

  @override
  State<PersistenceBanner> createState() => _PersistenceBannerState();
}

class _PersistenceBannerState extends State<PersistenceBanner> {
  late final ProgressPersistenceController _controller;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _controller = context.read<ProgressPersistenceController>();
    _lifecycle = AppLifecycleListener(
      onHide: _controller.drain,
      onPause: _controller.drain,
      onDetach: _controller.drain,
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ProgressPersistenceController>();
    final banner = _banner(controller);
    // No banner → the route keeps its own untouched safe area.
    if (banner == null) return widget.child;
    return Column(
      children: [
        banner,
        // The banner's SafeArea already consumed the top inset; strip it from
        // the route below so its own SafeArea / AppBar doesn't consume the same
        // status-bar padding a second time.
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: widget.child,
          ),
        ),
      ],
    );
  }

  Widget? _banner(ProgressPersistenceController controller) {
    // A live write failure outranks the informational recovery notice.
    if (controller.hasWriteFailure) {
      final retrying = controller.isRetrying;
      return _PersistenceSurface(
        message: AppStrings.persistFailedLine,
        detail: AppStrings.persistFailedDetail,
        actionLabel: retrying
            ? AppStrings.persistRetrying
            : AppStrings.persistRetry,
        // Disabled while a retry is in flight, so a second tap is visibly not a
        // live button rather than silently swallowed.
        onAction: retrying ? null : controller.retry,
      );
    }
    final copy = _recoveryCopy(controller.recoveryNotice);
    if (copy != null) {
      return _PersistenceSurface(
        message: copy,
        actionLabel: AppStrings.persistAck,
        onAction: controller.acknowledgeRecovery,
      );
    }
    return null;
  }

  /// One honest line per notice; null for [RecoveryNotice.none]. Kept here so
  /// [AppStrings] needs no dependency on the controller enum.
  String? _recoveryCopy(RecoveryNotice notice) => switch (notice) {
    RecoveryNotice.none => null,
    RecoveryNotice.salvaged => AppStrings.persistRecoverySalvaged,
    RecoveryNotice.restored => AppStrings.persistRecoveryRestored,
    RecoveryNotice.preservationPending =>
      AppStrings.persistRecoveryPreservationPending,
    RecoveryNotice.recoveryRequired =>
      AppStrings.persistRecoveryRecoveryRequired,
  };
}

/// The calm banner itself: a [MaterialBanner] on washi card with a hairline
/// divider and an ink text action (ink, not the 青磁 accent, so the action
/// clears 4.5:1 contrast on the near-white card). A live region so a screen
/// reader notices a fresh appearance; actions forced below so it never
/// overflows at a wide text scale on a narrow screen. A null [onAction] renders
/// the action disabled — but still readable — for the in-flight retry state.
class _PersistenceSurface extends StatelessWidget {
  const _PersistenceSurface({
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.detail,
  });

  final String message;
  final String? detail;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final detailText = detail;
    return Semantics(
      container: true,
      liveRegion: true,
      // A Material ancestor for the action's ink — the banner sits above the
      // navigator, where no route Scaffold provides one.
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          bottom: false,
          child: MaterialBanner(
            backgroundColor: AppColors.card,
            surfaceTintColor: AppColors.card,
            dividerColor: AppColors.hairline,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            forceActionsBelow: true,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message,
                  style: const TextStyle(color: AppColors.ink, height: 1.4),
                ),
                if (detailText != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    detailText,
                    style: const TextStyle(
                      color: AppColors.inkMuted,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.ink,
                  // The retrying/disabled label stays readable (≥4.5:1 on card).
                  disabledForegroundColor: AppColors.inkMuted,
                  minimumSize: const Size(48, 48),
                ),
                child: Text(actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
