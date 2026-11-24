import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/controller.dart';
import '../core/m5.dart';
import '../core/models.dart';
import '../core/strings.dart';
import '../data/repository.dart';
import '../data/watch_connection.dart';
import '../ui/components.dart';
import '../ui/theme.dart';
import 'metrics.dart';
import 'records.dart';

void showWatchConnection(BuildContext context, {VoidCallback? onConnected}) {
  pushScreen(
    context,
    (_) => WatchScreen(connectOnOpen: true, onConnected: onConnected),
  );
}

class WatchStatusTile extends StatelessWidget {
  const WatchStatusTile({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AtletaScope.of(context);
    return ListenableBuilder(
      listenable: store.watch,
      builder: (context, _) {
        final reading = store.watch.latest;
        final linked = store.data.watchLink != null;
        final summary = store.watch.pairing
            ? S.m5Pairing
            : reading == null
            ? linked
                  ? store.watch.connected
                        ? S.m5Waiting
                        : S.m5Disconnected
                  : S.m5Unlinked
            : '${S.m5Live} · ${reading.steps ?? S.noValue} ${S.stepsUnit} · ${S.durationLabel(store.watch.activeSecondsForDisplay(reading))}';
        return CompactTile(
          title: S.m5Watch,
          subtitle: summary,
          icon: Icons.watch_rounded,
          onTap: () => pushScreen(context, (_) => const WatchScreen()),
        );
      },
    );
  }
}

class WatchScreen extends StatefulWidget {
  const WatchScreen({super.key, this.connectOnOpen = false, this.onConnected});

  final bool connectOnOpen;
  final VoidCallback? onConnected;

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  bool _busy = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    if (!widget.connectOnOpen || kIsWeb) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _connect(AtletaScope.of(context));
    });
  }

  Future<void> _connect(AtletaController store) =>
      _run(() => _choose(store), loading: S.m5Searching);

  Future<void> _run(Future<void> Function() action, {String? loading}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = loading;
    });
    try {
      await action();
      if (mounted) setState(() => _status = null);
    } on WatchAlreadyLinked {
      if (mounted) setState(() => _status = S.m5LinkConflict);
    } on WorkoutInProgress {
      if (mounted) setState(() => _status = S.m5Busy);
    } on ValidationIssue catch (e) {
      if (mounted) setState(() => _status = e.message);
    } on WatchPairingFailed {
      if (mounted) setState(() => _status = S.m5PairingFailed);
    } on WatchAutoStartFailed {
      if (mounted) setState(() => _status = S.m5AutoStartFailed);
    } on Exception {
      if (mounted) setState(() => _status = S.m5Failed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choose(AtletaController store) async {
    final devices = await store.watch.discover();
    if (!mounted) return;
    if (devices.isEmpty) throw const ValidationIssue(S.m5None);
    final selected = devices.length == 1
        ? devices.single
        : await sheet<WatchLink>(
            context,
            (context) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const FormHeading(S.m5Select),
                const SizedBox(height: 12),
                for (final link in devices)
                  ListTile(
                    leading: const Icon(Icons.watch_rounded),
                    title: Text(link.name),
                    subtitle: Text(link.deviceId),
                    onTap: () => Navigator.pop(context, link),
                  ),
              ],
            ),
          );
    if (selected == null || !mounted) return;
    setState(() => _status = S.m5Connecting);
    await store.linkWatch(selected);
    if (mounted &&
        widget.connectOnOpen &&
        store.watch.connected &&
        ModalRoute.of(context)?.isCurrent == true) {
      Navigator.of(context).pop();
      widget.onConnected?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AtletaScope.of(context);
    final link = store.data.watchLink;
    return ListenableBuilder(
      listenable: store.watch,
      builder: (context, _) {
        final reading = store.watch.latest;
        final stats = reading?.totals(store.data.profile);
        final connected = store.watch.connected;
        final pairing = store.watch.pairing;
        return Screen(
          background: const DetailBackground(),
          children: [
            const CircleBack(),
            const SizedBox(height: 16),
            const Text(S.m5Watch, style: Design.header),
            const SizedBox(height: 13),
            if (link != null) Text(link.name, style: Design.body),
            if (!connected) const Text(S.m5Help, style: Design.body),
            const SizedBox(height: 13),
            if (link != null || pairing)
              EmptyCard(
                pairing
                    ? S.m5Pairing
                    : reading == null
                    ? connected
                          ? S.m5Waiting
                          : S.m5Disconnected
                    : S.m5Live,
              ),
            if (store.watch.canControl || store.data.watchDraft != null) ...[
              const SizedBox(height: 12),
              const WatchWorkoutPanel(showStatus: false),
            ],
            if (reading != null && stats != null) ...[
              const SizedBox(height: 10),
              CompactTile(
                title: S.m5Steps,
                trailing: Text(stats.steps?.toString() ?? S.noValue),
              ),
              const SizedBox(height: 6),
              CompactTile(
                title: S.m5ActiveTime,
                trailing: Text(
                  S.durationLabel(store.watch.activeSecondsForDisplay(reading)),
                ),
              ),
              const SizedBox(height: 6),
              CompactTile(
                title: S.m5Battery,
                trailing: Text(
                  stats.batteryPercent == null
                      ? S.noValue
                      : '${stats.batteryPercent}%',
                ),
              ),
              if (stats.distanceKm case final km?) ...[
                const SizedBox(height: 6),
                CompactTile(
                  title: S.m5Distance,
                  trailing: Text('${km.toStringAsFixed(3)} km'),
                ),
              ],
            ],
            const SizedBox(height: 15),
            if ((pairing ? S.m5PairingHelp : _status) case final status?) ...[
              Semantics(
                liveRegion: true,
                child: Text(status, style: Design.foot),
              ),
              const SizedBox(height: 12),
            ],
            if (!connected)
              FilledButton(
                onPressed: _busy || pairing || store.watchBusy
                    ? null
                    : () => _connect(store),
                child: Text(link == null ? S.m5Choose : S.m5Reconnect),
              ),
            if (connected)
              OutlinedButton(
                onPressed: _busy || store.watchBusy
                    ? null
                    : () => _run(store.watch.disconnect),
                child: const Text(S.m5Disconnect),
              ),
            if (link != null && store.data.watchDraft == null)
              TextButton(
                onPressed: _busy || pairing
                    ? null
                    : () => _run(store.forgetWatch),
                child: const Text(S.m5Forget),
              ),
            const SizedBox(height: 14),
            if (connected && !store.watch.canControl) ...[
              const Text(S.m5Legacy, style: Design.foot),
              const SizedBox(height: 8),
            ],
            const Text(S.m5Sensors, style: Design.foot),
          ],
        );
      },
    );
  }
}

