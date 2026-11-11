import 'package:flutter_test/flutter_test.dart';
import 'package:crispy_crust/data/app_store.dart';
import 'package:crispy_crust/data/local_database.dart';
import 'package:crispy_crust/data/local_store.dart';
import 'package:crispy_crust/data/planning_adapter.dart';

Map<String,dynamic> method()=>{'id':'review-fixture','version':1,'title':'Synthetic fixture, not a baking method','status':'draft','ingredients':[{'id':'flour','grams':100}], 'steps':[
 {'id':'bake','title':'Bake','durationMinutes':10,'kind':'handsOn','after':<String>[],'resources':['oven']},
 {'id':'cool','title':'Cool','durationMinutes':10,'kind':'wait','after':['bake'],'resources':<String>[]},
]};
void main(){
 late LocalDatabase db;late LocalAppStore store;
 setUp(()async{db=LocalDatabase.memory();store=LocalAppStore(db,{'recipes':[method()]});await store.load();});
 tearDown(()async{await db.close();});
 test('an explicit future mixing anchor stays identical between preview and acceptance',()async{
  final start=DateTime.now().toUtc().add(const Duration(hours:2));
  final reviewed=planRecipe(method(),[],[],{'oven':1},startAt:start);
  final bake=await store.createBake(method(),startAt:start,expectedSchedule:reviewed.toJson());
  expect(bake.date('startAt'),start);expect(bake.fields['schedule'],reviewed.toJson());expect(bake.fields['startedAt'],isNull);expect(store.records('bake'),hasLength(1));
 });
 test('tampered or obsolete reviewed schedule is rejected before any bake is saved',()async{
  final start=DateTime.now().toUtc().add(const Duration(hours:2));
  final reviewed=planRecipe(method(),[],[],{'oven':1},startAt:start).toJson();
  ((reviewed['tasks'] as List).first as Map)['start']=start.add(const Duration(minutes:1)).toIso8601String();
  await expectLater(store.createBake(method(),startAt:start,expectedSchedule:reviewed),throwsStateError);
  expect(store.records('bake'),isEmpty);
 });
 test('new availability constraints invalidate the previously reviewed schedule',()async{
  final start=DateTime.now().toUtc().add(const Duration(hours:2));
  final reviewed=planRecipe(method(),[],[],{'oven':1},startAt:start);
  await store.save('availability',{'startAt':start.toIso8601String(),'endAt':start.add(const Duration(hours:1)).toIso8601String()});
  await expectLater(store.createBake(method(),startAt:start,expectedSchedule:reviewed.toJson()),throwsStateError);
  expect(store.records('bake'),isEmpty);
 });
 test('accepted production reservations block overlapping home bakes until released',()async{
  final start=DateTime.now().toUtc().add(const Duration(hours:2));
  final run=await store.save('production',{'name':'Already planned loads','status':'planned','reservations':[{'resourceId':'oven','units':1,'start':start.toIso8601String(),'end':start.add(const Duration(hours:1)).toIso8601String()}]});
  await expectLater(store.createBake(method(),startAt:start),throwsStateError);expect(store.records('bake'),isEmpty);
  await store.save('production',{...run.fields,'status':'complete','state':'packed'},id:run.id);
  final bake=await store.createBake(method(),startAt:start);expect(bake.date('startAt'),start);
 });
 test('production created after review invalidates acceptance of a stale home plan',()async{
  final start=DateTime.now().toUtc().add(const Duration(hours:2));
  final reviewed=planRecipe(method(),[],[],{'oven':1},startAt:start);
  await store.save('production',{'status':'planned','reservations':[{'resourceId':'oven','units':1,'start':start.toIso8601String(),'end':start.add(const Duration(hours:1)).toIso8601String()}]});
  await expectLater(store.createBake(method(),startAt:start,expectedSchedule:reviewed.toJson()),throwsStateError);expect(store.records('bake'),isEmpty);
 });
 test('invalid active production reservation fails closed instead of disappearing',(){
  final start=DateTime.now().toUtc().add(const Duration(hours:2));
  final bad=AppRecord(id:'bad',kind:'production',fields:{'status':'planned','reservations':[{'resourceId':'oven','units':0,'start':start.toIso8601String(),'end':start.add(const Duration(hours:1)).toIso8601String()}]},updatedAt:start);
  expect(()=>planRecipe(method(),[],[bad],{'oven':1},startAt:start),throwsFormatException);
 });
 test('two anchors or a past explicit start cannot be interpreted silently',(){
  final future=DateTime.now().toUtc().add(const Duration(hours:2));
  expect(()=>planRecipe(method(),[],[],{'oven':1},startAt:future,serveAt:future),throwsFormatException);
  expect(()=>planRecipe(method(),[],[],{'oven':1},startAt:DateTime.now().toUtc().subtract(const Duration(minutes:1))),throwsFormatException);
 });
}
