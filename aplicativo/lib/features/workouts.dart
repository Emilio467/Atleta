import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../core/controller.dart';
import '../core/models.dart';
import '../core/strings.dart';
import '../ui/components.dart';
import '../ui/theme.dart';
import 'metrics.dart';
import 'records.dart';
import 'watch.dart';

class WorkoutsScreen extends StatefulWidget {
  const WorkoutsScreen({super.key});
  @override
  State<WorkoutsScreen> createState() => _WorkoutsScreenState();
}

class _WorkoutsScreenState extends State<WorkoutsScreen> {
  String? _filterType;
  DateTime? _filterDay;
  bool _clearing = false;

  Future<void> _clearHistory(AtletaController store) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(S.clearHistoryTitle),
        content: const Text(S.clearHistoryMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(S.clearHistory),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
    var message = S.historyCleared;
    try {
      await store.clearWorkoutHistory();
    } on Exception {
      message = S.failed;
    } finally {
      if (mounted) {
        setState(() {
          _clearing = false;
          if (message == S.historyCleared) {
            _filterDay = null;
            _filterType = null;
          }
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AtletaScope.of(context);
    final list = store.data.workouts;
    final types = list.map((w) => S.activityName(w.activity)).toSet().toList()
      ..sort();
    final hasWorkout =
        store.data.session != null || store.data.watchDraft != null;
    final shown = list
        .where(
          (w) =>
              (_filterType == null ||
                  S.activityName(w.activity) == _filterType) &&
              (_filterDay == null || dayOf(w.start) == _filterDay),
        )
        .toList();
    final addActions = Wrap(
      spacing: 9,
      runSpacing: 5,
      children: [
        TextButton.icon(
          key: const ValueKey('add-workout'),
          onPressed: () => showWorkoutForm(context),
          icon: const Icon(CupertinoIcons.plus, size: 17),
          label: const Text(S.addWorkout),
        ),
        if (!hasWorkout)
          TextButton.icon(
            onPressed: () => showStartSession(context),
            icon: const Icon(CupertinoIcons.timer, size: 18),
            label: const Text(S.startSession),
          ),
      ],
    );
    return Screen(
      background: const DashboardBackground(),
      children: [
        const Text(S.workouts, style: Design.header),
        const SizedBox(height: 26),
        if (store.data.session case final session?)
          _SessionCard(session: session, store: store)
        else if (!store.demo)
          const WatchWorkoutPanel(),
        if (!hasWorkout) addActions,
        const SizedBox(height: 20),
        Row(
          children: [
            const Expanded(
              child: Text(S.workoutHistory, style: Design.dashboardSection),
            ),
            if (!store.demo)
              PopupMenuButton<String>(
                tooltip: S.historyOptions,
                icon: const Icon(Icons.more_horiz_rounded),
                onSelected: (_) => _clearHistory(store),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: S.clearHistory,
                    enabled: list.isNotEmpty && !_clearing,
                    child: const Text(S.clearHistory),
                  ),
                ],
              ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            ActionChip(
              avatar: const Icon(
                CupertinoIcons.calendar,
                size: 17,
                color: Palette.text,
              ),
              backgroundColor: const Color(0xFF171A16),
              side: const BorderSide(color: Palette.border),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              label: _FilterLabel(
                _filterDay == null ? S.allDates : S.shortDay(_filterDay!),
              ),
              onPressed: () async {
                final date = await chooseDate(
                  context,
                  _filterDay ?? store.today,
                  store.now(),
                );
                if (date != null && mounted) setState(() => _filterDay = date);
              },
            ),
            PopupMenuButton<String>(
              tooltip: S.allTypes,
              onSelected: (activity) => setState(
                () => _filterType = activity.isEmpty ? null : activity,
              ),
              itemBuilder: (_) => [
                const PopupMenuItem(value: '', child: Text(S.allTypes)),
                for (final activity in types)
                  PopupMenuItem(value: activity, child: Text(activity)),
              ],
              child: Chip(
                avatar: const Icon(
                  CupertinoIcons.line_horizontal_3_decrease,
                  size: 17,
                  color: Palette.text,
                ),
                backgroundColor: const Color(0xFF171A16),
                side: const BorderSide(color: Palette.border),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                label: _FilterLabel(_filterType ?? S.allTypes),
              ),
            ),
            if (_filterDay != null)
              TextButton(
                onPressed: () => setState(() => _filterDay = null),
                child: const Text(S.clearDate),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (shown.isEmpty)
          EmptyCard(list.isEmpty ? S.noWorkouts : S.noneFiltered),
        for (final workout in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: WorkoutTile(
              workout,
              onTap: () =>
                  pushScreen(context, (_) => WorkoutScreen(id: workout.id)),
            ),
          ),
        if (!hasWorkout) ...[
          const SizedBox(height: 10),
          CompactTile(
            title: S.markRest,
            icon: CupertinoIcons.moon,
            onTap: () => showRestForm(context, selected: _filterDay),
          ),
        ],
      ],
    );
  }
}

class _FilterLabel extends StatelessWidget {
  const _FilterLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 7,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [Text(text), const Icon(CupertinoIcons.chevron_down, size: 12)],
  );
}

class _SessionCard extends StatefulWidget {
  const _SessionCard({required this.session, required this.store});
  final Session session;
  final AtletaController store;
  @override
  State<_SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<_SessionCard> {
  Timer? _tick;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (widget.session.activeSince != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _toggle() async {
    setState(() => _busy = true);
    try {
      await widget.store.toggleSession();
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(S.failed)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final running = session.activeSince != null;
    final elapsed = session.elapsed(widget.store.now()).inSeconds;
    return Material(
      color: Palette.surface,
      borderRadius: BorderRadius.circular(Design.card),
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(S.activityName(session.activity), style: Design.section),
            Text(running ? S.running : S.paused, style: Design.foot),
            const SizedBox(height: 5),
            Text(
              S.durationLabel(elapsed),
              style: Design.metric.copyWith(
                fontFamily: Design.mono,
                fontSize: 36,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : _toggle,
                  child: Text(running ? S.pause : S.resume),
                ),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => showWorkoutForm(context, session: session),
                  child: const Text(S.finish),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class WorkoutScreen extends StatelessWidget {
  const WorkoutScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    final store = AtletaScope.of(context);
    final workout = store.data.workouts.where((w) => w.id == id).firstOrNull;
    if (workout == null) {
      return Screen(
        children: [
          const CircleBack(),
          const SizedBox(height: 14),
          EmptyCard(S.noWorkouts),
        ],
      );
    }
    final local = !workout.origin.imported && workout.origin != Origin.demo;
    return Screen(
      background: const DetailBackground(),
      children: [
        const CircleBack(),
        const SizedBox(height: 18),
        Text(S.activityName(workout.activity), style: Design.header),
        const SizedBox(height: 7),
        Text(S.timestamp(workout.start), style: Design.body),
        const SizedBox(height: 16),
        CompactTile(
          title: S.duration,
          icon: CupertinoIcons.timer,
          trailing: Text(S.durationLabel(workout.seconds), style: Design.foot),
        ),
        const SizedBox(height: 8),
        CompactTile(
          title: S.effort,
          icon: CupertinoIcons.waveform_path,
          trailing: Text(
            workout.effort == null ? S.noValue : '${workout.effort}/10',
            style: Design.foot,
          ),
        ),
        if (workout.effort == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 3),
            child: Text(S.missingEffort, style: Design.foot),
          ),
        const SizedBox(height: 8),
        if (workout.watchStats case final stats?) ...[
          CompactTile(
            title: S.m5Steps,
            icon: Icons.watch_rounded,
            trailing: Text(stats.steps?.toString() ?? S.noValue),
          ),
          const SizedBox(height: 8),
          if (stats.distanceKm case final distance?) ...[
            CompactTile(
              title: S.m5Distance,
              trailing: Text('${distance.toStringAsFixed(3)} km'),
            ),
            const SizedBox(height: 8),
          ],
          if (stats.batteryPercent case final charge?) ...[
            CompactTile(title: S.m5Battery, trailing: Text('$charge%')),
            const SizedBox(height: 8),
          ],
        ],
        CompactTile(
          title: S.source,
          icon: CupertinoIcons.link,
          subtitle: workout.source.isEmpty
              ? S.origin(workout.origin)
              : '${S.origin(workout.origin)} · ${workout.source}',
        ),
        if (workout.notes.isNotEmpty) ...[
          const SizedBox(height: 8),
          CompactTile(title: S.notes, subtitle: workout.notes),
        ],
        const SizedBox(height: 16),
        Text(
          '${S.updated} · ${S.timestamp(workout.updated)}',
          style: Design.foot,
        ),
        const SizedBox(height: 16),
        if (local || workout.origin.imported)
          FilledButton(
            onPressed: () => showWorkoutForm(context, original: workout),
            child: Text(local ? S.editWorkout : S.adjustEffort),
          ),
        if (local)
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => _delete(context, store, workout),
            child: const Text(S.deleteWorkout),
          ),
      ],
    );
  }

  Future<void> _delete(
    BuildContext context,
    AtletaController store,
    Workout workout,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(S.deleteWorkout),
        content: const Text(S.deleteQuestion),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(S.deleteWorkout),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    try {
      await store.deleteWorkout(workout.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(S.deleted)));
      Navigator.of(context).pop();
    } on Exception {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(S.failed)));
      }
    }
  }
}
