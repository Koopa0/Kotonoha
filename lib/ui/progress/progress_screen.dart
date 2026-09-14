// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/data/repositories/kana_progress_repository.dart';
import 'package:kotonoha/data/repositories/progress_snapshot_restore_repository.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/progress_snapshot_exporter.dart';
import 'package:kotonoha/data/services/progress_snapshot_restorer.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';
import 'package:kotonoha/domain/use_cases/self_portrait.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/progress_ring.dart';
import 'package:provider/provider.dart';

/// 歩み — the one quiet 回望 (look-back). It is a MAP, not a scoreboard: how far
/// you've walked the syllabary (coverage), the present-tense state of each kana
/// (which can rise or fall, and tells you where to look), and the occasional
/// hard-gated observation. No accuracy %, no reaction-time number, no tally —
/// those are private inputs to the silent scheduler, never shown.
class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const ProgressScreen());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.progress)),
      body: SafeArea(
        child: Consumer<KanaProgressRepository>(
          builder: (context, store, _) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              children: [
                const SizedBox(height: 8),
                // Coverage of the whole syllabary — a map of how far you've come,
                // never a grade. It can only grow by the honest act of meeting a
                // kana, and it cannot be "lost".
                Center(
                  child: ProgressRing(
                    value: store.totalCount == 0
                        ? 0
                        : store.seenCount / store.totalCount,
                    centerLabel: '${store.seenCount}/${store.totalCount}',
                    caption: AppStrings.practiced,
                    title: AppStrings.practicedAllKanaScope,
                    footnote: AppStrings.practicedAllKanaHint,
                  ),
                ),
                const SizedBox(height: 28),
                _StatusBreakdown(store: store),
                const _Observations(),
                const _ProgressBackup(),
                const _ProgressRestore(),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The hard-gated notebook observation(s), read from the analytics stream — the
/// teaching signal that used to live in 自画像. Says nothing rather than something
/// flimsy, so an empty result simply shows nothing.
class _Observations extends StatelessWidget {
  const _Observations();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Attempt>>(
      future: context.read<AnalyticsLog>().all(),
      builder: (context, snapshot) {
        final observations = snapshot.hasData
            ? SelfPortrait.observe(snapshot.data!)
            : const <Observation>[];
        if (observations.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            children: [
              for (final o in observations) _ObservationCard(observation: o),
            ],
          ),
        );
      },
    );
  }
}

/// A quiet line, written like a notebook margin note — being seen, not scored.
class _ObservationCard extends StatelessWidget {
  const _ObservationCard({required this.observation});

  final Observation observation;

  @override
  Widget build(BuildContext context) {
    final text = switch (observation) {
      ConfusionObservation(:final target, :final mistakenFor) =>
        AppStrings.confusionLine(target, mistakenFor),
    };
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.spa_outlined, size: 18, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 15,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBreakdown extends StatelessWidget {
  const _StatusBreakdown({required this.store});

  final KanaProgressRepository store;

  @override
  Widget build(BuildContext context) {
    const items = [
      (KanaStatus.strong, AppStrings.statusStrong),
      (KanaStatus.learning, AppStrings.statusLearning),
      (KanaStatus.weak, AppStrings.statusWeak),
      (KanaStatus.unseen, AppStrings.statusNew),
    ];
    return Column(
      children: [
        for (final (status, label) in items) ...[
          _StatusRow(
            label: label,
            count: store.countWithStatus(status),
            color: AppColors.forStatus(status),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '$count',
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Quiet file-save entrance. Says exactly which five bodies leave the
/// device, and refuses to dress unresolved recovery as a complete backup.
class _ProgressBackup extends StatefulWidget {
  const _ProgressBackup();

  @override
  State<_ProgressBackup> createState() => _ProgressBackupState();
}

class _ProgressBackupState extends State<_ProgressBackup> {
  bool _saving = false;
  SnapshotExportStatus? _status;

  Future<void> _export() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _status = null;
    });
    final result = await context.read<ProgressSnapshotExporter>().export();
    if (!mounted) return;
    setState(() {
      _saving = false;
      _status = result.status == SnapshotExportStatus.cancelled
          ? null
          : result.status;
    });
  }

  @override
  Widget build(BuildContext context) {
    final exporter = context.read<ProgressSnapshotExporter>();
    final blocked = exporter.isBlocked;
    final status = blocked ? SnapshotExportStatus.blocked : _status;
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              AppStrings.backupTitle,
              style: TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              AppStrings.backupScope,
              style: TextStyle(
                color: AppColors.inkMuted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              AppStrings.backupNotIncluded,
              style: TextStyle(
                color: AppColors.inkMuted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: blocked || _saving ? null : _export,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  side: const BorderSide(color: AppColors.hairline),
                  foregroundColor: AppColors.ink,
                  disabledForegroundColor: AppColors.inkMuted,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  _saving ? AppStrings.backupSaving : AppStrings.backupAction,
                ),
              ),
            ),
            if (status != null) ...[
              const SizedBox(height: 10),
              Text(
                _copyFor(status),
                style: const TextStyle(
                  color: AppColors.inkMuted,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _copyFor(SnapshotExportStatus status) => switch (status) {
    SnapshotExportStatus.saved => AppStrings.backupSaved,
    SnapshotExportStatus.blocked => AppStrings.backupBlocked,
    SnapshotExportStatus.failed => AppStrings.backupFailed,
    SnapshotExportStatus.unimportable => AppStrings.backupUnimportable,
    SnapshotExportStatus.cancelled => '',
  };
}

/// Pick → preview → explicit confirm → transactional replace of the five
/// portable bodies. Invalid or cancelled picks never touch stores.
class _ProgressRestore extends StatefulWidget {
  const _ProgressRestore();

  @override
  State<_ProgressRestore> createState() => _ProgressRestoreState();
}

class _ProgressRestoreState extends State<_ProgressRestore> {
  bool _restoring = false;
  SnapshotRestoreStatus? _status;

  Future<bool> _confirm(ProgressRestorePreview preview) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.restoreConfirmTitle),
        content: Text(AppStrings.restorePreviewBody(preview.snapshot.createdAtUtc)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(AppStrings.restoreConfirmNo),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(AppStrings.restoreConfirmYes),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _restore() async {
    if (_restoring) return;
    setState(() {
      _restoring = true;
      _status = null;
    });
    final result = await context.read<ProgressSnapshotRestorer>().restore(
      confirm: _confirm,
    );
    if (!mounted) return;
    setState(() {
      _restoring = false;
      _status = result.status == SnapshotRestoreStatus.cancelled
          ? null
          : result.status;
    });
  }

  @override
  Widget build(BuildContext context) {
    final restorer = context.read<ProgressSnapshotRestorer>();
    final blocked = restorer.isBlocked;
    final status = blocked ? SnapshotRestoreStatus.blocked : _status;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              AppStrings.restoreTitle,
              style: TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              AppStrings.restoreScope,
              style: TextStyle(
                color: AppColors.inkMuted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              AppStrings.restoreNotIncluded,
              style: TextStyle(
                color: AppColors.inkMuted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: blocked || _restoring ? null : _restore,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  side: const BorderSide(color: AppColors.hairline),
                  foregroundColor: AppColors.ink,
                  disabledForegroundColor: AppColors.inkMuted,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  _restoring ? AppStrings.restoreRestoring : AppStrings.restoreAction,
                ),
              ),
            ),
            if (status != null) ...[
              const SizedBox(height: 10),
              Text(
                _copyFor(status),
                style: const TextStyle(
                  color: AppColors.inkMuted,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _copyFor(SnapshotRestoreStatus status) => switch (status) {
    SnapshotRestoreStatus.restored => AppStrings.restoreRestored,
    SnapshotRestoreStatus.invalid => AppStrings.restoreInvalid,
    SnapshotRestoreStatus.failed => AppStrings.restoreFailed,
    SnapshotRestoreStatus.blocked => AppStrings.restoreBlocked,
    SnapshotRestoreStatus.cancelled => '',
  };
}
