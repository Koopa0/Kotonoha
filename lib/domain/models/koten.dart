// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/domain/models/season.dart';

/// A single classical, PUBLIC-DOMAIN Japanese line — a haiku, a waka, an いろは
/// fragment, a 茶道 phrase — surfaced *occasionally* as the 余韻 at a session's 凪
/// close. It is shown the way 名残の仮名 shows things: the [text] is READ (large,
/// with the [reading] as furigana and TTS), and the 繁中 [gloss] is the echo that
/// comes AFTER the reading, never the headline.
///
/// Invariants that keep this from drifting into a culture blog / a forbidden
/// collectible (see CLAUDE.md retention-ruler + feature-honesty):
/// - [attribution] is REQUIRED — every line names its source (the honesty gate).
///   Public-domain-ness is guaranteed by CURATION (all authors died before 1928)
///   + the verification record; it is NOT spelled out to the reader, since a
///   「公有領域」 label would read as clinical at a calm close.
/// - [gloss] is ONE line of resonance — never a paragraph, never a grammar lesson.
///
/// Pure data: no `package:flutter/*` imports.
class KotenLine {
  const KotenLine({
    required this.text,
    required this.reading,
    required this.gloss,
    required this.attribution,
    this.note,
    this.season,
  });

  /// The line as written (kanji + kana), shown large — the thing to read.
  final String text;

  /// The full hiragana reading — shown as a reading row beneath the line and what
  /// TTS speaks, so a kanji-literate reader meets the SOUND, not just the meaning.
  final String reading;

  /// ONE line of Traditional-Chinese 余韻 (the felt image / season). Never more.
  final String gloss;

  /// 作者・出處 on one muted line (e.g. 「松尾芭蕉『おくのほそ道』」). Required — every
  /// line is sourced (the honesty gate). The PD status is not surfaced here.
  final String attribution;

  /// An OPT-IN deeper note (繁中) — background / 季語 / 詩境 — revealed only behind a
  /// 「釋」 fold (see [PullNote]). Null = no fold; the close stays one calm line.
  /// Unlike [gloss] this MAY run a few sentences (it is reached only on purpose),
  /// but it is still our own prose, never a lifted modern annotation.
  final String? note;

  /// The 季語 season, or null for a season-neutral line (いろは, 一期一会). Lets an
  /// in-season line float toward the close, the way the reading corpus turns.
  final Season? season;
}
