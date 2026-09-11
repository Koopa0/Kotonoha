// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

/// Travel-purpose rooms the learner can ask for. Scene membership lives on
/// [TravelScene]; this id is the stable token a plan can persist.
enum TravelSceneId {
  transport,
  clothing,
  shrine,
  parkQueue,
  restaurant,
  convenience,
}
