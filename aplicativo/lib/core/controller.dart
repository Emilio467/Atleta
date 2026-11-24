import 'package:flutter/foundation.dart';

import '../data/native_health.dart';
import '../data/repository.dart';
import '../data/watch_connection.dart';
import 'demo.dart';
import 'm5.dart';
import 'metrics.dart';
import 'models.dart';
import 'strings.dart';

class AtletaController extends ChangeNotifier {
  AtletaController(
    this.repository, {
    this.demo = false,
    DateTime Function()? clock,
    NativeHealth? health,
  }) : now = clock ?? DateTime.now,
       health = health ?? NativeHealth();

  final AtletaRepository repository;
  final bool demo;
  final DateTime Function() now;
  final NativeHealth health;
  final watch = WatchConnection();
  TrainingData data = const TrainingData();
  HealthStatus healthStatus = HealthStatus.checking;
  bool syncing = false;
  Future<void> _queue = Future.value();
  bool _closed = false;
  bool _watchBusy = false;

  DateTime get today => demo ? Demo.today : dayOf(now());
  bool get watchBusy => _watchBusy;
  LoadHistory? _history;
  LoadHistory get history => _history ??= LoadHistory(data.workouts, data.rest);
  Map<DateTime, double> get ratios => demo ? Demo.load : history.ratios;

  List<Workout> workoutsOn(DateTime day) =>
      data.workouts.where((w) => dayOf(w.start) == dayOf(day)).toList();
  ReadinessEntry? readinessOn(DateTime day) =>
      data.readiness.where((r) => r.day == dayOf(day)).firstOrNull;
  Future<void> initialize() async {
    if (demo) {
      await repository.putWorkout(Demo.workout);
      await repository.putReadiness(Demo.readiness);
    }
    data = await repository.read();
    notifyListeners();
  }

