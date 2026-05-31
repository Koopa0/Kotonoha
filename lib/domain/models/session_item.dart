// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:kotonoha/domain/models/attempt.dart';
import 'package:kotonoha/domain/models/quiz_question.dart';

/// One question in a session, tagged with the mode it should be logged as.
/// Lets an adaptive session mix modes (MC / listening) within one run.
///
/// Pure data: no `package:flutter/*` imports.
class SessionItem {
  const SessionItem({required this.question, required this.mode});

  final QuizQuestion question;
  final PracticeMode mode;
}
