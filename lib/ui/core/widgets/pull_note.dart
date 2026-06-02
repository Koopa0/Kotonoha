// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';

/// A pull-not-push note: a muted [trigger] that folds one quiet [child] panel
/// open or closed (AnimatedSize), with ephemeral state and no persistence — the
/// calm "tap to learn more" gesture shared by ④「これは?」, the 同形異義語 note, and
/// the 助詞 gloss. Never auto-shown, never modal; the single trigger is also the
/// dismiss, so there is never a second or dead control.
class PullNote extends StatefulWidget {
  const PullNote({required this.trigger, required this.child, super.key});

  final String trigger;

  /// The revealed panel — shown only while open.
  final Widget child;

  @override
  State<PullNote> createState() => _PullNoteState();
}

class _PullNoteState extends State<PullNote> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: AppColors.inkMuted),
          onPressed: () => setState(() => _open = !_open),
          child: Text(widget.trigger),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: _open ? widget.child : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
