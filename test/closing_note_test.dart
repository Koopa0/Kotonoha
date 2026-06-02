// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:kotonoha/ui/core/app_strings.dart';

void main() {
  test('the close keeps the same competence clause, day and night', () {
    final day = AppStrings.closingNote('あ', band: ClosingBand.day);
    final night = AppStrings.closingNote('あ', band: ClosingBand.night);
    expect(day, contains('和「あ」更熟了一點'));
    expect(night, contains('和「あ」更熟了一點'));
  });

  test('only the send-off differs — night gives permission to stop', () {
    final day = AppStrings.closingNote('あ', band: ClosingBand.day);
    final night = AppStrings.closingNote('あ', band: ClosingBand.night);
    expect(day, contains('去過你的一天吧'));
    expect(day, isNot(contains('好好休息')));
    expect(night, contains('好好休息'));
    expect(night, isNot(contains('去過你的一天吧')));
  });

  test('the close softens at dusk (19:00), two bands only', () {
    expect(ClosingBand.forHour(9), ClosingBand.day);
    expect(ClosingBand.forHour(18), ClosingBand.day);
    expect(ClosingBand.forHour(19), ClosingBand.night); // dusk threshold
    expect(ClosingBand.forHour(23), ClosingBand.night);
    // A single dusk threshold (no dawn wrap) — the small hours read as day.
    expect(ClosingBand.forHour(0), ClosingBand.day);
    expect(ClosingBand.values.length, 2);
  });
}
