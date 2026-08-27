// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

// Which kanji the sentence corpus actually asks the learner to read, but the
// curriculum inventory (kKanji) does not know — ranked by how often they occur.
// The corpus tells the curriculum what to teach next, rather than a JLPT list
// deciding for it; an unknown kanji still works, it just cannot contribute the
// naive-misreading distractor that makes a question honest.
//
// Run: dart run tool/dump_unit_inventory_gap.dart
import 'package:kotonoha/kanji/domain/data/kanji_dataset.dart';
import 'package:kotonoha/kanji/domain/use_cases/kanji_units.dart';

void main() {
  final known = {for (final k in kKanji) k.char};
  final counts = <String, int>{};
  final examples = <String, String>{};
  for (final unit in kKanjiUnits) {
    for (final char in unit.chars) {
      if (known.contains(char)) continue;
      counts[char] = (counts[char] ?? 0) + 1;
      examples.putIfAbsent(char, () => '${unit.written}【${unit.reading}】');
    }
  }
  final ranked = counts.keys.toList()
    ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  // ignore: avoid_print
  print(
    'units: ${kKanjiUnits.length}  kanji in inventory: ${known.length}  '
    'missing: ${ranked.length}',
  );
  for (final char in ranked) {
    // ignore: avoid_print
    print('$char\t${counts[char]}\t${examples[char]}');
  }
}
