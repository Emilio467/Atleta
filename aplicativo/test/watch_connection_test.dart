import 'dart:typed_data';

import 'package:atleta/core/controller.dart';
import 'package:atleta/core/m5.dart';
import 'package:atleta/core/strings.dart';
import 'package:atleta/data/repository.dart';
import 'package:atleta/data/watch_connection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart' show newDatabaseFactoryMemory;
import 'package:universal_ble/universal_ble.dart';

import 'flows_test.dart' as flow;

void main() {
  test(
    'M5 fills one display second between readings and stops on pause',
    () async {
      final ble = FakeM5Ble();
      UniversalBle.setInstance(ble);
      final watch = WatchConnection();
      await watch.connect(const WatchLink(FakeM5Ble.id, 'Atleta-M5'));

      void expectTime(int confirmed, int displayed) {
        final reading = watch.latest!;
        expect(reading.activeSeconds, confirmed);
        expect(watch.activeSecondsForDisplay(reading), displayed);
      }

      expectTime(20, 20);
      const afterTick = Duration(milliseconds: 1100);
      await Future<void>.delayed(afterTick);
      expectTime(20, 21);

      // A duplicate packet must not reset the intermediate display tick.
      ble.report(20);
      await Future<void>.delayed(Duration.zero);
      expectTime(20, 21);

      ble.report(22);
      await Future<void>.delayed(Duration.zero);
      expectTime(22, 22);
      await Future<void>.delayed(afterTick);
      expectTime(22, 23);

      ble.report(22, running: false);
      await Future<void>.delayed(afterTick);
      expectTime(22, 22);

      ble.report(22);
      await Future<void>.delayed(afterTick);
      expectTime(22, 23);

      ble.report(24, running: false, finished: true);
      await Future<void>.delayed(afterTick);
      expectTime(24, 24);

      await watch.disconnect();
      expect(watch.latest, isNull);
      watch.dispose();
    },
  );

  test(
    'M5 connects at zero, keeps paused activity, and archives on a new link',
    () async {
      final ble = FakeM5Ble();
      UniversalBle.setInstance(ble);
      final db = await newDatabaseFactoryMemory().openDatabase('m5-play');
      final store = AtletaController(AtletaRepository(db));
      addTearDown(() async {
        await store.watch.disconnect();
        store.dispose();
        await db.close();
      });
      await store.initialize();
      const link = WatchLink(FakeM5Ble.id, 'Atleta-M5');
      await store.linkWatch(link);
      final draft = store.data.watchDraft!;
      expect(draft.activity, S.otherActivity);
      expect(store.watch.latest!.token, draft.token);
      expect(store.watch.latest!.running, isTrue);
      expect(store.watch.latest!.activeSeconds, 0);
      expect(ble.commands, [WatchAction.start]);

      await store.controlWatch(WatchAction.pause);
      expect(store.watch.latest!.running, isFalse);
      await store.watch.disconnect();
      await store.linkWatch(link);
      expect(store.data.watchDraft!.id, draft.id);
      expect(store.watch.latest!.running, isFalse);
      expect(store.watch.latest!.activeSeconds, 20);
      await store.controlWatch(WatchAction.resume);
      expect(store.watch.latest!.running, isTrue);
      await store.controlWatch(WatchAction.finish);
      expect(store.data.watchDraft!.result!.finished, isTrue);
      await expectLater(
        store.controlWatch(WatchAction.start),
        throwsA(isA<WatchSessionMismatch>()),
      );
      expect(store.data.watchDraft!.id, draft.id);
      expect(ble.commands, WatchAction.values);

      await store.watch.disconnect();
      await store.linkWatch(link);
      expect(store.data.workouts.single.id, draft.id);
      expect(store.data.workouts.single.seconds, 20);
      expect(store.data.watchDraft!.id, isNot(draft.id));
      expect(store.watch.latest!.activeSeconds, 0);
      expect(ble.commands, [...WatchAction.values, WatchAction.start]);
    },
  );

  testWidgets('Hoje connects and opens the M5 controls in Treinos', (
    tester,
  ) async {
    final ble = FakeM5Ble();
    UniversalBle.setInstance(ble);
    final store = await flow.loadApp(tester);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('today-watch-action')));
      await tester.pumpAndSettle();
      expect(find.text(S.m5Searching), findsOneWidget);
      await Future<void>.delayed(const Duration(milliseconds: 4300));
    });
    await tester.pumpAndSettle();
    expect(
      ble.commands,
      [WatchAction.start],
      reason:
          [
                S.m5Searching,
                S.m5Connecting,
                S.m5Failed,
                S.m5None,
                S.m5AutoStartFailed,
              ]
              .where((message) => find.text(message).evaluate().isNotEmpty)
              .join(' | '),
    );
    expect(find.text('00:00:00'), findsOneWidget);
    expect(flow.label(S.pause), findsOneWidget);
    expect(flow.label(S.finish), findsOneWidget);

    Future<void> command(String label) async {
      await tester.runAsync(() async {
        await tester.tap(flow.label(label));
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pumpAndSettle();
    }

    await command(S.pause);
    expect(flow.label(S.resume), findsOneWidget);
    await command(S.resume);
    expect(flow.label(S.pause), findsOneWidget);
    await command(S.finish);
    expect(store.data.watchDraft?.result?.finished, isTrue);
    expect(flow.label(S.m5Save), findsOneWidget);
    expect(ble.commands, WatchAction.values);
    await flow.tap(tester, flow.label(S.m5Save));
    await flow.effort(tester, 4);
    await flow.save(tester);
    expect(store.data.watchDraft, isNull);
    expect(store.data.workouts.single.seconds, 20);
    expect(flow.label(S.activityName(S.otherActivity)), findsOneWidget);
  });
}

