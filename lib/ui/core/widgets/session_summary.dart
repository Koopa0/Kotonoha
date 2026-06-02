// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/domain/models/koten.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/pull_note.dart';
import 'package:kotonoha/ui/core/widgets/speak_button.dart';

/// 凪 — the calm close of a practice session. Not a results table: a komorebi
/// glow that gently settles in, one quiet [note] (a fact about today, never a
/// count), and only then — quietly — the score. Light as the only "reward".
/// Shared by every self-graded screen.
///
/// Deliberate decision (not an oversight): when a [note] is present the score is
/// kept as a small, muted footnote rather than removed. It's honest feedback,
/// never the reward — the closing FACT (the note) leads; the count never does.
class SessionSummary extends StatelessWidget {
  const SessionSummary({
    required this.headline,
    required this.onDone,
    this.note,
    this.share,
    this.onMore,
    super.key,
  });

  /// e.g. 「讀對 8 / 10」.
  final String headline;

  /// A quiet fact about today (「今天,和『あき』更熟了一點。」). When present it
  /// leads, and the score recedes to a muted footnote — the breath-out.
  final String? note;

  /// An optional classical PD line that deepens the close into 余韻 (see
  /// [KotenLine] / [KotenShare]). When present it leads instead of [note] — the
  /// line is READ first, its gloss is the echo. Null on most closes by design.
  final KotenLine? share;

  final VoidCallback onDone;

  /// Opt-in "one more" — composes a fresh short session. Null = hidden. Rendered
  /// as a muted button below 完成, never the default; the home suppresses it at
  /// night (the close is there to grant permission to stop).
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final hasNote = note != null;
    final hasShare = share != null;
    // When a note or a classical 余韻 leads, the score recedes to a footnote.
    final quiet = hasNote || hasShare;
    // Centre when it fits; scroll when it doesn't — a long classical 余韻 with the
    // 釋 unfolded can exceed a short screen, and the close must never overflow.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The light settles in — a slow breath out.
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 1100),
                    curve: Curves.easeOut,
                    builder: (context, v, child) =>
                        Opacity(opacity: v, child: child),
                    child: Container(
                      width: 104,
                      height: 104,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            AppColors.komorebi.withValues(alpha: 0.30),
                            AppColors.komorebi.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // A classical 余韻 leads when present; else the quiet fact; else
                  // nothing (the close line below fills in).
                  if (hasShare)
                    _KotenShareView(share!)
                  else if (hasNote)
                    Text(
                      note!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 19,
                        height: 1.5,
                        color: AppColors.ink,
                      ),
                    ),
                  const SizedBox(height: 12),
                  // The score: prominent on its own, a quiet footnote under a lead.
                  Text(
                    headline,
                    style: TextStyle(
                      fontSize: quiet ? 14 : 22,
                      fontWeight: quiet ? FontWeight.w500 : FontWeight.w700,
                      color: quiet ? AppColors.inkMuted : AppColors.ink,
                    ),
                  ),
                  if (!quiet) ...[
                    const SizedBox(height: 8),
                    const Text(
                      AppStrings.sessionCloseLine,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.inkMuted, fontSize: 14),
                    ),
                  ],
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: onDone,
                      child: const Text(AppStrings.done),
                    ),
                  ),
                  if (onMore != null) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: onMore,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.inkMuted,
                      ),
                      child: const Text(AppStrings.practiceAgain),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The three-part 余韻 block: the classical line READ (large, with a hiragana
/// reading row + TTS), then its 繁中 echo, then a muted attribution. Reading
/// first, meaning as echo.
class _KotenShareView extends StatelessWidget {
  const _KotenShareView(this.line);

  final KotenLine line;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          line.text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 24,
            height: 1.55,
            fontWeight: FontWeight.w500,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          line.reading,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, color: AppColors.inkMuted),
        ),
        SpeakButton(text: line.reading),
        const SizedBox(height: 4),
        Text(
          line.gloss,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            height: 1.6,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          line.attribution,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
        ),
        // Opt-in 「釋」 — a deeper background note, folded away until tapped. The
        // close stays one calm line for anyone who doesn't reach for it.
        if (line.note case final note?)
          PullNote(
            trigger: AppStrings.kotenNoteTrigger,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                note,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.7,
                  color: AppColors.inkMuted,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
