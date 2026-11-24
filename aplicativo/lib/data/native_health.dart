import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:health/health.dart';

import '../core/models.dart';
import 'repository.dart';

enum HealthStatus {
  unsupported,
  checking,
  unavailable,
  installRequired,
  ready,
  reading,
  restricted,
  empty,
  synced,
  failed,
  linkedElsewhere,
}

class NativeHealth {
  NativeHealth({Health? plugin}) : _health = plugin ?? Health();
  final Health _health;
  bool _configured = false;
  bool get _android => defaultTargetPlatform == TargetPlatform.android;

  static const _types = [HealthDataType.WORKOUT];
  static const _access = [HealthDataAccess.READ];

  Future<HealthStatus> status() async {
    if (kIsWeb || (!_android && defaultTargetPlatform != TargetPlatform.iOS)) {
      return HealthStatus.unsupported;
    }
    if (!_configured) {
      await _health.configure();
      _configured = true;
    }
    if (!_android) {
      const channel = MethodChannel('br.com.atleta/health');
      return await channel.invokeMethod<bool>('isAvailable') == true
          ? HealthStatus.ready
          : HealthStatus.unavailable;
    }
    return switch (await _health.getHealthConnectSdkStatus()) {
      HealthConnectSdkStatus.sdkAvailable => HealthStatus.ready,
      HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired =>
        HealthStatus.installRequired,
      _ => HealthStatus.unavailable,
    };
  }

  Future<void> install() => _health.installHealthConnect();

  Future<void> authorize() async {
    await _health.requestAuthorization(_types, permissions: _access);
  }

  Future<({HealthStatus status, HealthImport data})> read(DateTime now) async {
    const empty = HealthImport([]);
    final availability = await status();
    if (availability != HealthStatus.ready) {
      return (status: availability, data: empty);
    }

    // HealthKit deliberately does not expose a read grant.
    if (_android &&
        await _health.hasPermissions(_types, permissions: _access) != true) {
      return (status: HealthStatus.restricted, data: empty);
    }
    final points = await _health.getHealthDataFromTypes(
      types: _types,
      startTime: now.subtract(const Duration(days: 30)),
      endTime: now,
    );

    final origin = _android ? Origin.healthConnect : Origin.healthKit;
    final workouts = <Workout>[];
    for (final point in points) {
      final from = point.dateFrom;
      final to = point.dateTo;
      final seconds = to.difference(from).inSeconds;
      final value = point.value;
      if (to.isAfter(now) || seconds <= 0 || value is! WorkoutHealthValue) {
        continue;
      }
      final identity = [
        origin.name,
        point.sourceId,
        point.type.name,
        point.uuid,
      ].join('|');
      final source = point.sourceName.isEmpty
          ? point.sourceId
          : point.sourceName;
      final activity = value.workoutActivityType.name
          .toLowerCase()
          .split('_')
          .map((word) => word[0].toUpperCase() + word.substring(1))
          .join(' ');
      workouts.add(
        Workout(
          id: point.uuid.isEmpty ? '$identity|$from|$to' : identity,
          activity: activity,
          start: from,
          seconds: seconds,
          origin: origin,
          source: source,
          created: now,
          updated: now,
        ),
      );
    }
    return (
      status: workouts.isEmpty ? HealthStatus.empty : HealthStatus.synced,
      data: HealthImport(workouts),
    );
  }
}