class FakeM5Ble extends UniversalBlePlatform {
  static const id = '00:00:00:00:00:42';
  bool _connected = false;
  int _token = 1;
  late Uint8List _latest = _packet(20, running: true, finished: false);
  final commands = <WatchAction>[];

  @override
  Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  }) async {
    updateScanResult(
      BleDevice(deviceId: id, name: 'Atleta-M5', services: [m5ServiceUuid]),
    );
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<bool> isPaired(String deviceId) async => true;

  @override
  Future<void> connect(
    String deviceId, {
    Duration? connectionTimeout,
    bool autoConnect = false,
    ConnectionPlatformConfig? platformConfig,
  }) async {
    _connected = true;
    updateConnection(deviceId, true);
  }

  @override
  Future<void> disconnect(String deviceId) async {
    _connected = false;
    updateConnection(deviceId, false);
  }

  @override
  Future<BleConnectionState> getConnectionState(String deviceId) async =>
      _connected
      ? BleConnectionState.connected
      : BleConnectionState.disconnected;

  @override
  Future<List<BleService>> discoverServices(
    String deviceId,
    bool withDescriptors, {
    DiscoverServicesPlatformConfig? platformConfig,
  }) async => [
    BleService(m5ServiceUuid, [
      BleCharacteristic(m5SummaryUuid, [CharacteristicProperty.read], []),
      BleCharacteristic(m5SessionUuid, [
        CharacteristicProperty.read,
        CharacteristicProperty.notify,
      ], []),
      BleCharacteristic(m5ControlUuid, [CharacteristicProperty.write], []),
    ]),
  ];

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) async {}

  @override
  Future<Uint8List> readValue(
    String deviceId,
    String service,
    String characteristic, {
    Duration? timeout,
  }) async => _latest;

  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) async {
    final action = WatchAction.values.singleWhere((a) => a.code == value[0]);
    commands.add(action);
    _token = ByteData.sublistView(value).getUint32(1, Endian.little);
    report(
      action == WatchAction.start ? 0 : 20,
      running: action == WatchAction.start || action == WatchAction.resume,
      finished: action == WatchAction.finish,
    );
  }

  void report(
    int seconds, {
    bool running = true,
    bool finished = false,
    int? steps,
  }) {
    _latest = _packet(
      seconds,
      running: running,
      finished: finished,
      steps: steps,
    );
    updateCharacteristicValue(id, m5SessionUuid, _latest, null);
  }

  Uint8List _packet(
    int seconds, {
    required bool running,
    required bool finished,
    int? steps,
  }) =>
      (ByteData(18)
            ..setUint8(0, 2)
            ..setUint8(
              1,
              (running ? 1 : 0) | (steps != null ? 2 : 0) | (finished ? 16 : 0),
            )
            ..setUint32(2, steps ?? 0, Endian.little)
            ..setUint32(6, seconds, Endian.little)
            ..setUint32(13, _token, Endian.little))
          .buffer
          .asUint8List();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
