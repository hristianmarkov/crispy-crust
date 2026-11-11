import 'dart:typed_data';

enum SensorRole { room, dough, fridge, oven }

class TemperatureReading {
  const TemperatureReading({required this.deviceId, required this.role,
    required this.celsius, required this.observedAt});
  final String deviceId;
  final SensorRole role;
  final double celsius;
  final DateTime observedAt;
  bool isStaleAt(DateTime now, {Duration maximumAge = const Duration(minutes: 5)}) =>
    now.difference(observedAt) > maximumAge || observedAt.isAfter(now.add(const Duration(minutes: 1)));
}

/// Bluetooth SIG Environmental Sensing Service 0x181A temperature 0x2A6E:
/// signed 16-bit little endian, resolution 0.01 Celsius.
TemperatureReading decodeEnvironmentalTemperature(List<int> bytes, {
  required String deviceId, required SensorRole role, required DateTime receivedAt,
  double calibrationOffset = 0,
}) {
  if (bytes.length != 2) throw const FormatException('Temperature requires two bytes');
  if (!calibrationOffset.isFinite || calibrationOffset.abs() > 10) {
    throw ArgumentError('Calibration offset outside reviewed bounds');
  }
  final value = ByteData.sublistView(Uint8List.fromList(bytes)).getInt16(0, Endian.little);
  final celsius = value / 100 + calibrationOffset;
  if (celsius < -100 || celsius > 200) throw const FormatException('Sensor reading outside supported range');
  return TemperatureReading(deviceId: deviceId, role: role,
    celsius: celsius, observedAt: receivedAt.toUtc());
}
