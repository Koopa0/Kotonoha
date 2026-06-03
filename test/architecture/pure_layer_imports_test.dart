// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// RULER guard for the one-way dependency rule (CLAUDE.md / docs/architecture.md):
/// the PURE layer must never import Flutter. This was held only by code review +
/// 12 doc-comment reminders — `flutter analyze` and the whole suite stay GREEN if
/// someone adds `import 'package:flutter/material.dart';` to a domain file (e.g. to
/// reach for Color/@immutable/debugPrint). This walks the source at test time and
/// fails on the first offender, turning a hoped invariant into an executable one.
/// (Pure dart:io — no Flutter binding needed; runs under `flutter test`.)
void main() {
  const pureGlobs = [
    'lib/domain/models',
    'lib/domain/data',
    'lib/domain/use_cases',
    'lib/kanji/domain',
  ];
  // An actual import of Flutter or dart:ui at the start of a (non-comment) line.
  final forbidden = RegExp('''^\\s*import\\s+['"](package:flutter/|dart:ui)''');

  test('the pure domain layer imports no package:flutter/* or dart:ui', () {
    final offenders = <String>[];
    for (final glob in pureGlobs) {
      final dir = Directory(glob);
      expect(dir.existsSync(), isTrue, reason: 'missing pure-layer dir: $glob');
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        for (final line in entity.readAsLinesSync()) {
          final t = line.trimLeft();
          // Skip doc/line/block comments — a "must not import flutter" reminder
          // is intent, not an import.
          if (t.startsWith('//') || t.startsWith('*')) continue;
          if (forbidden.hasMatch(line)) {
            offenders.add('${entity.path}: ${line.trim()}');
          }
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'pure layer must not import Flutter / dart:ui — found:\n'
          '${offenders.join('\n')}',
    );
  });
}
