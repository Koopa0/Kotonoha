// Copyright (c) 2026 Koopa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:kotonoha/data/repositories/travel_focus_repository.dart';
import 'package:kotonoha/domain/models/travel_focus.dart';
import 'package:kotonoha/domain/models/travel_scene_id.dart';
import 'package:kotonoha/ui/core/app_strings.dart';
import 'package:kotonoha/ui/core/persistence/progress_persistence_controller.dart';
import 'package:kotonoha/ui/core/theme/app_colors.dart';
import 'package:kotonoha/ui/travel/travel_focus_viewmodel.dart';
import 'package:provider/provider.dart';

/// Editor for the retained 1–2 travel focuses. Saving, switching, or
/// clearing writes only the plan — never kana or 詞と句 mastery.
///
/// A thin View over [TravelFocusViewModel]: it renders the tiles, shows the
/// date picker, and pops once a write landed. The draft, the two-focus
/// limit and the save / clear writes are the ViewModel's.
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
  late final TravelFocusViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = TravelFocusViewModel(
      focuses: context.read<TravelFocusRepository>(),
      persistence: context.read<ProgressPersistenceController>(),
      clock: widget.clock,
    );
  }

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  Future<void> _pickDate(TravelSceneId scene) async {
    if (_vm.isBlocked) return;
    final now = _vm.now;
    final picked = await showDatePicker(
      context: context,
      initialDate: _vm.initialDateFor(scene),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2, 12, 31),
      helpText: AppStrings.travelFocusDateLabel,
    );
    if (!mounted || picked == null) return;
    _vm.setDate(scene, picked);
  }

  Future<void> _save() async {
    if (await _vm.save() && mounted) Navigator.of(context).pop();
  }

  Future<void> _clear() async {
    if (await _vm.clear() && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.travelFocusTitle)),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _vm,
          builder: (context, _) => _editor(),
        ),
      ),
    );
  }

  Widget _editor() {
    final blocked = _vm.isBlocked;
    final saving = _vm.isSaving;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        const Text(
          AppStrings.travelFocusHint,
          style: TextStyle(color: AppColors.inkMuted, height: 1.5),
        ),
        if (_vm.showsLimitHint) ...[
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
            selected: _vm.isSelected(scene),
            date: _vm.dateOf(scene),
            enabled: !blocked,
            onToggle: () => _vm.toggle(scene),
            onDate: _vm.isSelected(scene) ? () => _pickDate(scene) : null,
            onClearDate: _vm.isSelected(scene) && _vm.dateOf(scene) != null
                ? () => _vm.clearDate(scene)
                : null,
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 8),
        FilledButton(
          onPressed: blocked ? null : _save,
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 56),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          child: Text(
            saving ? AppStrings.backupSaving : AppStrings.travelFocusSave,
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: blocked ? null : _clear,
          style: TextButton.styleFrom(foregroundColor: AppColors.inkMuted),
          child: Text(
            saving ? AppStrings.backupSaving : AppStrings.travelFocusClear,
          ),
        ),
      ],
    );
  }
}

class _FocusTile extends StatelessWidget {
  const _FocusTile({
    required this.scene,
    required this.selected,
    required this.date,
    required this.enabled,
    required this.onToggle,
    this.onDate,
    this.onClearDate,
  });

  final TravelSceneId scene;
  final bool selected;
  final DateTime? date;
  final bool enabled;
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
              onChanged: enabled ? (_) => onToggle() : null,
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
                      onPressed: enabled ? onDate : null,
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
                        onPressed: enabled ? onClearDate : null,
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