class WatchWorkoutPanel extends StatefulWidget {
  const WatchWorkoutPanel({super.key, this.showStatus = true});

  final bool showStatus;

  @override
  State<WatchWorkoutPanel> createState() => _WatchWorkoutPanelState();
}

class _WatchWorkoutPanelState extends State<WatchWorkoutPanel> {
  Future<void> _send(AtletaController store, WatchAction action) async {
    try {
      await store.controlWatch(action);
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(S.m5ControlFailed)));
      }
    }
  }

  Future<void> _discard(AtletaController store, WatchDraft draft) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(S.m5DiscardDraft),
        content: const Text(S.m5DiscardQuestion),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(S.remove),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await store.discardWatch(draft.id);
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(S.failed)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AtletaScope.of(context);
    final draft = store.data.watchDraft;
    return ListenableBuilder(
      listenable: store.watch,
      builder: (context, _) {
        if (draft != null) return _activeCard(context, store, draft);
        final watch = store.watch;
        final packet = watch.latest;
        final canStart = watch.canControl && store.data.session == null;
        final canImport =
            packet != null &&
            packet.token == 0 &&
            !packet.running &&
            packet.activeSeconds > 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showStatus)
              if (!watch.connected)
                CompactTile(
                  title: store.data.watchLink == null
                      ? S.connectM5
                      : S.m5Reconnect,
                  icon: Icons.watch_outlined,
                  accent: Palette.lime,
                  radius: 15,
                  onTap: () => showWatchConnection(context),
                )
              else
                const WatchStatusTile(),
            if (canStart) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                style: Design.dashboardButton,
                onPressed: store.watchBusy
                    ? null
                    : () => _send(store, WatchAction.start),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text(S.m5Start),
              ),
            ],
            if (canImport) ...[
              if (watch.canControl)
                const Text(S.m5ResumeOnWatch, style: Design.foot),
              TextButton(
                onPressed: () => _saveWatch(context, store, packet),
                child: const Text(S.m5Save),
              ),
            ],
            if (widget.showStatus && watch.connected && !watch.canControl)
              const Text(S.m5Legacy, style: Design.foot),
          ],
        );
      },
    );
  }

  Widget _activeCard(
    BuildContext context,
    AtletaController store,
    WatchDraft draft,
  ) {
    final watch = store.watch;
    final latest = watch.latest;
    final same = latest?.token == draft.token;
    final saved = draft.result;
    final packet = saved ?? watch.latestFor(draft.token);
    final stats = packet?.totals(store.data.profile);
    final paused = same && !latest!.running && !latest.finished;
    final seconds = packet == null
        ? S.noValue
        : S.stopwatch(watch.activeSecondsForDisplay(packet));
    final status = switch ((saved, watch.connected, same)) {
      (final result?, _, _) when result.finished => S.m5Stopped,
      (_, false, _) => S.lostConnection,
      (_, true, false) when latest == null => S.m5Waiting,
      _ => S.m5Connected,
    };
    return DashboardPanel(
      padding: const EdgeInsets.fromLTRB(16, 17, 16, 21),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Icon(
                  Icons.circle,
                  size: 10,
                  color: watch.connected ? Palette.lime : Palette.muted,
                ),
                Text(
                  status,
                  style: Design.foot.copyWith(
                    color: Palette.text,
                    fontSize: 14,
                  ),
                ),
                if (paused) Text('· ${S.paused}', style: Design.foot),
              ],
            ),
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              const Icon(Icons.directions_walk_rounded, color: Palette.lime),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  S.activityName(draft.activity),
                  style: Design.section.copyWith(fontSize: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          FittedBox(
            key: const ValueKey('m5-live-clock'),
            fit: BoxFit.scaleDown,
            child: Text(
              seconds,
              style: Design.metric.copyWith(
                fontFamily: Design.mono,
                fontSize: 64,
              ),
            ),
          ),
          const SizedBox(height: 21),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _WatchValue(
                    stats?.steps == null ? S.noValue : S.number(stats!.steps!),
                    S.m5Steps,
                  ),
                ),
                const VerticalDivider(width: 19, color: Color(0x557A9377)),
                Expanded(
                  child: _WatchValue(
                    stats?.distanceKm == null
                        ? S.noValue
                        : S.kilometers(stats!.distanceKm!),
                    S.distance,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          if (saved != null) ...[
            if (saved.activeSeconds > 0)
              FilledButton(
                style: Design.dashboardButton,
                onPressed: () =>
                    _saveWatch(context, store, saved, draft: draft),
                child: const Text(S.m5Save),
              )
            else
              const Text(S.m5InvalidTime, style: Design.foot),
            TextButton(
              onPressed: () => _discard(store, draft),
              child: const Text(S.m5DiscardDraft),
            ),
          ] else if (!watch.connected) ...[
            if (widget.showStatus)
              FilledButton(
                style: Design.dashboardButton,
                onPressed: () => showWatchConnection(context),
                child: const Text(S.m5Reconnect),
              ),
            TextButton(
              onPressed: store.watchBusy ? null : () => _discard(store, draft),
              child: const Text(S.m5DiscardDraft),
            ),
          ] else if (same)
            _sessionButtons(store, latest!)
          else if (watch.canControl && latest != null) ...[
            FilledButton.icon(
              style: Design.dashboardButton,
              onPressed: store.watchBusy
                  ? null
                  : () => _send(store, WatchAction.start),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text(S.m5Start),
            ),
            TextButton(
              onPressed: store.watchBusy ? null : () => _discard(store, draft),
              child: const Text(S.m5DiscardDraft),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sessionButtons(AtletaController store, WatchReading current) {
    final available = store.watch.canControl && !store.watchBusy;
    if (current.finished) {
      return FilledButton(
        style: Design.dashboardButton,
        onPressed: available ? () => _send(store, WatchAction.finish) : null,
        child: const Text(S.m5Save),
      );
    }
    final toggle = FilledButton.icon(
      style: Design.dashboardButton.copyWith(
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 9),
        ),
      ),
      onPressed: available
          ? () => _send(
              store,
              current.running ? WatchAction.pause : WatchAction.resume,
            )
          : null,
      icon: Icon(
        current.running ? Icons.pause_rounded : Icons.play_arrow_rounded,
      ),
      label: Text(
        current.running ? S.pause : S.resume,
        textAlign: TextAlign.center,
      ),
    );
    final finish = OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: Palette.text,
        side: const BorderSide(color: Palette.axis),
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 9),
      ),
      onPressed: available ? () => _send(store, WatchAction.finish) : null,
      icon: const Icon(CupertinoIcons.stop, size: 18),
      label: const Text(S.finish, textAlign: TextAlign.center),
    );
    return LayoutBuilder(
      builder: (context, box) {
        final textSize = MediaQuery.textScalerOf(context).scale(16);
        if (box.maxWidth < 18 * textSize) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [toggle, const SizedBox(height: 8), finish],
          );
        }
        return Row(
          children: [
            Expanded(child: toggle),
            const SizedBox(width: 8),
            Expanded(child: finish),
          ],
        );
      },
    );
  }
}

