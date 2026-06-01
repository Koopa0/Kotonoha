// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/use_cases/insights.dart';
import 'package:kotonoha/domain/use_cases/self_portrait.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:provider/provider.dart';

/// A quiet dashboard over the analytics event stream: totals, accuracy,
/// reaction time, and where practice has gone. Read-only.
class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const InsightsScreen());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.insightsTitle)),
      body: SafeArea(
        child: FutureBuilder<List<Attempt>>(
          future: context.read<AnalyticsLog>().all(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final s = Insights.summarize(snapshot.data!);
            if (s.total == 0) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    AppStrings.insightsEmpty,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.inkMuted, fontSize: 15),
                  ),
                ),
              );
            }
            final modes = s.perMode.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            final observations = SelfPortrait.observe(snapshot.data!);
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              children: [
                for (final o in observations) _ObservationCard(observation: o),
                _Stat(
                  label: AppStrings.insightsTotal,
                  value: AppStrings.insightsCount(s.total),
                ),
                _Stat(
                  label: AppStrings.insightsAccuracy,
                  value: '${(s.accuracy * 100).round()}%',
                ),
                _Stat(
                  label: AppStrings.insightsAvgRt,
                  value: s.avgRtMs == null
                      ? '—'
                      : AppStrings.insightsMs(s.avgRtMs!),
                ),
                _Stat(
                  label: AppStrings.insightsDistinct,
                  value: '${s.distinctItems}',
                ),
                const SizedBox(height: 20),
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    AppStrings.insightsByMode,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                for (final e in modes)
                  _Stat(
                    label: AppStrings.modeLabel(e.key),
                    value: AppStrings.insightsCount(e.value),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.inkMuted, fontSize: 15),
          ),
          Text(
            value,
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
      margin: const EdgeInsets.only(bottom: 16),
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
