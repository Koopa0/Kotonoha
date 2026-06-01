// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/data/services/analytics_log.dart';
import 'package:kotonoha/data/services/speech_service.dart';
import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/word.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/core/widgets/session_summary.dart';
import 'package:provider/provider.dart';

/// 渡し舟 — the Ferry. For a learner whose ear runs ahead of his eye: a word he
/// may already know by sound is ferried across to its written body in three
/// beats — (1) hear it, (2) watch the kana ink in over the still-ringing audio
/// (the binding), (3) read it back unaided. The thesis made mechanical. Records
/// a reading [Attempt] (mode=ferry); reaction time is the read-back.
class FerryScreen extends StatefulWidget {
  const FerryScreen({required this.words, required this.title, super.key});

  final List<Word> words;
  final String title;

  static Route<void> route(List<Word> words, String title) =>
      MaterialPageRoute<void>(
        builder: (_) => FerryScreen(words: words, title: title),
      );

  @override
  State<FerryScreen> createState() => _FerryScreenState();
}

enum _Beat { hear, see, readback }

class _FerryScreenState extends State<FerryScreen> {
  final String _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
  int _index = 0;
  _Beat _beat = _Beat.hear;
  int _seenAtMs = 0;
  int _correct = 0;
  bool _done = false;

  Word get _current => widget.words[_index];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _speak());
  }

  void _speak() {
    if (!mounted) return;
    context.read<SpeechService>().speak(_current.kana);
  }

  void _showText() {
    _speak();
    setState(() {
      _beat = _Beat.see;
      _seenAtMs = DateTime.now().millisecondsSinceEpoch;
    });
  }

  void _readSelf() => setState(() => _beat = _Beat.readback);

  void _grade(bool correct) {
    final now = DateTime.now();
    context.read<AnalyticsLog>().record(
      Attempt(
        ts: now.millisecondsSinceEpoch,
        itemId: _current.kana,
        mode: PracticeMode.ferry.name,
        correct: correct,
        rtMs: now.millisecondsSinceEpoch - _seenAtMs,
        sessionId: _sessionId,
        meta: {'romaji': _current.romaji},
      ),
    );
    if (correct) _correct++;
    if (_index + 1 >= widget.words.length) {
      setState(() => _done = true);
    } else {
      setState(() {
        _index++;
        _beat = _Beat.hear;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _speak());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(child: _done ? _summary() : _question()),
    );
  }

  Widget _summary() => SessionSummary(
    headline: AppStrings.readingSummary(_correct, widget.words.length),
    onDone: () => Navigator.of(context).pop(),
  );

  Widget _question() {
    final showKana = _beat != _Beat.hear;
    return Column(
      children: [
        const SizedBox(height: 8),
        Text(
          '${_index + 1} / ${widget.words.length}',
          style: const TextStyle(
            color: AppColors.inkMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  _Speaker(onTap: _speak, big: !showKana),
                  if (showKana) ...[
                    const SizedBox(height: 24),
                    // The kana inks in — fades and rises into being.
                    _InkIn(
                      key: ValueKey(_index),
                      child: Text(
                        _current.kana,
                        style: const TextStyle(
                          fontSize: 64,
                          height: 1.1,
                          fontWeight: FontWeight.w500,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    switch (_beat) {
                      _Beat.hear => AppStrings.ferryHear,
                      _Beat.see => AppStrings.ferrySee,
                      _Beat.readback => AppStrings.ferryReadback,
                    },
                    style: const TextStyle(
                      color: AppColors.inkMuted,
                      fontSize: 15,
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: _controls(),
        ),
      ],
    );
  }

  Widget _controls() {
    switch (_beat) {
      case _Beat.hear:
        return SizedBox(
          height: 54,
          child: FilledButton(
            onPressed: _showText,
            child: const Text(AppStrings.ferryShowText),
          ),
        );
      case _Beat.see:
        return SizedBox(
          height: 54,
          child: FilledButton(
            onPressed: _readSelf,
            child: const Text(AppStrings.ferryReadSelf),
          ),
        );
      case _Beat.readback:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  side: const BorderSide(color: AppColors.error),
                  foregroundColor: AppColors.error,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () => _grade(false),
                child: const Text(AppStrings.iCouldnt),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.success,
                  minimumSize: const Size.fromHeight(54),
                ),
                onPressed: () => _grade(true),
                child: const Text(AppStrings.iReadIt),
              ),
            ),
          ],
        );
    }
  }
}

/// Fades and rises its child into being — ink surfacing on wet paper.
class _InkIn extends StatelessWidget {
  const _InkIn({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, (1 - v) * 14),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _Speaker extends StatelessWidget {
  const _Speaker({required this.onTap, required this.big});

  final VoidCallback onTap;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      onPressed: onTap,
      iconSize: big ? 56 : 34,
      style: IconButton.styleFrom(
        backgroundColor: AppColors.accentSoft,
        foregroundColor: AppColors.accent,
        padding: EdgeInsets.all(big ? 22 : 14),
      ),
      icon: const Icon(Icons.volume_up_rounded),
    );
  }
}
