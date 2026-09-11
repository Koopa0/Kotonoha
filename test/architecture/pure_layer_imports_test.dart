// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// RULER guards for the one-way dependency rules (CLAUDE.md /
/// docs/architecture.md). Each rule below was once held only by code review +
/// doc-comment reminders — `flutter analyze` and the whole suite stay GREEN if
/// someone quietly breaks one (e.g. adds `import 'package:flutter/material.dart';`
/// to a domain file, or reaches for a Timer inside a ViewModel). These tests walk
/// the source at test time and fail on the first offender, turning each hoped
/// invariant into an executable one.
/// (Pure dart:io — no Flutter binding needed; runs under `flutter test`.)
void main() {
  test('the pure domain layer imports no package:flutter/* or dart:ui', () {
    final offenders = _scan(
      dirs: [
        'lib/domain/models',
        'lib/domain/data',
        'lib/domain/use_cases',
        'lib/kanji/domain',
      ],
      forbidden: RegExp('''^\\s*import\\s+['"](package:flutter/|dart:ui)'''),
    );
    expect(
      offenders,
      isEmpty,
      reason:
          'pure layer must not import Flutter / dart:ui — found:\n'
          '${offenders.join('\n')}',
    );
  });

  test('repositories never import use_cases (the dependency points one way)', () {
    final offenders = _scan(
      dirs: ['lib/data/repositories', 'lib/kanji/data/repositories'],
      forbidden: RegExp('''^\\s*import\\s+['"].*use_cases/'''),
    );
    expect(
      offenders,
      isEmpty,
      reason:
          'a use_case MAY depend on a repository, never the reverse — found:\n'
          '${offenders.join('\n')}',
    );
  });

  test('ViewModels hold no Timer / Navigator / BuildContext (the View owns those)', () {
    // Match the current naming convention. If the convention ever changes the
    // scanned-files assertion below fails loudly instead of the guard silently
    // matching nothing.
    final viewmodelFiles = _dartFilesUnder(['lib/ui', 'lib/kanji/ui'])
        .where((f) => f.path.endsWith('viewmodel.dart'))
        .toList();
    expect(
      viewmodelFiles,
      isNotEmpty,
      reason:
          'no *viewmodel.dart files found — the naming convention moved '
          'and this guard is scanning nothing; update the glob',
    );
    final forbidden = RegExp(r'\b(Timer\s*[.(]|Navigator\.|BuildContext\b)');
    final offenders = <String>[];
    for (final file in viewmodelFiles) {
      for (final line in file.readAsLinesSync()) {
        final t = line.trimLeft();
        if (t.startsWith('//') || t.startsWith('*')) continue;
        if (forbidden.hasMatch(line)) {
          offenders.add('${file.path}: ${line.trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'ViewModels are pure ChangeNotifiers — cosmetic delays and routing '
          'belong to the View. Found:\n${offenders.join('\n')}',
    );
  });

  test('the UI layer never touches platform packages directly (services wrap them)', () {
    final offenders = _scan(
      dirs: ['lib/ui', 'lib/kanji/ui'],
      forbidden: RegExp(
        '''^\\s*import\\s+['"](package:shared_preferences/|package:path_provider/|package:file_picker/|package:flutter_tts/|dart:io)''',
      ),
    );
    expect(
      offenders,
      isEmpty,
      reason:
          'ui must reach platform sources only through data/services — found:\n'
          '${offenders.join('\n')}',
    );
  });
}

/// All .dart files under [dirs]; every directory must exist (a moved/renamed
/// layer should fail the guard loudly, not silently scan nothing).
List<File> _dartFilesUnder(List<String> dirs) {
  final files = <File>[];
  for (final glob in dirs) {
    final dir = Directory(glob);
    expect(dir.existsSync(), isTrue, reason: 'missing layer dir: $glob');
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) files.add(entity);
    }
  }
  return files;
}

/// Non-comment lines matching [forbidden] across every .dart file in [dirs],
/// as `path: line` strings. A "must not import X" doc-comment reminder is
/// intent, not an import — comment lines are skipped.
List<String> _scan({required List<String> dirs, required RegExp forbidden}) {
  final offenders = <String>[];
  for (final file in _dartFilesUnder(dirs)) {
    for (final line in file.readAsLinesSync()) {
      final t = line.trimLeft();
      if (t.startsWith('//') || t.startsWith('*')) continue;
      if (forbidden.hasMatch(line)) {
        offenders.add('${file.path}: ${line.trim()}');
      }
    }
  }
  return offenders;
}
