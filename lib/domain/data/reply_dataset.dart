// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/domain/models/reply_drill.dart';

/// First-slice station replies: hear a Kyoto-station ask, name the intent,
/// pick one short answer. Original staff / passer-by turns. Reuses shipped
/// T01 phrases or already-met station words; does not copy paid text and
/// does not join the 黙読 / [TravelScene] pools.
///
/// Pure data: no `package:flutter/*` imports.
const List<ReplyDrill> kReplyDrills = [
  ReplyDrill(
    id: 'reply:doko-e-iku',
    promptKana: 'どこへ いく',
    promptRomaji: 'doko e iku',
    promptMeaning: '要去哪裡',
    intentCorrect: '問你要去哪裡',
    intentWrong: ['問車站在哪裡', '問這裡是不是車站'],
    replyCorrectKana: 'きょうとです',
    replyCorrectRomaji: 'kyouto desu',
    replyCorrectMeaning: '我去京都',
    replyWrongKana: ['みぎです', 'はい'],
    requiredSeenIds: ['phrase:どこへ いく'],
  ),
  ReplyDrill(
    id: 'reply:eki-wa-doko',
    promptKana: 'えきは どこ',
    promptRomaji: 'eki wa doko',
    promptMeaning: '車站在哪裡',
    intentCorrect: '問車站在哪裡',
    intentWrong: ['問你要去哪裡', '問這裡是不是車站'],
    replyCorrectKana: 'みぎです',
    replyCorrectRomaji: 'migi desu',
    replyCorrectMeaning: '在右邊',
    replyWrongKana: ['ここです', 'はい'],
    requiredSeenIds: ['phrase:えきは どこ'],
  ),
  ReplyDrill(
    id: 'reply:koko-wa-eki',
    promptKana: 'ここは えきですか',
    promptRomaji: 'koko wa eki desu ka',
    promptMeaning: '這裡是車站嗎',
    intentCorrect: '問這裡是不是車站',
    intentWrong: ['問你要去哪裡', '問車站在哪裡'],
    replyCorrectKana: 'はい',
    replyCorrectRomaji: 'hai',
    replyCorrectMeaning: '是／好',
    replyWrongKana: ['みぎです', 'ここです'],
    requiredSeenIds: ['word:ここ', 'word:えき'],
  ),
];