class _WatchValue extends StatelessWidget {
  const _WatchValue(this.value, this.label);
  final String value, label;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          value,
          style: const TextStyle(
            fontFamily: Design.mono,
            fontWeight: FontWeight.w600,
            fontSize: 25,
          ),
        ),
      ),
      const SizedBox(height: 3),
      Text(
        label,
        textAlign: TextAlign.center,
        style: Design.foot.copyWith(fontSize: 14),
      ),
    ],
  );
}

Widget _activities(String activity, ValueChanged<String> onChange) =>
    DropdownButtonFormField<String>(
      initialValue: activity,
      isExpanded: true,
      decoration: const InputDecoration(labelText: S.activity),
      items: [
        for (final type in S.exerciseList)
          DropdownMenuItem(value: type, child: Text(S.activityName(type))),
      ],
      onChanged: (value) {
        if (value != null) onChange(value);
      },
    );

Future<void> _saveWatch(
  BuildContext context,
  AtletaController store,
  WatchReading result, {
  WatchDraft? draft,
}) async {
  final link = store.data.watchLink;
  if (link == null) return;
  var activity = draft?.activity ?? S.exerciseList.first;
  var start =
      draft?.started.toLocal() ??
      store.now().toLocal().subtract(Duration(seconds: result.activeSeconds));
  var notes = '';
  int? effort;
  final stats = result.totals(store.data.profile);
  await sheet<void>(
    context,
    (_) => StatefulBuilder(
      builder: (context, setState) => EntryForm(
        title: S.m5Save,
        fields: [
          _activities(activity, (value) => activity = value),
          if (draft == null)
            DateField(
              label: S.startTime,
              value: start,
              now: store.now(),
              withTime: true,
              onChanged: (value) => setState(() => start = value),
            ),
          Text(
            '${S.durationLabel(result.activeSeconds)} · ${stats.steps ?? S.noValue} ${S.stepsUnit}',
            style: Design.body,
          ),
          EffortField(value: effort, onChanged: (value) => effort = value),
          input(
            label: S.optionalNotes,
            onChange: (value) => notes = value,
            lines: 3,
            maxLength: 500,
          ),
        ],
        onSave: () async {
          final now = store.now();
          if (start.isAfter(now)) throw const ValidationIssue(S.future);
          final id =
              draft?.id ??
              [
                'm5',
                link.deviceId,
                dayKey(start),
                result.activeSeconds,
                result.steps,
              ].join('|');
          await store.saveWatchWorkout(
            Workout(
              id: id,
              activity: activity,
              start: start,
              seconds: result.activeSeconds,
              effort: effort,
              notes: notes.trim(),
              origin: Origin.m5,
              source: link.name,
              created: now,
              updated: now,
              watchStats: stats,
            ),
            draft?.id,
          );
        },
      ),
    ),
  );
}
