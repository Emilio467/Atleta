import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import '../core/m5.dart';

class WatchConnection extends ChangeNotifier {
  static Future<void> _release = Future.value();
  static const _timeout = Duration(seconds: 9);
  static const _pairTimeout = Duration(seconds: 40);
  static final _filter = ScanFilter(withServices: const [m5ServiceUuid]);
  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  StreamSubscription<bool>? _connectionEvents;
  StreamSubscription<Uint8List>? _values;
  Timer? _expiry, _displayTick;
  int _displayOffset = 0;
  String? _deviceId, _summary;
  bool _disposed = false, _connected = false, _scanning = false;
  bool _canControl = false;
  bool _pairing = false;
  DateTime? _received;
  WatchReading? _reading;

  bool get connected => _connected;
  bool get canControl => _connected && _canControl;
  bool get pairing => _pairing;
  WatchReading? get latest =>
      _connected &&
          _received != null &&
          DateTime.now().difference(_received!) < _timeout
      ? _reading
      : null;

  WatchReading? latestFor(int token) =>
      _reading?.token == token ? _reading : null;

  int activeSecondsForDisplay(WatchReading reading) =>
      reading.activeSeconds +
      (identical(reading, _reading) ? _displayOffset : 0);

  Future<List<WatchLink>> discover() async {
    if (kIsWeb) {
      // Browsers require the native picker to be started by the tap itself.
      return [_link(await UniversalBle.requestDevice(scanFilter: _filter))];
    }
    await _release;
    if (_disposed) return const [];
    final visible = <String, WatchLink>{};
    final subscription = UniversalBle.scanStream.listen((device) {
      visible[device.deviceId] = _link(device);
    });
    _scanning = true;
    try {
      await UniversalBle.startScan(
        scanFilter: _filter,
        skipDuplicates: true,
        platformConfig: PlatformConfig(
          android: AndroidOptions(
            legacy: true,
            requestLocationPermission: false,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(seconds: 4));
      return visible.values.toList();
    } finally {
      await subscription.cancel();
      if (_scanning) {
        _scanning = false;
        await UniversalBle.stopScan();
      }
    }
  }

  WatchLink _link(BleDevice device) => WatchLink(
    device.deviceId,
    device.name?.trim().isNotEmpty == true ? device.name!.trim() : 'Atleta-M5',
  );

  Future<void> connect(WatchLink link) async {
    await _release;
    if (_disposed) return;
    if (_deviceId == link.deviceId && _connected) return;
    await disconnect();
    if (_disposed) return;
    final id = link.deviceId;
    // Let Android initiate pairing before GATT connects. Otherwise the M5's
    // security request arrives first and Android can ask for consent twice.
    if (_isAndroid) await _pairOnAndroid(id);
    if (_disposed) return;
    _deviceId = id;
    try {
      await UniversalBle.connect(id, timeout: const Duration(seconds: 15));
      if (_disposed || _deviceId != id) {
        await _disconnectDevice(id);
        return;
      }
      var linkLost = false;
      _connectionEvents = UniversalBle.connectionStream(id).listen((connected) {
        if (_deviceId != id || connected) return;
        linkLost = true;
        _connected = false;
        _displayTick?.cancel();
        _changed();
      });
      final services = await UniversalBle.discoverServices(
        id,
        timeout: _timeout,
      );
      final m5 = services
          .where((s) => s.uuid.toLowerCase() == m5ServiceUuid)
          .firstOrNull;
      final ids =
          m5?.characteristics.map((c) => c.uuid.toLowerCase()).toSet() ??
          <String>{};
      if (!ids.contains(m5SummaryUuid)) throw const InvalidWatch();
      _canControl = ids.contains(m5SessionUuid) && ids.contains(m5ControlUuid);
      if (linkLost) throw const WatchConnectionLost();
      final summary = _canControl ? m5SessionUuid : m5SummaryUuid;
      _summary = summary;
      _values = UniversalBle.characteristicValueStream(id, summary).listen((
        bytes,
      ) {
        if (_deviceId == id) _accept(bytes);
      });
      await UniversalBle.subscribeNotifications(
        id,
        m5ServiceUuid,
        summary,
        timeout: _timeout,
      );
      _accept(
        await UniversalBle.read(id, m5ServiceUuid, summary, timeout: _timeout),
      );
      if (_disposed || _deviceId != id) {
        await _disconnectDevice(id);
        return;
      }
      if (linkLost) throw const WatchConnectionLost();
      _connected = true;
      _changed();
    } catch (_) {
      if (_deviceId == id) await disconnect();
      rethrow;
    }
  }

  Future<void> _pairOnAndroid(String id) async {
    if (await UniversalBle.isPaired(id, timeout: _timeout) == true) return;
    if (_disposed) return;
    _pairing = true;
    _changed();
    try {
      await UniversalBle.pair(id, timeout: _pairTimeout);
    } on Exception {
      throw const WatchPairingFailed();
    } finally {
      _pairing = false;
      _changed();
    }
  }

  Future<WatchReading> send(WatchAction action, int token) async {
    final id = _deviceId;
    final summary = _summary;
    if (!canControl || id == null || summary == null) {
      throw const InvalidWatch();
    }
    await UniversalBle.write(
      id,
      m5ServiceUuid,
      m5ControlUuid,
      action.encode(token),
      timeout: const Duration(seconds: 18),
    );
    for (var attempt = 0; attempt < 8; attempt++) {
      if (!_connected || _deviceId != id) break;
      final bytes = await UniversalBle.read(
        id,
        m5ServiceUuid,
        summary,
        timeout: _timeout,
      );
      _accept(bytes);
      final packet = WatchReading.decode(bytes);
      if (packet != null && action.confirmedBy(packet, token)) return packet;
      await Future<void>.delayed(const Duration(milliseconds: 420));
    }
    throw const WatchNoConfirmation();
  }

  void _accept(Uint8List bytes) {
    final result = WatchReading.decode(bytes);
    if (result == null || _disposed) return;
    final previous = latest;
    if (previous?.activeSeconds != result.activeSeconds ||
        previous?.running != result.running ||
        previous?.finished != result.finished ||
        previous?.token != result.token) {
      _displayTick?.cancel();
      _displayOffset = 0;
      if (result.running && !result.finished) {
        // Fill the missing second between the M5's two-second readings.
        _displayTick = Timer(const Duration(seconds: 1), () {
          _displayOffset = 1;
          _changed();
        });
      }
    }
    _reading = result;
    _received = DateTime.now();
    _expiry?.cancel();
    _expiry = Timer(_timeout, _changed);
    _changed();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> disconnect() async {
    final id = _deviceId;
    _deviceId = null;
    _summary = null;
    _connected = false;
    _canControl = false;
    _received = null;
    _reading = null;
    _expiry?.cancel();
    _displayTick?.cancel();
    _displayOffset = 0;
    final events = _connectionEvents;
    final values = _values;
    _connectionEvents = null;
    _values = null;
    _changed();
    await events?.cancel();
    await values?.cancel();
    if (id != null) await _disconnectDevice(id);
  }

  Future<void> _disconnectDevice(String id) async {
    if (_isAndroid) {
      // Android's plugin can emit a delayed disconnect event for an already
      // closed GATT client, which can abort the next connection to this ID.
      try {
        if (await UniversalBle.getConnectionState(id, timeout: _timeout) ==
            BleConnectionState.disconnected) {
          return;
        }
      } on Exception {
        // Still attempt to close the GATT link if its state is unavailable.
      }
    }
    try {
      await UniversalBle.disconnect(id, timeout: const Duration(seconds: 6));
    } on Exception {
      // The GATT link may already be closed by the watch or OS.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _displayTick?.cancel();
    _release = _release.then((_) async {
      if (_scanning) {
        _scanning = false;
        try {
          await UniversalBle.stopScan();
        } on Exception {
          // The adapter may already be off.
        }
      }
      await disconnect();
    });
    super.dispose();
  }
}

class InvalidWatch implements Exception {
  const InvalidWatch();
}

class WatchNoConfirmation implements Exception {
  const WatchNoConfirmation();
}

class WatchPairingFailed implements Exception {
  const WatchPairingFailed();
}

class WatchConnectionLost implements Exception {
  const WatchConnectionLost();
}
