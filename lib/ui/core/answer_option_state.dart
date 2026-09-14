// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

/// Visual state of an answer option once an answer has been committed.
enum OptionState {
  /// Not yet answered — tappable.
  idle,

  /// The option the user picked, and it was correct.
  correct,

  /// The option the user picked, and it was wrong.
  wrong,

  /// The correct answer, revealed after the user picked wrong.
  revealed,

  /// An untouched, now-disabled option after answering.
  dimmed,
}
