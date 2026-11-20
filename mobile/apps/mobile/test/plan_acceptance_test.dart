import 'package:flutter_test/flutter_test.dart';
import 'package:crispy_crust/data/app_store.dart';
import 'package:crispy_crust/data/local_database.dart';
import 'package:crispy_crust/data/local_store.dart';
import 'package:crispy_crust/data/planning_adapter.dart';
import 'package:crispy_crust/data/fermentation.dart';
import 'package:crispy_crust/data/bake_replan.dart';

Map<String,dynamic> method()=>{'id':'review-fixture','version':1,'title':'Synthetic fixture, not a baking method','status':'draft','ingredients':[{'id':'flour','grams':100}], 'steps':[
 {'id':'bake','title':'Bake','durationMinutes':10,'kind':'handsOn','after':<String>[],'resources':['oven']},
 {'id':'cool','title':'Cool','durationMinutes':10,'kind':'wait','after':['bake'],'resources':<String>[]},
]};
void main(){
 late LocalDatabase db;late LocalAppStore store;
 setUp(()async{db=LocalDatabase.memory();store=LocalAppStore(db,{'recipes':[method()]});await store.load();});
 tearDown(()async{await db.close();});
 test('lean forecast shortens the check window for warmer dough', () {
  expect(leanDoughRise(16), isNull);
  expect(leanDoughRise(24)?.minimumMinutes, 300);
  expect(leanDoughRise(25)!.maximumMinutes, lessThan(leanDoughRise(24)!.maximumMinutes));
 });
 test('a time-away conflict offers a later feasible start without booking it', () async {
  final start = DateTime.now().toUtc().add(const Duration(hours: 1));
  final back = start.add(const Duration(hours: 3));
  final setup = BakeSetup(timeAway: [(start.subtract(const Duration(minutes: 10)), back)]);
  final options = prepareBakeSchedule(method(), setup.awayRecords, [], {'oven': 1}, startAt: start);
  expect(options.warning, contains('starts later'));
  expect(options.candidates.first.startsAt.isBefore(back), isFalse);
  expect(store.records('bake'), isEmpty);
 });
 test('the selected starter and next timer are recorded once when mixing is completed', () async {
  final starter = await store.save('starter', {'name': 'Rye jar', 'mass': 150});
  final recipe = {...method(), 'ingredients': [
    {'id': 'seed', 'name': 'Starter', 'role': 'starter', 'grams': 80},
    {'id': 'flour', 'name': 'Bread flour', 'role': 'flour', 'grams': 400},
  ]};
  final start = DateTime.now().toUtc().add(const Duration(minutes: 2));
  final bake = await store.createBake(recipe, startAt: start, beginImmediately: true,
    setup: BakeSetup(starterId: starter.id, addToShopping: false));
  expect(bake.text('starterId'), starter.id);
  expect(store.find(starter.id)!.number('mass'), 150);
  expect(store.records('shopping'), isEmpty);
  expect(store.records('timer'), isEmpty);
  final at = DateTime.now().toUtc();
  await store.completeStep(bake.id, occurredAt: at, expectedIndex: 0);
  final afterMix = store.find(bake.id)!;
  expect(afterMix.date('starterUsedAt'), at);
  expect(afterMix.date('nextStepDueAt'), at.add(const Duration(minutes: 10)));
  expect(store.records('timer').single.text('stepId'), 'cool');
  expect(store.find(starter.id)!.number('mass'), 70);
  await store.completeStep(bake.id, expectedIndex: 1);
  expect(store.records('timer').single.text('state'), 'acknowledged');
  expect(store.find(starter.id)!.number('mass'), 70);
 });
 test('time away can add fridge tasks without moving completed folds', () async {
  final recipe = <String,dynamic>{...method(), 'id': 'R01', 'steps': [
    {'id': 'fold', 'title': 'Final fold', 'kind': 'handsOn', 'durationMinutes': 3, 'after': <String>[]},
    {'id': 'bulk', 'title': 'Bulk rise', 'kind': 'check', 'durationMinutes': 240, 'after': ['fold']},
    {'id': 'shape', 'title': 'Shape', 'kind': 'handsOn', 'durationMinutes': 5, 'after': ['bulk']},
  ]};
  final now = DateTime.now().toUtc();
  final start = now.add(const Duration(minutes: 4));
  final bake = await store.createBake(recipe, startAt: start);
  await store.completeStep(bake.id, expectedIndex: 0);
  final current = store.find(bake.id)!;
  final anchor = now.add(const Duration(minutes: 6));
  final leave = anchor.add(const Duration(hours: 1));
  final back = anchor.add(const Duration(hours: 5));
  final proposal = reviewRemainingBake(store, current, anchor, (leave, back));
  final option = proposal.candidates.first;
  expect(option.task('chill-dough').end.isAfter(leave), isFalse);
  expect(option.task('un-chill-dough').start.isBefore(back), isFalse);
  expect(option.task('temper-dough').duration, const Duration(minutes: 30));
  final updated = updatedBakeSchedule(current, proposal, option);
  expect(updated['completedSteps'], current.fields['completedSteps']);
  expect((updated['steps'] as List).first, (current.fields['steps'] as List).first);
 });
 test('acceptance adds scaled pantry shortages to shopping once', () async {
  final recipe = {...method(), 'ingredients': [
    {'id': 'flour', 'name': 'Bread flour', 'grams': 400, 'role': 'flour'},
    {'id': 'water', 'name': 'Water', 'grams': 300, 'role': 'water'},
  ]};
  await store.save('pantry', {'name': 'bread flour', 'grams': 175});
  final bake = await store.createBake(recipe, startAt: DateTime.now().add(const Duration(hours: 2)), scale: .5);
  final item = store.records('shopping').single;
  expect(item.text('bakeId'), bake.id);
  expect(item.number('grams'), 25);
  expect(store.records('pantry').single.number('grams'), 175);
 });
 test('an explicit future mixing anchor stays identical between preview and acceptance',()async{
  final start=DateTime.now().toUtc().add(const Duration(hours:2));
  final reviewed=planRecipe(method(),[],[],{'oven':1},startAt:start);
  final bake=await store.createBake(method(),startAt:start,expectedSchedule:reviewed.toJson());
  expect(bake.date('startAt'),start);expect(bake.fields['schedule'],reviewed.toJson());expect(bake.fields['startedAt'],isNull);expect(store.records('bake'),hasLength(1));
 });
 test('the reviewed alternative is saved when it remains feasible', () async {
  final start = DateTime.now().toUtc().add(const Duration(hours: 2));
  final recipe = method();
  (recipe['steps'] as List).add({
   'id': 'packaging',
   'title': 'Prepare packaging',
   'durationMinutes': 5,
   'kind': 'handsOn',
   'after': <String>[],
   'resources': <String>[],
  });
  await store.save('availability', {
   'startAt': start.add(const Duration(minutes: 15)).toIso8601String(),
   'endAt': start.add(const Duration(minutes: 30)).toIso8601String(),
  });
  final candidates = planRecipeCandidates(recipe, store.records('availability'), [], {'oven': 1}, startAt: start);
  final alternative = candidates[1];
  final bake = await store.createBake(recipe, startAt: start, expectedSchedule: alternative.toJson());
  expect(bake.fields['schedule'], alternative.toJson());
  expect(bake.fields['schedule'], isNot(candidates.first.toJson()));
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
