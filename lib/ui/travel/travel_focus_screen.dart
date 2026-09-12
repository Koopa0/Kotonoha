// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/data/repositories/travel_focus_repository.dart';
import 'package:kotonoha/domain/models/travel_focus.dart';
import 'package:kotonoha/domain/models/travel_scene_id.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:provider/provider.dart';

/// Editor for the retained 1–2 travel focuses. Saving, switching, or
/// clearing writes only the plan — never kana or 詞と句 mastery.
class TravelFocusScreen extends StatefulWidget {
  const TravelFocusScreen({this.clock, super.key});

  final DateTime Function()? clock;

  static Route<void> route({DateTime Function()? clock}) =>
      MaterialPageRoute<void>(
        builder: (_) => TravelFocusScreen(clock: clock),
        settings: const RouteSettings(name: 'travel-focus'),
      );

  @override
  State<TravelFocusScreen> createState() => _TravelFocusScreenState();
}

class _TravelFocusScreenState extends State<TravelFocusScreen> {
  late List<TravelFocus> _draft;
  bool _limitHint = false;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _draft = List<TravelFocus>.of(
      context.read<TravelFocusRepository>().plan.focuses,
    );
  }

  bool _selected(TravelSceneId scene) =>
      _draft.any((focus) => focus.scene == scene);

  TravelFocus? _focus(TravelSceneId scene) {
    for (final focus in _draft) {
      if (focus.scene == scene) return focus;
    }
    return null;
  }

  void _toggle(TravelSceneId scene) {
    setState(() {
      if (_selected(scene)) {
        _draft = [
          for (final f in _draft)
            if (f.scene != scene) f,
        ];
        _limitHint = false;
        return;
      }
      if (_draft.length >= TravelFocusPlan.maxFocuses) {
        _limitHint = true;
        return;
      }
      _draft = [..._draft, TravelFocus(scene: scene)];
      _limitHint = false;
    });
  }

  Future<void> _pickDate(TravelSceneId scene) async {
    final current = _focus(scene)?.date ?? TravelFocusPlan.dayOf(_now);
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(_now.year - 1),
      lastDate: DateTime(_now.year + 2, 12, 31),
      helpText: AppStrings.travelFocusDateLabel,
    );
    if (!mounted || picked == null) return;
    setState(() {
      _draft = [
        for (final f in _draft)
          if (f.scene == scene) TravelFocus(scene: scene, date: picked) else f,
      ];
    });
  }

  void _clearDate(TravelSceneId scene) {
    setState(() {
      _draft = [
        for (final f in _draft)
          if (f.scene == scene) TravelFocus(scene: scene) else f,
      ];
    });
  }

  void _save() {
    final persist = context.read<ProgressPersistenceController>();
    persist.trackTravelFocus(
      context.read<TravelFocusRepository>().saveFocuses(_draft),
    );
    Navigator.of(context).pop();
  }

  void _clear() {
    final persist = context.read<ProgressPersistenceController>();
    persist.trackTravelFocus(context.read<TravelFocusRepository>().clear());
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.travelFocusTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            const Text(
              AppStrings.travelFocusHint,
              style: TextStyle(color: AppColors.inkMuted, height: 1.5),
            ),
            if (_limitHint) ...[
              const SizedBox(height: 10),
              const Text(
                AppStrings.travelFocusLimit,
                style: TextStyle(color: AppColors.inkMuted, height: 1.5),
              ),
            ],
            const SizedBox(height: 16),
            for (final scene in TravelSceneId.values) ...[
              _FocusTile(
                scene: scene,
                selected: _selected(scene),
                date: _focus(scene)?.date,
                onToggle: () => _toggle(scene),
                onDate: _selected(scene) ? () => _pickDate(scene) : null,
                onClearDate: _selected(scene) && _focus(scene)?.date != null
                    ? () => _clearDate(scene)
                    : null,
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              child: const Text(AppStrings.travelFocusSave),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _clear,
              style: TextButton.styleFrom(foregroundColor: AppColors.inkMuted),
              child: const Text(AppStrings.travelFocusClear),
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusTile extends StatelessWidget {
  const _FocusTile({
    required this.scene,
    required this.selected,
    required this.date,
    required this.onToggle,
    this.onDate,
    this.onClearDate,
  });

  final TravelSceneId scene;
  final bool selected;
  final DateTime? date;
  final VoidCallback onToggle;
  final VoidCallback? onDate;
  final VoidCallback? onClearDate;

  String get _label => switch (scene) {
    TravelSceneId.transport => AppStrings.travelSceneTransport,
    TravelSceneId.clothing => AppStrings.travelSceneClothing,
    TravelSceneId.shrine => AppStrings.travelSceneShrine,
    TravelSceneId.parkQueue => AppStrings.travelSceneParkQueue,
    TravelSceneId.restaurant => AppStrings.travelSceneRestaurant,
    TravelSceneId.convenience => AppStrings.travelSceneConvenience,
    TravelSceneId.hotel => AppStrings.travelSceneHotel,
  };

  String get _purpose => switch (scene) {
    TravelSceneId.transport => AppStrings.travelScenePurposeTransport,
    TravelSceneId.clothing => AppStrings.travelScenePurposeClothing,
    TravelSceneId.shrine => AppStrings.travelScenePurposeShrine,
    TravelSceneId.parkQueue => AppStrings.travelScenePurposeParkQueue,
    TravelSceneId.restaurant => AppStrings.travelScenePurposeRestaurant,
    TravelSceneId.convenience => AppStrings.travelScenePurposeConvenience,
    TravelSceneId.hotel => AppStrings.travelScenePurposeHotel,
  };

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              value: selected,
              onChanged: (_) => onToggle(),
              contentPadding: const EdgeInsets.only(left: 8, right: 4),
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                _label,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              subtitle: Text(
                _purpose,
                style: const TextStyle(color: AppColors.inkMuted),
              ),
            ),
            if (selected)
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 8, bottom: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    TextButton(
                      onPressed: onDate,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.ink,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        minimumSize: const Size(48, 48),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        date == null
                            ? '${AppStrings.travelFocusDateLabel} · ${AppStrings.travelFocusDateUnset}'
                            : '${AppStrings.travelFocusDateLabel} · ${TravelFocusPlan.isoDay(date!)}',
                        style: const TextStyle(height: 1.4),
                      ),
                    ),
                    if (onClearDate != null)
                      TextButton(
                        onPressed: onClearDate,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.inkMuted,
                          minimumSize: const Size(48, 48),
                        ),
                        child: const Text(AppStrings.travelFocusDateClear),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
