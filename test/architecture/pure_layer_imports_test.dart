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

  test(
    'the data layer never imports use_cases (the dependency points one way)',
    () {
      final offenders = _scan(
        dirs: ['lib/data', 'lib/kanji/data'],
        forbidden: RegExp('''^\\s*(?:import|export)\\s+['"].*use_cases/'''),
      );
      expect(
        offenders,
        isEmpty,
        reason:
            'a use_case MAY depend on a repository or service, never the '
            'reverse — found:\n${offenders.join('\n')}',
      );
    },
  );

  test('the data layer never imports the UI layer', () {
    final offenders = _scan(
      dirs: ['lib/data', 'lib/kanji/data'],
      forbidden: RegExp(
        '''^\\s*(?:import|export)\\s+['"]package:kotonoha/(?:kanji/)?ui/''',
      ),
    );
    expect(
      offenders,
      isEmpty,
      reason:
          'data must not know the widgets or controllers that observe it — '
          'found:\n${offenders.join('\n')}',
    );
  });

  test('services never import repositories (services sit below them)', () {
    final offenders = _scan(
      dirs: ['lib/data/services'],
      forbidden: RegExp('''^\\s*(?:import|export)\\s+['"].*repositories/'''),
    );
    expect(
      offenders,
      isEmpty,
      reason:
          'a service wraps a platform source or a storage contract; the '
          'journal and the store keys must not depend on the repositories '
          'that own them — found:\n${offenders.join('\n')}',
    );
  });

  test('the data layer has no import cycles', () {
    final files = _dartFilesUnder(['lib/data', 'lib/kanji/data']);
    final edges = <String, List<String>>{};
    final pattern = RegExp(
      '''^\\s*(?:import|export)\\s+['"]package:kotonoha/((?:kanji/)?data/[^'"]+)['"]''',
    );
    for (final file in files) {
      final from = file.path.replaceFirst(RegExp('^lib/'), '');
      edges[from] = [
        for (final line in file.readAsLinesSync())
          if (pattern.firstMatch(line) case final m?) m.group(1)!,
      ];
    }
    final cycle = _firstCycle(edges);
    expect(
      cycle,
      isNull,
      reason:
          'the backup / restore layer once had journal → repository → journal; '
          'a cycle means two files own each other — found:\n'
          '${cycle?.join(' → ')}',
    );
  });

  test('ViewModels hold no view dependencies (widgets, timers, or navigation)', () {
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
    final forbidden = RegExp(
      r"""\b(Timer\s*[.(]|Navigator\.|BuildContext\b)|^\s*(?:import|export)\s+['"].*(?:/widgets/|_screen\.dart|package:flutter/(?:material|cupertino|widgets)\.dart)""",
    );
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
          'ViewModels must not depend on widgets — cosmetic delays and routing '
          'belong to the View. Found:\n${offenders.join('\n')}',
    );
  });

  test('migrated feature views leave progress and analytics writes to their ViewModel', () {
    // A feature counts as split into View / ViewModel (#149) once its
    // directory holds a *_viewmodel.dart; every *_screen.dart beside it is
    // then a View. Discovering the set from the tree means each batch that
    // lands is guarded without editing a list here (and without merge
    // conflicts between batches). A view may still *inject* a repository or
    // the analytics log into its ViewModel — it must never mutate one.
    final migratedDirs = _dartFilesUnder(['lib/ui', 'lib/kanji/ui'])
        .where((f) => f.path.endsWith('_viewmodel.dart'))
        .map((f) => f.parent.path)
        .toSet()
        .toList();
    expect(
      migratedDirs,
      isNotEmpty,
      reason:
          'no *_viewmodel.dart files found — the naming convention moved '
          'and this guard is scanning nothing; update the glob',
    );
    final migratedViews = _dartFilesUnder(migratedDirs)
        .where((f) => f.path.endsWith('_screen.dart'))
        .toList();
    expect(
      migratedViews,
      isNotEmpty,
      reason: 'a ViewModel directory with no *_screen.dart beside it',
    );
    final forbidden = RegExp(
      r'\.(recordAnswer|recordPromptedPractice|markIntroduced|introduce|'
      'markUnitLearned|recordObserved|record|trackKana|trackKanji|trackWord|'
      r'trackPlacement|trackAnalytics|trackTravelFocus)\s*\(',
    );
    final offenders = <String>[];
    for (final file in migratedViews) {
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
          'learning evidence, schedule writes and analytics belong to the '
          'feature ViewModel, not the widget State — found:\n'
          '${offenders.join('\n')}',
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

/// The first import cycle in [edges] as a path that starts and ends on the
/// same file, or null when the graph is acyclic. Plain DFS with a grey set.
List<String>? _firstCycle(Map<String, List<String>> edges) {
  final done = <String>{};
  final stack = <String>[];
  final onStack = <String>{};
  List<String>? visit(String node) {
    if (onStack.contains(node)) {
      return [...stack.sublist(stack.indexOf(node)), node];
    }
    if (done.contains(node)) return null;
    stack.add(node);
    onStack.add(node);
    for (final next in edges[node] ?? const <String>[]) {
      final found = visit(next);
      if (found != null) return found;
    }
    stack.removeLast();
    onStack.remove(node);
    done.add(node);
    return null;
  }

  for (final node in edges.keys) {
    final found = visit(node);
    if (found != null) return found;
  }
  return null;
}