  Future<void> change(Future<void> Function() action) {
    final operation = _queue.then((_) async {
      if (_closed) return;
      await action();
      data = await repository.read();
      _history = null;
      if (!_closed) notifyListeners();
    });
    _queue = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  Future<void> saveWorkout(Workout workout) =>
      change(() => repository.putWorkout(workout));
  Future<void> setImportedEffort(String id, int effort) =>
      change(() => repository.setImportedEffort(id, effort, now()));
  Future<void> deleteWorkout(String id) =>
      change(() => repository.deleteWorkout(id));
  Future<void> clearWorkoutHistory() =>
      change(() => repository.clearWorkoutHistory(now()));
  Future<void> saveReadiness(ReadinessEntry entry) =>
      change(() => repository.putReadiness(entry));
  Future<void> saveProfile(AthleteProfile profile) =>
      change(() => repository.putProfile(profile));
  Future<void> saveRest(DateTime day, bool confirm) =>
      change(() => repository.putRest(day, confirm));

  Future<void> begin(String activity) => change(() async {
    final time = now();
    await repository.beginSession(
      Session(
        id: newId(),
        started: time,
        activeSince: time,
        activity: activity,
      ),
    );
  });
  Future<void> toggleSession() => change(() async {
    final session = data.session;
    if (session == null) return;
    final time = now();
    await repository.updateSession(
      session.activeSince == null ? session.resume(time) : session.pause(time),
    );
  });
  Future<void> finishSession(Workout workout) =>
      change(() => repository.finishSession(workout));

  Future<void> linkWatch(WatchLink link) => _runWatchOperation(() async {
    final newConnection =
        !watch.connected || data.watchLink?.deviceId != link.deviceId;
    await watch.connect(link);
    if (_closed || !watch.connected) return;
    try {
      await change(() => repository.putWatchLink(link));
    } catch (_) {
      await watch.disconnect();
      rethrow;
    }
    if (newConnection && !_closed && watch.canControl && data.session == null) {
      await _startWatchOnConnection(link);
    }
  });

  Future<void> _startWatchOnConnection(WatchLink link) async {
    try {
      final draft = data.watchDraft;
      final packet = watch.latest;
      if (draft != null) {
        final result =
            draft.result ??
            (packet != null && packet.token == draft.token && packet.finished
                ? packet
                : null);
        if (result == null || result.activeSeconds == 0) return;
        if (draft.result == null) {
          await change(() => repository.finishWatchDraft(draft.id, result));
        }
        final time = now();
        await saveWatchWorkout(
          Workout(
            id: draft.id,
            activity: draft.activity,
            start: draft.started,
            seconds: result.activeSeconds,
            origin: Origin.m5,
            source: link.name,
            created: time,
            updated: time,
            watchStats: result.totals(data.profile),
          ),
          draft.id,
        );
      }
      if (!_closed) await _controlWatch(WatchAction.start);
    } on Exception {
      throw const WatchAutoStartFailed();
    }
  }

  Future<void> forgetWatch() async {
    await change(() => repository.putWatchLink(null));
    await watch.disconnect();
  }

  Future<void> _beginWatch() async {
    final link = data.watchLink;
    if (link == null || !watch.canControl) throw const InvalidWatch();
    final id = newId();
    final code = int.parse(id.substring(0, 8), radix: 16);
    final draft = WatchDraft(
      id: id,
      token: code == 0 ? 1 : code,
      deviceId: link.deviceId,
      activity: S.otherActivity,
      started: now(),
    );
    await change(() => repository.beginWatchDraft(draft));
  }

  Future<void> _runWatchOperation(Future<void> Function() operation) async {
    if (_closed || _watchBusy) return;
    _watchBusy = true;
    notifyListeners();
    try {
      await operation();
    } finally {
      _watchBusy = false;
      if (!_closed) notifyListeners();
    }
  }

  Future<void> controlWatch(WatchAction action) =>
      _runWatchOperation(() => _controlWatch(action));

  Future<void> _controlWatch(WatchAction action) async {
    if (action == WatchAction.start && data.watchDraft == null) {
      await _beginWatch();
    }
    final draft = data.watchDraft;
    if (draft == null ||
        draft.result != null ||
        data.watchLink?.deviceId != draft.deviceId) {
      throw const WatchSessionMismatch();
    }
    if (action == WatchAction.start) {
      await change(() => repository.markWatchStart(draft.id, now()));
    }
    if (_closed) return;
    final confirmed = await watch.send(action, draft.token);
    if (action == WatchAction.finish) {
      await change(() => repository.finishWatchDraft(draft.id, confirmed));
    }
  }

  Future<void> discardWatch(String draftId) =>
      change(() => repository.discardWatchDraft(draftId));

  Future<void> saveWatchWorkout(Workout workout, String? draftId) =>
      change(() => repository.saveWatchWorkout(workout, draftId: draftId));

  Future<void> refreshStatus() async {
    if (syncing) return;
    try {
      healthStatus = demo ? HealthStatus.unsupported : await health.status();
      if (healthStatus == HealthStatus.ready &&
          await repository.healthLinkedElsewhere()) {
        healthStatus = HealthStatus.linkedElsewhere;
      }
    } on Exception {
      healthStatus = HealthStatus.failed;
    }
    if (!_closed) notifyListeners();
  }

  Future<void> sync({bool request = false}) async {
    if (_closed || demo || syncing || (!request && !data.syncEnabled)) return;
    syncing = true;
    healthStatus = HealthStatus.reading;
    notifyListeners();
    try {
      final available = await health.status();
      if (_closed) return;
      if (available != HealthStatus.ready) {
        healthStatus = available;
        return;
      }
      if (request) {
        if (await repository.healthLinkedElsewhere()) {
          throw const HealthAlreadyLinked();
        }
        if (_closed) return;
        await health.authorize();
        if (_closed) return;
        await change(() => repository.setSyncEnabled(true));
      }
      if (_closed) return;
      final time = now();
      final result = await health.read(time);
      if ({HealthStatus.synced, HealthStatus.empty}.contains(result.status)) {
        await change(() => repository.saveImport(result.data, time));
      }
      healthStatus = result.status;
    } on HealthAlreadyLinked {
      healthStatus = HealthStatus.linkedElsewhere;
    } on Exception {
      healthStatus = HealthStatus.failed;
    } finally {
      syncing = false;
      if (!_closed) notifyListeners();
    }
  }

  Future<void> stopImporting() =>
      change(() => repository.setSyncEnabled(false));

  void onResume() {
    if (_closed) return;
    notifyListeners();
    if (syncing) return;
    if (data.syncEnabled) {
      sync();
    } else {
      refreshStatus();
    }
  }

  @override
  void dispose() {
    _closed = true;
    watch.dispose();
    super.dispose();
  }
}

class WatchAutoStartFailed implements Exception {
  const WatchAutoStartFailed();
}
