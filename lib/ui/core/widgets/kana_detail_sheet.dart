// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/kana.dart';
import 'package:kotonoha/domain/models/kana_stat.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/speak_button.dart';
import 'package:provider/provider.dart';

/// A calm bottom sheet showing a single kana large, with its romaji, audio, and
/// a quiet present-tense STATUS (a state, never a grade). Opened from the Learn
/// grid. Per the retention ruler, no count / accuracy / score is ever shown here
/// — accuracy stays a private scheduler input.
class KanaDetailSheet extends StatefulWidget {
  const KanaDetailSheet({required this.kana, required this.stat, super.key});

  final Kana kana;
  final KanaStat stat;

  static Future<void> show(BuildContext context, Kana kana, KanaStat stat) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => KanaDetailSheet(kana: kana, stat: stat),
    );
  }

  @override
  State<KanaDetailSheet> createState() => _KanaDetailSheetState();
}

class _KanaDetailSheetState extends State<KanaDetailSheet> {
  late final SpeechService _speech;
  late final AppLifecycleListener _lifecycle;
  int? _ownedPlay;

  @override
  void initState() {
    super.initState();
    _speech = context.read<SpeechService>();
    _lifecycle = AppLifecycleListener(
      onInactive: _abandonOwnedPlayback,
      onHide: _abandonOwnedPlayback,
      onPause: _abandonOwnedPlayback,
      onDetach: _abandonOwnedPlayback,
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _abandonOwnedPlayback();
    super.dispose();
  }

  void _abandonOwnedPlayback() {
    final generation = _ownedPlay;
    _ownedPlay = null;
    if (generation != null) {
      unawaited(_speech.stop(generation: generation));
    }
  }

  void _speak() {
    unawaited(_speech.speak(widget.kana.character));
    _ownedPlay = _speech.generation;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.kana.character,
              style: const TextStyle(
                fontSize: 104,
                height: 1.0,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.kana.romaji,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: 8),
            SpeakButton(text: widget.kana.character, size: 32, onPlay: _speak),
            const SizedBox(height: 16),
            if (widget.stat.isSeen)
              _StatusLine(status: widget.stat.status)
            else
              const Text(
                AppStrings.notPracticedYet,
                style: TextStyle(color: AppColors.inkMuted),
              ),
          ],
        ),
      ),
    );
  }
}

/// A single calm line: a status dot + present-tense label (學習中 / 待加強 / 熟練).
/// A STATE, not a grade — no count, no accuracy. Mirrors 歩み's status language.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.status});

  final KanaStatus status;

  String get _label => switch (status) {
    KanaStatus.strong => AppStrings.statusStrong,
    KanaStatus.weak => AppStrings.statusWeak,
    KanaStatus.learning => AppStrings.statusLearning,
    KanaStatus.unseen => AppStrings.statusNew,
  };

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.forStatus(status),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _label,
          style: const TextStyle(fontSize: 14, color: AppColors.inkMuted),
        ),
      ],
    );
  }
}
