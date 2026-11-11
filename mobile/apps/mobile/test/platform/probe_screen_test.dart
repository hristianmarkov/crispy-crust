import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crispy_crust/data/app_store.dart';
import 'package:crispy_crust/platform/platform_result.dart';
import 'package:crispy_crust/platform/temperature_probe.dart';
import 'package:crispy_crust/screens/probe_screen.dart';

class _Store extends ChangeNotifier implements AppStore {
  @override
  List<AppRecord> records(String kind) => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DeniedProbe extends TemperatureProbeService {
  int requests = 0;
  @override
  Future<CapabilityResult<bool>> requestPermission() async {
    requests++;
    return const CapabilityResult(CapabilityStatus.denied,
      'Permission denied. Manual temperature entry remains available.');
  }
}

void main() {
  testWidgets('probe screen makes no permission request on open and preserves manual fallback', (tester) async {
    final store = _Store();
    final service = _DeniedProbe();
    await tester.pumpWidget(MaterialApp(home: ProbeScreen(store: store, service: service)));
    expect(service.requests, 0);
    expect(find.text('This probe measures'), findsOneWidget);
    final scan = find.text('Allow Bluetooth and scan for 10 seconds');
    await tester.ensureVisible(scan);
    await tester.tap(scan); await tester.pump();
    expect(service.requests, 1);
    expect(find.text('Permission denied. Manual temperature entry remains available.'), findsOneWidget);
    expect(find.text('Review and save this reading'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await service.dispose(); store.dispose();
  });
}
