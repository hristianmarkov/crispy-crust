import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import '../data/app_store.dart';
import '../platform/platform_result.dart';
import '../platform/sensor_reading.dart';
import '../platform/temperature_probe.dart';

class ProbeScreen extends StatefulWidget {
  const ProbeScreen({super.key, required this.store, this.service});
  final AppStore store;
  final TemperatureProbeService? service;
  @override
  State<ProbeScreen> createState() => _ProbeScreenState();
}

class _ProbeScreenState extends State<ProbeScreen> {
  late final TemperatureProbeService service;
  final devices = <String, DiscoveredDevice>{};
  final calibration = TextEditingController(text: '0');
  StreamSubscription<DiscoveredDevice>? scanner;
  StreamSubscription<CapabilityResult<TemperatureReading>>? subscription;
  Timer? scanTimeout;
  Timer? ageTicker;
  SensorRole role = SensorRole.dough;
  TemperatureReading? reading;
  String? selectedDevice;
  String? objectId;
  String message = 'Choose a measurement role, then allow a bounded scan.';
  double appliedOffset = 0;
  bool scanning = false;
  bool saving = false;
  String? lastSavedReading;

  @override
  void initState() {
    super.initState();
    service = widget.service ?? TemperatureProbeService();
    subscription = service.readings.listen((result) {
      if (!mounted) { return; }
      setState(() {
        message = result.message;
        if (result.isAvailable && result.value != null) {
          reading = result.value;
          message = 'Reading received. Confirm it before saving to a bake or starter.';
        }
      });
    });
    ageTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && reading != null) { setState(() {}); }
    });
    widget.store.addListener(refresh);
  }

  void refresh() { if (mounted) { setState(() {}); } }
  @override
  void dispose() {
    widget.store.removeListener(refresh);
    scanTimeout?.cancel(); ageTicker?.cancel();
    unawaited(scanner?.cancel()); unawaited(subscription?.cancel());
    if (widget.service == null) { unawaited(service.dispose()); }
    calibration.dispose(); super.dispose();
  }

  Future<void> stopScan() async {
    scanTimeout?.cancel(); await scanner?.cancel(); scanner = null;
    if (mounted) { setState(() => scanning = false); }
  }

  Future<void> scan() async {
    await stopScan();
    try {
      final permission = await service.requestPermission();
      if (!mounted) { return; }
      if (!permission.isAvailable) { setState(() => message = permission.message); return; }
      setState(() { scanning = true; devices.clear(); message = 'Scanning for the SIG Environmental Sensing service for 10 seconds…'; });
      scanner = service.scan().listen((device) {
        if (mounted) { setState(() => devices[device.id] = device); }
      }, onError: (Object _) async {
        await stopScan();
        if (mounted) { setState(() => message = 'Scan failed. Check Bluetooth is on. Manual temperature entry remains available.'); }
      });
      scanTimeout = Timer(const Duration(seconds: 10), () async {
        await stopScan();
        if (mounted) { setState(() => message = devices.isEmpty
          ? 'No compatible service found. A retail probe may use an unsupported proprietary protocol.'
          : 'Scan finished. Choose a device and wait for an actual reading.'); }
      });
    } catch (_) {
      await stopScan();
      if (mounted) { setState(() => message = 'Bluetooth is unavailable. Enter measurements manually in your bake or starter.'); }
    }
  }

  Future<void> connect(DiscoveredDevice device) async {
    final offset = double.tryParse(calibration.text.trim());
    if (offset == null || !offset.isFinite || offset.abs() > 10) {
      setState(() => message = 'Enter a calibration offset between -10 and 10°C.'); return;
    }
    await stopScan();
    if (!mounted) { return; }
    setState(() { selectedDevice = device.id; reading = null; appliedOffset = offset;
      message = 'Connecting to ${device.name.isEmpty ? device.id : device.name}. Waiting for an actual reading…'; });
    try { await service.connect(device.id, role, calibrationOffset: offset); }
    catch (_) { if (mounted) { setState(() { selectedDevice = null; message = 'Could not connect. Check the protocol and probe availability.'; }); } }
  }

  Future<void> disconnect() async {
    await service.disconnect();
    if (mounted) { setState(() { selectedDevice = null; reading = null; message = 'Disconnected. You can change role or calibration before connecting again.'; }); }
  }

  Future<void> save() async {
    final value = reading;
    if (value == null || value.isStaleAt(DateTime.now().toUtc()) || objectId == null || saving ||
        lastSavedReading == '$objectId:${value.observedAt.toIso8601String()}') { return; }
    final target = widget.store.find(objectId!);
    if (target == null) { setState(() => message = 'The selected bake or starter is no longer available.'); return; }
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Save this observation?'),
      content: Text('${value.celsius.toStringAsFixed(2)}°C · ${value.role.name}\n'
        '${target.text('name', 'Selected record')}\n'
        'Observed ${value.observedAt.toLocal()}\n'
        'Calibration offset: ${appliedOffset.toStringAsFixed(2)}°C\n\n'
        'This records a measurement. It does not mark the dough ready or change the accepted plan.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm and save'))]));
    if (confirmed != true || !mounted) { return; }
    setState(() => saving = true);
    try {
      await widget.store.save('observation', {'objectId': target.id,
        'temperature': value.celsius, 'sensorRole': value.role.name,
        'deviceId': value.deviceId, 'source': 'sensor_confirmed',
        'calibrationOffset': appliedOffset, 'occurredAt': value.observedAt.toUtc().toIso8601String(),
        'confirmedAt': DateTime.now().toUtc().toIso8601String()});
      if (mounted) { setState(() { lastSavedReading = '${target.id}:${value.observedAt.toIso8601String()}'; message = 'Observation saved locally with its original reading time. Your plan is unchanged.'; }); }
    } catch (_) {
      if (mounted) { setState(() => message = 'The observation could not be saved. Your reading remains here; retry.'); }
    } finally { if (mounted) { setState(() => saving = false); } }
  }

  @override
  Widget build(BuildContext context) {
    final targets = [...widget.store.records('bake'), ...widget.store.records('starter')];
    final selectedTarget = targets.any((r) => r.id == objectId) ? objectId : null;
    final value = reading;
    final stale = value?.isStaleAt(DateTime.now().toUtc()) ?? true;
    return Scaffold(appBar: AppBar(title: const Text('Temperature probe')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text('Measured, then confirmed.', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        const Text('This adapter supports the Bluetooth SIG Environmental Sensing temperature characteristic (0x181A / 0x2A6E). A specific retail model has not been physically validated. Proprietary probes may not work.'),
        const SizedBox(height: 8),
        const Text('Only use hardware rated for the measurement. The app does not establish food-contact or oven safety. The current supported reading range is -100 to 200°C.'),
        const SizedBox(height: 20),
        DropdownButtonFormField<SensorRole>(initialValue: role,
          decoration: const InputDecoration(labelText: 'This probe measures'),
          items: SensorRole.values.map((r) => DropdownMenuItem(value: r, child: Text(r.name))).toList(),
          onChanged: selectedDevice != null ? null : (r) { if (r != null) { setState(() => role = r); } }),
        const SizedBox(height: 12),
        TextField(controller: calibration, enabled: selectedDevice == null,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: const InputDecoration(labelText: 'Calibration offset (°C)', helperText: 'Applied only after reconnecting. Default is zero.')),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: selectedDevice != null ? null : (scanning ? stopScan : scan),
          icon: Icon(scanning ? Icons.stop : Icons.bluetooth_searching),
          label: Text(scanning ? 'Stop scan' : 'Allow Bluetooth and scan for 10 seconds')),
        const SizedBox(height: 12),
        Semantics(liveRegion: true, child: Text(message)),
        for (final device in devices.values) ListTile(contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.device_thermostat), title: Text(device.name.isEmpty ? 'Unnamed ESS device' : device.name),
          subtitle: Text('${device.id}\nSignal ${device.rssi} dBm · service advertised, model unverified'),
          trailing: selectedDevice == device.id ? const Icon(Icons.radio_button_checked) : null,
          onTap: selectedDevice != null ? null : () => connect(device)),
        if (selectedDevice != null) OutlinedButton(onPressed: disconnect, child: const Text('Disconnect')),
        const SizedBox(height: 24),
        if (value != null) ...[
          Text('${value.celsius.toStringAsFixed(2)}°C', style: Theme.of(context).textTheme.displaySmall),
          Text('${value.role.name} · ${stale ? 'STALE — do not treat as current' : 'Reading received'}'),
          Text('Observed ${value.observedAt.toLocal()} · age ${DateTime.now().toUtc().difference(value.observedAt).inSeconds}s'),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(initialValue: selectedTarget,
            decoration: const InputDecoration(labelText: 'Save to a bake or starter'),
            items: targets.map((r) => DropdownMenuItem(value: r.id, child: Text('${r.text('name', r.kind)} · ${r.kind}'))).toList(),
            onChanged: saving ? null : (id) => setState(() => objectId = id)),
          if (targets.isEmpty) const Text('Create a starter or bake before saving an observation.'),
          const SizedBox(height: 16),
          FilledButton(onPressed: stale || selectedTarget == null || saving || lastSavedReading == '$selectedTarget:${value.observedAt.toIso8601String()}' ? null : save,
            child: Text(saving ? 'Saving…' : 'Review and save this reading')),
        ],
        const SizedBox(height: 24),
        const Text('Nothing is logged automatically. A disconnect or old reading never triggers replanning. Manual temperature entry is always available from a starter or active bake.'),
      ]));
  }
}
