// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

// Prints every legal reading id in the kanji curriculum, for corpus authoring.
// Run: dart run tool/dump_reading_ids.dart
import 'package:kotonoha/kanji/domain/data/kanji_dataset.dart';

void main() {
  for (final k in kKanji) {
    final readings = k.readings
        .map((r) => '${r.text}(${r.kind.name})')
        .join(' / ');
    // ignore: avoid_print
    print('${k.char}\t$readings\t${k.readingIds.join(" | ")}');
  }
}
