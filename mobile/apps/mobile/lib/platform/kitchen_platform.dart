import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'calendar_export.dart';
import 'platform_result.dart';
import 'companion_snapshot.dart';

class KitchenPlatform {
  KitchenPlatform({MethodChannel? channel, FlutterTts? speech})
      : channel = channel ?? const MethodChannel('app.crispycrust/kitchen'),
        speech = speech ?? FlutterTts();
  final MethodChannel channel;
  final FlutterTts speech;

  Future<CapabilityResult<bool>> publishCompanion(CompanionTaskSnapshot snapshot) async {
    try {
      final result = await channel.invokeMapMethod<String, dynamic>('publishCompanion', {'snapshot': snapshot.toJson()});
      if (result?['widget'] == true) { return const CapabilityResult.available(true,
        'Task snapshot sent to installed widget. Watch transport is not yet connected.'); }
      return const CapabilityResult(CapabilityStatus.unsupported, 'Native companion transport unavailable.');
    } on MissingPluginException {
      return const CapabilityResult(CapabilityStatus.unsupported, 'Native companion transport unavailable.');
    } on PlatformException {
      return const CapabilityResult(CapabilityStatus.failed, 'Could not update companion status. Open the app for current state.');
    }
  }

  Future<CapabilityResult<bool>> setKeepAwake(bool enabled) async {
    try { await channel.invokeMethod<void>('setKeepAwake', {'enabled': enabled});
      return CapabilityResult.available(enabled); }
    on MissingPluginException { return const CapabilityResult(CapabilityStatus.unsupported, 'Keep-awake is unavailable on this platform.'); }
    on PlatformException { return const CapabilityResult(CapabilityStatus.failed, 'Could not change screen-awake state.'); }
  }

  /// Native extraction returns only dates. Calendar event titles never cross this channel.
  Future<CapabilityResult<List<BusyBlock>>> readBusy(DateTime start, DateTime end) async {
    if (!end.isAfter(start) || end.difference(start) > const Duration(days: 31)) {
      throw ArgumentError('Busy import requires a positive range of at most 31 days');
    }
    try {
      final value = await channel.invokeMapMethod<String, dynamic>('readBusy',
        {'start': start.toUtc().millisecondsSinceEpoch, 'end': end.toUtc().millisecondsSinceEpoch});
      if (value?['status'] == 'denied') { return const CapabilityResult(
        CapabilityStatus.denied, 'Calendar access is off. Enter availability manually.'); }
      if (value?['status'] != 'available') { return const CapabilityResult(
        CapabilityStatus.failed, 'Calendar did not return a usable response. Enter availability manually.'); }
      final rows = (value?['blocks'] as List? ?? []).cast<Map>();
      final blocks = rows.map((r) => BusyBlock(
        start: DateTime.fromMillisecondsSinceEpoch(r['start'] as int, isUtc: true),
        end: DateTime.fromMillisecondsSinceEpoch(r['end'] as int, isUtc: true))).toList();
      return CapabilityResult.available(blocks);
    } on MissingPluginException {
      return const CapabilityResult(CapabilityStatus.unsupported, 'Calendar import is unavailable. Enter availability manually.');
    } on PlatformException {
      return const CapabilityResult(CapabilityStatus.failed, 'Calendar could not be read. Your existing plan is unchanged.');
    }
  }

  Future<CapabilityResult<bool>> speak(String text) async {
    try {
      await speech.stop();
      await speech.setSpeechRate(0.45);
      await speech.speak(text);
      return const CapabilityResult.available(true);
    } on MissingPluginException {
      return const CapabilityResult(CapabilityStatus.unsupported, 'Read-aloud is unavailable. Written instructions remain available.');
    } on PlatformException {
      return const CapabilityResult(CapabilityStatus.failed, 'Could not start read-aloud.');
    }
  }
  Future<void> stopSpeaking() async { await speech.stop(); }
}
