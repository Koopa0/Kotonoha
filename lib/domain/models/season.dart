// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

/// The four seasons, for the silent seasonal-lift in reading sampling. A reading
/// tagged with the current season (or with no season at all) floats toward the
/// front of a session; off-season readings sink but are NEVER excluded — so the
/// year quietly turns in what you read (物の哀れ), and a winter learner still
/// occasionally meets a falling cherry (名残). Nothing is ever labelled.
///
/// A model (not a use_case): [ReadingItem] references it, so it must sit in the
/// layer models may import. Pure: no `package:flutter/*` imports.
enum Season {
  spring,
  summer,
  autumn,
  winter;

  /// The season of a calendar [month] (1–12): spring 3–5, summer 6–8,
  /// autumn 9–11, winter 12/1/2.
  static Season forMonth(int month) {
    return switch (month) {
      3 || 4 || 5 => Season.spring,
      6 || 7 || 8 => Season.summer,
      9 || 10 || 11 => Season.autumn,
      _ => Season.winter,
    };
  }
}
