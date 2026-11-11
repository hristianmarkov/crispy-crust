import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crispy_crust/data/app_store.dart';
import 'package:crispy_crust/screens/starter_insights_screen.dart';

class MemoryStarterStore extends AppStore {
  final rows=<AppRecord>[];int sequence=0;
  @override List<AppRecord> records(String kind)=>rows.where((r)=>r.kind==kind).toList();
  @override AppRecord? find(String id)=>rows.where((r)=>r.id==id).firstOrNull;
  @override Future<AppRecord> save(String kind,Map<String,dynamic> fields,{String? id}) async {
    final key=id??'record-${sequence++}';final before=find(key);rows.removeWhere((r)=>r.id==key);
    final value=AppRecord(id:key,kind:kind,fields:fields,updatedAt:DateTime.utc(2026,11,11),revision:(before?.revision??0)+1);rows.add(value);notifyListeners();return value;
  }
  @override Future<void> remove(String id) async {rows.removeWhere((r)=>r.id==id);notifyListeners();}
  @override List<Map<String,dynamic>> get recipes=>[];
  @override List<Map<String,dynamic>> get lessons=>[];
  @override List<Map<String,dynamic>> get guidance=>[];
  @override bool get beginnerMode=>true;
  @override bool get darkMode=>false;
  @override String get storageDescription=>'Stored on this device';
  @override dynamic preference(String key,[dynamic fallback])=>fallback;
  @override Future<void> setPreference(String key,dynamic value) async {}
  @override Future<AppRecord> createBake(Map<String,dynamic> recipe,{double scale=1,DateTime? serveAt,DateTime? startAt,Map<String,dynamic>? expectedSchedule})=>throw UnsupportedError('not used');
  @override Future<void> completeStep(String bakeId,{DateTime? occurredAt,int? expectedIndex})=>throw UnsupportedError('not used');
  @override Future<void> logFeed(String starterId,{required double seed,required double flour,required double water,DateTime? occurredAt})=>throw UnsupportedError('not used');
  @override Future<String> exportArchive()=>throw UnsupportedError('not used');
  @override Future<void> importArchive(String source)=>throw UnsupportedError('not used');
  @override Future<void> resetLocalData()=>throw UnsupportedError('not used');
}
Map<String,dynamic> conditions({double temperature=23,String mix='bread flour'})=>{'flourMixKey':mix,'hydrationPercent':100,'temperatureC':temperature,'storageMode':'counter'};
Future<void> evidence(MemoryStarterStore store,{int historicalFeeds=5,bool confirmed=true,bool linked=true}) async {
  await store.save('starter',{'name':'Matilda','flour':'Current renamed flour, not historical evidence','hydration':100,'storage':'counter'},id:'jar');
  for(var i=0;i<historicalFeeds;i++) {
    final fedAt=DateTime.utc(2026,11,1+i,8);
    await store.save('feed',{'starterId':'jar','seed':20,'flour':40,'water':40,'occurredAt':fedAt.toIso8601String()},id:'feed-$i');
    await store.save('observation',{'objectId':'jar',if(linked)'feedId':'feed-$i','peak':'observed','peakConfirmed':confirmed,'peakAt':fedAt.add(const Duration(hours:5)).toIso8601String(),'occurredAt':fedAt.add(const Duration(hours:5)).toIso8601String(),'contextConfirmed':true,'feedContext':conditions()},id:'peak-$i');
  }
  await store.save('feed',{'starterId':'jar','seed':20,'flour':40,'water':40,'occurredAt':'2026-11-11T08:00:00Z'},id:'latest-feed');
  await store.save('observation',{'objectId':'jar','feedId':'latest-feed','peak':'not_yet','contextConfirmed':true,'feedContext':conditions(),'occurredAt':'2026-11-11T09:00:00Z'},id:'latest-context');
}
void main() {
  test('five real comparable prior peaks produce an empirical window',() async {
    final store=MemoryStarterStore();await evidence(store);
    final result=analyseStarterEvidence(store,'jar',now:DateTime.utc(2026,11,11,10));
    expect(result.comparableCount,5);expect(result.estimate,isNotNull);expect(result.estimate!.personalized,isTrue);expect(result.estimate!.statisticallyCalibrated,isFalse);expect(result.estimate!.sourceRecordIds,hasLength(5));
    expect(result.estimate!.nominal,DateTime.utc(2026,11,11,13));store.dispose();
  });
  test('sparse history has no fabricated reviewed broad fallback',() async {
    final store=MemoryStarterStore();await evidence(store,historicalFeeds:4);
    final result=analyseStarterEvidence(store,'jar',now:DateTime.utc(2026,11,11,10));
    expect(result.estimate,isNull);expect(result.comparableCount,4);expect(result.explanation,contains('no time window is invented'));store.dispose();
  });
  test('legacy unlinked or unconfirmed peak claims never become comparable evidence',() async {
    final store=MemoryStarterStore();await evidence(store,linked:false);
    var result=analyseStarterEvidence(store,'jar',now:DateTime.utc(2026,11,11,10));expect(result.estimate,isNull);expect(result.comparableCount,0);
    store.rows.clear();await evidence(store,confirmed:false);
    result=analyseStarterEvidence(store,'jar',now:DateTime.utc(2026,11,11,10));expect(result.estimate,isNull);expect(result.comparableCount,0);store.dispose();
  });
  test('different flour and unknown representative temperature cannot narrow window',() async {
    final store=MemoryStarterStore();await evidence(store);
    final row=store.find('peak-0')!;await store.save('observation',{...row.fields,'feedContext':conditions(mix:'rye')},id:row.id);
    var result=analyseStarterEvidence(store,'jar',now:DateTime.utc(2026,11,11,10));expect(result.comparableCount,4);expect(result.estimate,isNull);
    final current=store.find('latest-context')!;await store.save('observation',{...current.fields,'feedContext':{...conditions(),'temperatureC':null}},id:current.id);
    result=analyseStarterEvidence(store,'jar',now:DateTime.utc(2026,11,11,10));expect(result.estimate,isNull);expect(result.explanation,contains('Confirm the actual conditions'));store.dispose();
  });
  test('conflicting peak times for one feed are excluded rather than averaged',() async {
    final store=MemoryStarterStore();await evidence(store);
    final first=store.find('peak-0')!;await store.save('observation',{...first.fields,'peakAt':'2026-11-01T14:00:00Z'},id:'conflicting-peak');
    final result=analyseStarterEvidence(store,'jar',now:DateTime.utc(2026,11,11,10));expect(result.comparableCount,4);expect(result.estimate,isNull);expect(result.excludedCount,2);store.dispose();
  });
  test('current-feed peak cannot train its own supposed prediction',() async {
    final store=MemoryStarterStore();await evidence(store,historicalFeeds:4);
    await store.save('observation',{'objectId':'jar','feedId':'latest-feed','peak':'observed','peakConfirmed':true,'peakAt':'2026-11-11T09:00:00Z','occurredAt':'2026-11-11T09:00:00Z','contextConfirmed':true,'feedContext':conditions()},id:'current-peak');
    final result=analyseStarterEvidence(store,'jar',now:DateTime.utc(2026,11,11,10));expect(result.comparableCount,4);expect(result.estimate,isNull);store.dispose();
  });
  test('travel cancels only matching jar reminders and never logs a feed',() async {
    final store=MemoryStarterStore();await store.save('starter',{'name':'Jar'},id:'jar');
    await store.save('timer',{'starterId':'jar','state':'running'},id:'jar-timer');await store.save('timer',{'starterId':'other-jar','state':'running'},id:'other-timer');await store.save('timer',{'bakeId':'bake','state':'running'},id:'bake-timer');
    await setStarterCareMode(store,'jar','travel');
    expect(store.find('jar-timer')!.text('state'),'canceled');expect(store.find('other-timer')!.text('state'),'running');expect(store.find('bake-timer')!.text('state'),'running');expect(store.records('feed'),isEmpty);
    await setStarterCareMode(store,'jar','counter');expect(store.find('jar-timer')!.text('state'),'canceled');store.dispose();
  });
  testWidgets('new jar shows honest insufficient-history and manual check controls',(tester) async {
    final store=MemoryStarterStore();await store.save('starter',{'name':'New jar','hydration':100,'flour':'Bread flour','storage':'counter'},id:'jar');
    await tester.pumpWidget(MaterialApp(home:StarterInsightsScreen(store:store,starterId:'jar')));
    expect(find.textContaining('No peak window can be inferred'),findsOneWidget);expect(find.text('Choose a manual check reminder'),findsOneWidget);
    expect(find.textContaining('statistically calibrated'),findsNothing);store.dispose();
  });
}
