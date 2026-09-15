// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ARCHITECTURE.md promises that every source convention it lists has an
/// executable guard, and its Guards table is where the promise is cashed. That
/// table is prose, so it rots the moment someone adds a guard and forgets the
/// row — which is exactly what happened when the kana progress contract landed
/// and the table stayed twelve rows against thirteen tests.
///
/// This test makes the table itself executable: the right-hand column must name
/// the tests in pure_layer_imports_test.dart, exactly, in both directions. A new
/// guard without a row fails here, and so does a row that outlived its guard.
void main() {
  test('the Guards table lists exactly the guards that exist', () {
    final documented = _guardTableEntries();
    final actual = _guardTestNames();

    expect(
      documented,
      isNotEmpty,
      reason:
          'no rows parsed out of the Guards table in ARCHITECTURE.md — the '
          'heading or table shape moved and this test is reading nothing',
    );
    expect(
      actual,
      isNotEmpty,
      reason:
          'no tests parsed out of pure_layer_imports_test.dart — the file moved '
          'or its test style changed and this test is reading nothing',
    );

    final undocumented = actual.difference(documented).toList()..sort();
    expect(
      undocumented,
      isEmpty,
      reason:
          'these guards exist but no row in the ARCHITECTURE.md Guards table '
          'names them, so the document under-states what is enforced — add a '
          'row for each:\n${undocumented.join('\n')}',
    );

    final stale = documented.difference(actual).toList()..sort();
    expect(
      stale,
      isEmpty,
      reason:
          'the ARCHITECTURE.md Guards table names these, but no test in '
          'pure_layer_imports_test.dart does, so the document claims '
          'enforcement it does not have — remove or rename each row:\n'
          '${stale.join('\n')}',
    );
  });
}

/// The right-hand cell of every row in the `## Guards` table of
/// ARCHITECTURE.md, minus the header and separator rows.
Set<String> _guardTableEntries() {
  final lines = File('ARCHITECTURE.md').readAsLinesSync();
  final start = lines.indexWhere((l) => l.trim() == '## Guards');
  expect(
    start,
    isNot(-1),
    reason: 'ARCHITECTURE.md has no "## Guards" heading',
  );

  final names = <String>{};
  for (final line in lines.skip(start + 1)) {
    final trimmed = line.trim();
    // The table ends at the first line after it that is not a row.
    if (!trimmed.startsWith('|')) {
      if (names.isNotEmpty) break;
      continue;
    }
    final cells = trimmed.split('|').map((c) => c.trim()).toList();
    // A row splits into ['', rule, guard, ''].
    if (cells.length < 4) continue;
    final guard = cells[2];
    if (guard.isEmpty || guard.startsWith('---') || guard == 'Guard') continue;
    names.add(guard);
  }
  return names;
}

/// Every `test('...')` name declared in the import-guard suite.
Set<String> _guardTestNames() {
  final source = File('test/architecture/pure_layer_imports_test.dart')
      .readAsStringSync();
  // Covers both `test('name', () {` and the wrapped `test(\n  'name',\n` form
  // the formatter produces for long names.
  final pattern = RegExp(r"""\btest\(\s*'((?:[^'\\]|\\.)*)'""");
  return pattern.allMatches(source).map((m) => m.group(1)!).toSet();
}
