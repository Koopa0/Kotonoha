// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/domain/models/shift_drill.dart';

/// Human-checked original swap-sentence drills. These are NOT Satori lines,
/// NOT the 黙読 / travel phrase pool, and never fetched from a source URL.
///
/// This slice holds one focus — い／な adjective modification — with two
/// drills so the learner can name today's stuck point without a Dart edit.
const List<ShiftDrill> kShiftDrills = <ShiftDrill>[
  ShiftDrill(
    id: 'i-adj-aoi-noun',
    focusId: 'adj-mod',
    focusTitle: 'い／な形容詞修飾',
    label: 'あおい + 名詞',
    change: ShiftChange.noun,
    base: ShiftSentence(
      kana: 'あおい そら',
      romaji: 'aoi sora',
      meaning: '藍色的天空',
      modifier: 'あおい',
      head: 'そら',
      relation: '「あおい」修飾「そら」——藍色的,是在說天空。',
    ),
    shift: ShiftSentence(
      kana: 'あおい うみ',
      romaji: 'aoi umi',
      meaning: '藍色的海',
      modifier: 'あおい',
      head: 'うみ',
      relation: '「あおい」修飾「うみ」——藍色的,是在說海。',
    ),
  ),
  ShiftDrill(
    id: 'na-adj-shizuka-noun',
    focusId: 'adj-mod',
    focusTitle: 'い／な形容詞修飾',
    label: 'しずかな + 名詞',
    change: ShiftChange.noun,
    base: ShiftSentence(
      kana: 'しずかな へや',
      romaji: 'shizuka na heya',
      meaning: '安靜的房間',
      modifier: 'しずかな',
      head: 'へや',
      relation: '「しずかな」修飾「へや」——安靜的,是在說房間。',
    ),
    shift: ShiftSentence(
      kana: 'しずかな まち',
      romaji: 'shizuka na machi',
      meaning: '安靜的街',
      modifier: 'しずかな',
      head: 'まち',
      relation: '「しずかな」修飾「まち」——安靜的,是在說街。',
    ),
  ),
];
