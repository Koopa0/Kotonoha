// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/domain/models/reply_drill.dart';

/// First-slice station replies: hear a Kyoto-station ask, name the intent,
/// pick one short answer that fits the named situation. Original staff /
/// passer-by turns. Reuses shipped T01 phrases or already-met station words;
/// does not copy paid text and does not join the 黙読 / [TravelScene] pools.
///
/// Pure data: no `package:flutter/*` imports.
const List<ReplyDrill> kReplyDrills = [
  ReplyDrill(
    id: 'reply:doko-e-iku',
    sceneZh: '檢票口有人問你要去哪裡。',
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
    sceneZh: '有人問路。改札在你右邊。',
    promptKana: 'えきは どこ',
    promptRomaji: 'eki wa doko',
    promptMeaning: '車站在哪裡',
    intentCorrect: '問車站在哪裡',
    intentWrong: ['問你要去哪裡', '問這裡是不是車站'],
    replyCorrectKana: 'みぎです',
    replyCorrectRomaji: 'migi desu',
    replyCorrectMeaning: '在右邊',
    replyWrongKana: ['はい', 'きょうとです'],
    requiredSeenIds: ['phrase:えきは どこ', 'word:みぎ'],
  ),
  ReplyDrill(
    id: 'reply:eki-wa-koko',
    sceneZh: '你站在車站門口。有人問路。',
    promptKana: 'えきは どこ',
    promptRomaji: 'eki wa doko',
    promptMeaning: '車站在哪裡',
    intentCorrect: '問車站在哪裡',
    intentWrong: ['問你要去哪裡', '問這裡是不是車站'],
    replyCorrectKana: 'ここです',
    replyCorrectRomaji: 'koko desu',
    replyCorrectMeaning: '就在這裡',
    replyWrongKana: ['はい', 'きょうとです'],
    requiredSeenIds: ['phrase:えきは どこ', 'word:ここ'],
  ),
  ReplyDrill(
    id: 'reply:koko-wa-eki',
    sceneZh: '有人指這裡，確認是不是車站。',
    promptKana: 'ここは えきですか',
    promptRomaji: 'koko wa eki desu ka',
    promptMeaning: '這裡是車站嗎',
    intentCorrect: '問這裡是不是車站',
    intentWrong: ['問你要去哪裡', '問車站在哪裡'],
    replyCorrectKana: 'はい',
    replyCorrectRomaji: 'hai',
    replyCorrectMeaning: '是／好',
    replyWrongKana: ['みぎです', 'きょうとです'],
    requiredSeenIds: ['word:ここ', 'word:えき'],
  ),
];
