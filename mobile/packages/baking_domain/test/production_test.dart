import 'package:baking_domain/baking_domain.dart';
import 'package:test/test.dart';
Rational r(num n)=>Rational.fromNum(n);
DateTime at(int h)=>DateTime.utc(2026,11,15,h);
ProductionMethod method({String id='country',num temperature=230,int piecesPerLoad=1})=>ProductionMethod(recipeId:id,title:id,validationEvidenceId:'synthetic-fixture-not-kitchen-validation',readyStepId:'cool',maximumPiecesPerLoad:piecesPerLoad,perPieceFormula:PhysicalFormula([
 PhysicalIngredient(id:'flour',grams:r(450),flourGrams:r(450)),PhysicalIngredient(id:'water',grams:r(300),waterGrams:r(300)),PhysicalIngredient(id:'levain',grams:r(100),flourGrams:r(50),waterGrams:r(50)),PhysicalIngredient(id:'salt',grams:r(10)),
]),perPieceResources:{'vessel','rack'},ovenTemperatures:{'bake':r(temperature)},graph:RecipeGraph(recipeVersion:'$id-v1',profileVersion:'fixture-only',steps:[
 RecipeStep(id:'bake',title:'Bake',nominalDuration:const Duration(hours:1),resources:{'oven':1,'vessel':1}),
 RecipeStep(id:'cool',title:'Cool',nominalDuration:const Duration(hours:1),dependencies:['bake'],resources:{'rack':1}),
]));
void main(){
 test('100 loaves become 100 distinct oven reservations, not one scaled loaf',(){
  final blueprint=const ProductionPlanner().compose(items:[ProductionItem(id:'gift',method:method(),pieces:100,pickupWindow:TimeWindow(at(18),at(19)))],horizon:TimeWindow(at(0),at(23)),reloadDuration:const Duration(minutes:10));
  expect(blueprint.batches,hasLength(100));expect(blueprint.graph.steps.where((s)=>s.id.endsWith('/bake')),hasLength(100));expect(blueprint.shoppingDemand['flour'],r(45000));expect(blueprint.packList.fold<int>(0,(n,l)=>n+(l['plannedPieces'] as int)),100);expect(blueprint.batches.map((b)=>b.id).toSet(),hasLength(100));
 });
 test('reviewed 2-piece load splits 5 pieces into 2,2,1 and scales vessels/racks',(){
  final b=const ProductionPlanner().compose(items:[ProductionItem(id:'gift',method:method(piecesPerLoad:2),pieces:5,pickupWindow:TimeWindow(at(18),at(19)))],horizon:TimeWindow(at(0),at(23)),reloadDuration:const Duration(minutes:10));
  expect(b.batches.map((b)=>b.pieces),[2,2,1]);expect(b.graph.steps.firstWhere((s)=>s.id=='gift:load-1/bake').resources,{'oven':1,'vessel':2});expect(b.batches.first.formula.totalDough,r(1720));
 });
 test('two loaves with one vessel have separate serial loads and cooled pickup',(){
  final planner=const ProductionPlanner();final horizon=TimeWindow(at(0),at(23));
  final b=planner.compose(items:[ProductionItem(id:'first',method:method(),pieces:1,pickupWindow:TimeWindow(at(12),at(13))),ProductionItem(id:'second',method:method(),pieces:1,pickupWindow:TimeWindow(at(14),at(15)))],horizon:horizon,reloadDuration:const Duration(hours:1));
  final result=planner.solve(blueprint:b,horizon:horizon,resourceCapacities:{'oven':1,'vessel':1,'rack':2});
  expect(result.feasible,isTrue);final c=result.planning.candidates.first;expect(c.task('first:load-1/bake').end.isAfter(c.task('second:load-1/bake').start),isFalse);expect(c.task('first:load-1/cool').end.isAfter(at(12)),isFalse);expect(c.task('second:load-1/cool').end.isAfter(at(14)),isFalse);
 });
 test('identical tight pickups do not invent a proof hold or concurrent oven',(){
  final planner=const ProductionPlanner();final horizon=TimeWindow(at(10),at(14));
  final b=planner.compose(items:[ProductionItem(id:'first',method:method(),pieces:2,pickupWindow:TimeWindow(at(12),at(13)))],horizon:horizon,reloadDuration:const Duration(minutes:10));
  final result=planner.solve(blueprint:b,horizon:horizon,resourceCapacities:{'oven':1,'vessel':1,'rack':2});expect(result.feasible,isFalse);expect(result.planning.status,PlanningStatus.searchIncomplete);
 });
 test('temperature changes require an explicit documented transition',(){
  final planner=const ProductionPlanner();final horizon=TimeWindow(at(0),at(23));
  final items=[ProductionItem(id:'bread',method:method(),pieces:1,pickupWindow:TimeWindow(at(12),at(13))),ProductionItem(id:'enriched',method:method(id:'milk',temperature:180),pieces:1,pickupWindow:TimeWindow(at(15),at(16)))];
  expect(()=>planner.compose(items:items,horizon:horizon,reloadDuration:const Duration(minutes:10)),throwsA(isA<DomainException>().having((e)=>e.code,'code','OVEN_CHANGEOVER_UNSUPPORTED')));
  final b=planner.compose(items:items,horizon:horizon,reloadDuration:const Duration(minutes:10),changeovers:[OvenChangeover(fromC:r(230),toC:r(180),duration:const Duration(minutes:20))]);
  final change=b.graph.steps.firstWhere((s)=>s.id.contains('__production_changeover__'));expect(change.nominalDuration,const Duration(minutes:30));expect(change.resources,{'oven':1});
 });
 test('unverified scaling envelope is rejected and large runs are bounded',(){
  expect(()=>ProductionMethod(recipeId:'x',title:'x',validationEvidenceId:'',readyStepId:'cool',perPieceFormula:method().perPieceFormula,graph:method().graph,maximumPiecesPerLoad:1),throwsA(isA<DomainException>()));
  expect(()=>const ProductionPlanner().compose(items:[ProductionItem(id:'large',method:method(),pieces:1000,pickupWindow:TimeWindow(at(12),at(13)))],horizon:TimeWindow(at(0),at(23)),reloadDuration:Duration.zero),throwsA(isA<DomainException>().having((e)=>e.code,'code','PRODUCTION_SIZE_UNSUPPORTED')));
 });
 test('cost and label distinguish dough mass planned pieces and missing prices',(){
  final b=const ProductionPlanner().compose(items:[ProductionItem(id:'gift',method:method(),pieces:2,pickupWindow:TimeWindow(at(12),at(13)))],horizon:TimeWindow(at(0),at(23)),reloadDuration:const Duration(minutes:10));
  expect(b.batches.first.label()['foodLabellingCompliance'],'not_certified');expect(b.cost([],currency:'GBP').totalCostMinorUnits,isNull);expect(b.batches.fold(Rational.zero,(Rational n,v)=>n+v.formula.totalDough),r(1720));
 });
}
