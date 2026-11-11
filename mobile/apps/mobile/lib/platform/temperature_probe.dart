import 'dart:async';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'platform_result.dart';
import 'sensor_reading.dart';

/// Implements only the published SIG Environmental Sensing service, not every
/// retail food probe. A model must pass a physical-device compatibility test.
class TemperatureProbeService {
  TemperatureProbeService({FlutterReactiveBle? ble}) : ble = ble ?? FlutterReactiveBle();
  final FlutterReactiveBle ble;
  static final serviceId = Uuid.parse('0000181a-0000-1000-8000-00805f9b34fb');
  static final temperatureId = Uuid.parse('00002a6e-0000-1000-8000-00805f9b34fb');
  StreamSubscription<ConnectionStateUpdate>? _connection;
  StreamSubscription<List<int>>? _readings;
  final _stream = StreamController<CapabilityResult<TemperatureReading>>.broadcast();
  Stream<CapabilityResult<TemperatureReading>> get readings => _stream.stream;
  TemperatureReading? latest;

  Future<CapabilityResult<bool>> requestPermission() async {
    final permissions = await [Permission.bluetoothScan, Permission.bluetoothConnect].request();
    final allowed = permissions.values.every((p) => p.isGranted || p.isLimited);
    return allowed ? const CapabilityResult.available(true) : const CapabilityResult(
      CapabilityStatus.denied, 'Bluetooth access is off. Manual temperature entry remains available.');
  }

  Stream<DiscoveredDevice> scan() => ble.scanForDevices(withServices: [serviceId], scanMode: ScanMode.lowLatency);

  Future<void> connect(String deviceId, SensorRole role, {double calibrationOffset = 0}) async {
    await disconnect();
    _connection = ble.connectToDevice(id: deviceId, connectionTimeout: const Duration(seconds: 15),
      servicesWithCharacteristicsToDiscover: {serviceId: [temperatureId]}).listen((state) {
      if (state.connectionState == DeviceConnectionState.connected) {
        _readings?.cancel();
        _readings = ble.subscribeToCharacteristic(QualifiedCharacteristic(deviceId: deviceId,
          serviceId: serviceId, characteristicId: temperatureId)).listen((bytes) {
          try {
            latest = decodeEnvironmentalTemperature(bytes, deviceId: deviceId,
              role: role, receivedAt: DateTime.now().toUtc(), calibrationOffset: calibrationOffset);
            _stream.add(CapabilityResult.available(latest!));
          } on FormatException {
            _stream.add(const CapabilityResult(CapabilityStatus.failed, 'The probe sent an unsupported temperature value. Enter it manually.'));
          }
        }, onError: (Object _) { _stream.add(const CapabilityResult(CapabilityStatus.failed,
          'Temperature stream interrupted. The last reading may be stale.')); });
      } else if (state.connectionState == DeviceConnectionState.disconnected) {
        _stream.add(const CapabilityResult(CapabilityStatus.failed,
          'Probe disconnected. Check the age of the last reading or enter a new reading manually.'));
      }
    }, onError: (Object _) { _stream.add(const CapabilityResult(CapabilityStatus.failed,
      'Could not connect to this probe. Only documented compatible models are supported.')); });
  }

  Future<void> disconnect() async {
    await _readings?.cancel(); _readings = null;
    await _connection?.cancel(); _connection = null;
  }
  Future<void> dispose() async { await disconnect(); await _stream.close(); }
}
