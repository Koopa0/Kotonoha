// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/domain/models/phrase.dart';
import 'package:kotonoha/domain/models/reading_item.dart';

/// Short readable phrases — the sentence layer. All hiragana, no yōon, layout
/// spaces at word boundaries. Original motif sentences flavoured to the
/// learner's interests (NOT copyrighted lyrics/lines); grammar follows the early
/// 《大家的日本語》 lessons (は/が/を/の/に particles).
///
/// Pure data: no `package:flutter/*` imports.
const List<Phrase> kPhrases = <Phrase>[
  Phrase(
    kana: 'そらが あおい',
    romaji: 'sora ga aoi',
    meaning: '天空是藍的',
    theme: ContentTheme.yorushika,
  ),
  Phrase(
    kana: 'なつの かぜ',
    romaji: 'natsu no kaze',
    meaning: '夏天的風',
    theme: ContentTheme.yorushika,
  ),
  Phrase(
    kana: 'うみが みえる',
    romaji: 'umi ga mieru',
    meaning: '看得見海',
    theme: ContentTheme.yorushika,
  ),
  Phrase(
    kana: 'きみの こえ',
    romaji: 'kimi no koe',
    meaning: '你的聲音',
    theme: ContentTheme.yorushika,
  ),
  Phrase(
    kana: 'きみが すき',
    romaji: 'kimi ga suki',
    meaning: '喜歡你',
    theme: ContentTheme.anime,
  ),
  Phrase(
    kana: 'みずを ください',
    romaji: 'mizu o kudasai',
    meaning: '請給我水',
    theme: ContentTheme.travel,
  ),
  Phrase(
    kana: 'えきは どこ',
    romaji: 'eki wa doko',
    meaning: '車站在哪裡',
    theme: ContentTheme.travel,
  ),
  Phrase(
    kana: 'たたかうか もどるか',
    romaji: 'tatakau ka modoru ka',
    meaning: '戰鬥還是返回',
    theme: ContentTheme.game,
  ),
];
