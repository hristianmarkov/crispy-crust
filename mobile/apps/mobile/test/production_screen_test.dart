import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crispy_crust/data/app_store.dart';
import 'package:crispy_crust/screens/production_screen.dart';

final recipe=<String,dynamic>{
 'id':'test-loaf','title':'Test loaf','version':1,'yieldCount':1,'status':'draft',
 'ingredients':[
  {'id':'flour','grams':450,'flourGrams':450,'waterGrams':0},
  {'id':'water','grams':300,'flourGrams':0,'waterGrams':300},
  {'id':'starter','grams':100,'flourGrams':50,'waterGrams':50},
  {'id':'salt','grams':10,'flourGrams':0,'waterGrams':0},
 ],
 'steps':[
  {'id':'bake','title':'Bake','durationMinutes':60,'kind':'handsOn','after':<String>[],'resources':['oven','vessel']},
  {'id':'cool','title':'Cool before slicing','durationMinutes':60,'kind':'wait','after':['bake'],'resources':['coolingRack']},
 ],
};
class ProductionTestStore extends AppStore {
 final List<AppRecord> data=[];
 @override List<AppRecord> records(String kind)=>data.where((r)=>r.kind==kind).toList();
 @override AppRecord? find(String id)=>data.where((r)=>r.id==id).firstOrNull;
 @override List<Map<String,dynamic>> get recipes=>[recipe];
 @override List<Map<String,dynamic>> get lessons=>[];
 @override List<Map<String,dynamic>> get guidance=>[];
 @override bool get darkMode=>false;
 @override bool get beginnerMode=>false;
 @override String get storageDescription=>'Local test store';
 @override dynamic preference(String key,[dynamic fallback])=>fallback;
 @override Future<void> setPreference(String key,dynamic value)async{}
 @override Future<AppRecord> save(String kind,Map<String,dynamic> fields,{String? id})async{
  final record=AppRecord(id:id??'record-${data.length}',kind:kind,fields:fields,updatedAt:DateTime.utc(2026,11,15));
  data.removeWhere((r)=>r.id==record.id);data.add(record);notifyListeners();return record;
 }
 @override Future<void> remove(String id)async{data.removeWhere((r)=>r.id==id);notifyListeners();}
 @override Future<void> resetLocalData()async{data.clear();notifyListeners();}
 @override Future<String> exportArchive()async=>'{}';
 @override Future<void> importArchive(String source)async{}
 @override Future<AppRecord> createBake(Map<String,dynamic> recipe,{double scale=1,DateTime? serveAt,DateTime? startAt,Map<String,dynamic>? expectedSchedule})=>throw UnimplementedError();
 @override Future<void> completeStep(String bakeId,{DateTime? occurredAt,int? expectedIndex})=>throw UnimplementedError();
 @override Future<void> logFeed(String starterId,{required double seed,required double flour,required double water,DateTime? occurredAt})=>throw UnimplementedError();
}
void main(){
 late ProductionTestStore store;
 setUp(()=>store=ProductionTestStore());
 tearDown(()=>store.dispose());
 Future<void> mount(WidgetTester tester)async{
  await tester.binding.setSurfaceSize(const Size(430,920));addTearDown(()=>tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home:ProductionScreen(store:store,clock:()=>DateTime(2026,11,15),solver:(input)async=>solveProduction(input))));await tester.pumpAndSettle();
 }
 Finder scroll()=>find.descendant(of:find.byKey(const ValueKey('production-scroll')),matching:find.byType(Scrollable)).first;
 Future<void> reveal(WidgetTester tester,Finder finder,{double delta=250})async{await tester.scrollUntilVisible(finder,delta,scrollable:scroll());await tester.ensureVisible(finder);}
 Future<void> addProduct(WidgetTester tester,{String pieces='2'})async{
  await tester.enterText(find.byKey(const ValueKey('production-name')),'Gift loaves');
  await reveal(tester,find.byKey(const ValueKey('production-count')));await tester.enterText(find.byKey(const ValueKey('production-count')),pieces);
  await reveal(tester,find.byKey(const ValueKey('production-experimental')));await tester.tap(find.byKey(const ValueKey('production-experimental')));await tester.pumpAndSettle();
  await reveal(tester,find.byKey(const ValueKey('production-add')));await tester.tap(find.byKey(const ValueKey('production-add')));await tester.pumpAndSettle();
 }
 testWidgets('production requires explicit experimental acknowledgement; no implicit reservations', (tester)async{
  await mount(tester);await reveal(tester,find.byKey(const ValueKey('production-add')));
  final add=tester.widget<FilledButton>(find.byKey(const ValueKey('production-add')));expect(add.onPressed,isNull);expect(store.records('production'),isEmpty);
  expect(find.textContaining('not kitchen-tested'),findsWidgets);expect(tester.takeException(),isNull);
 });
 testWidgets('quantity creates separate loads; acceptance persists exact demand and reservations', (tester)async{
  await mount(tester);await addProduct(tester);
  await reveal(tester,find.byKey(const ValueKey('production-generate')));await tester.tap(find.byKey(const ValueKey('production-generate')));await tester.pumpAndSettle();
  expect(store.records('production'),isEmpty);
  await reveal(tester,find.byKey(const ValueKey('production-save')));await tester.tap(find.byKey(const ValueKey('production-save')));await tester.pumpAndSettle();
  final run=store.records('production').single;expect((run.fields['batches'] as List).length,2);expect(run.fields['experimental'],isTrue);expect(run.fields['actualYield'],isNull);expect(run.fields['totalCostMinorUnits'],isNull);expect((run.fields['reservations'] as List).length,greaterThanOrEqualTo(4));
  final shopping=run.fields['shopping'] as Map;expect(shopping['flour'],{'n':'900','d':'1'});expect(store.records('bake'),isEmpty);expect(tester.takeException(),isNull);
 });
 testWidgets('zero vessel capacity shows a real conflict and cannot be accepted', (tester)async{
  await mount(tester);await addProduct(tester,pieces:'1');
  final capacity=find.byKey(const ValueKey('production-capacity-vessel'));await reveal(tester,capacity);await tester.enterText(capacity,'0');
  await reveal(tester,find.byKey(const ValueKey('production-generate')));await tester.tap(find.byKey(const ValueKey('production-generate')));await tester.pumpAndSettle();
  expect(find.text('Review conflicts'),findsOneWidget);expect(find.byKey(const ValueKey('production-save')),findsNothing);expect(store.records('production'),isEmpty);expect(tester.takeException(),isNull);
 });
}
