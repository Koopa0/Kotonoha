// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/domain/models/info_drill.dart';

/// Travel info-extraction drills. Readings cross-checked against minna L01–06
/// (いくら／時刻) and L07–12 (人数) reference phrases in the kanji track.
const List<InfoDrill> kInfoDrills = [
  InfoDrill(
    id: 'info:amount-3000',
    kind: InfoKind.amount,
    sceneZh: '店員在念這件商品的價格。',
    promptKana: 'さんぜん えん です',
    promptRomaji: 'sanzen en desu',
    promptMeaning: '（價格是）三千日圓',
    correctAnswer: '3000日圓',
    wrongAnswers: ['6000日圓', '300日圓'],
    requiredSeenIds: ['word:さんぜん', 'word:えん'],
  ),
  InfoDrill(
    id: 'info:amount-6000',
    kind: InfoKind.amount,
    sceneZh: '收費櫃檯播報應付金額。',
    promptKana: 'ろくせん えん です',
    promptRomaji: 'rokusen en desu',
    promptMeaning: '（價格是）六千日圓',
    correctAnswer: '6000日圓',
    wrongAnswers: ['3000日圓', '600日圓'],
    requiredSeenIds: ['word:ろく', 'word:せん', 'word:えん'],
  ),
  InfoDrill(
    id: 'info:time-10am',
    kind: InfoKind.time,
    sceneZh: '廣播通知集合時間。',
    promptKana: 'ごぜん じゅう じ です',
    promptRomaji: 'gozen juu ji desu',
    promptMeaning: '（時間是）上午十點',
    correctAnswer: '上午10點',
    wrongAnswers: ['上午3點', '下午10點'],
    requiredSeenIds: ['word:ごぜん', 'word:じゅう', 'word:じ'],
  ),
  InfoDrill(
    id: 'info:time-330pm',
    kind: InfoKind.time,
    sceneZh: '工作人員告知入場時間。',
    promptKana: 'ごご さん じ はん です',
    promptRomaji: 'gogo san ji han desu',
    promptMeaning: '（時間是）下午三點半',
    correctAnswer: '下午3點半',
    wrongAnswers: ['上午3點半', '下午10點'],
    requiredSeenIds: ['word:ごご', 'word:さん', 'word:じ', 'word:はん'],
  ),
  InfoDrill(
    id: 'info:person-1',
    kind: InfoKind.personCount,
    sceneZh: '售票窗口確認要幾張票。',
    promptKana: 'ひとり です',
    promptRomaji: 'hitori desu',
    promptMeaning: '（人數是）一位',
    correctAnswer: '1位',
    wrongAnswers: ['2位', '3位'],
    requiredSeenIds: ['word:ひとり'],
  ),
  InfoDrill(
    id: 'info:person-2',
    kind: InfoKind.personCount,
    sceneZh: '窗口確認同行人數。',
    promptKana: 'ふたり です',
    promptRomaji: 'futari desu',
    promptMeaning: '（人數是）兩位',
    correctAnswer: '2位',
    wrongAnswers: ['1位', '3位'],
    requiredSeenIds: ['word:ふたり'],
  ),
];

List<InfoDrill> infoDrillsFor(InfoKind? kind) {
  if (kind == null) return List<InfoDrill>.unmodifiable(kInfoDrills);
  return List<InfoDrill>.unmodifiable([
    for (final drill in kInfoDrills)
      if (drill.kind == kind) drill,
  ]);
}
