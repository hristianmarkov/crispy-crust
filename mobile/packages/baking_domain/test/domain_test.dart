import 'dart:convert';
import 'package:baking_domain/baking_domain.dart';
import 'package:test/test.dart';

Rational r(num n)=>Rational.fromNum(n);
DateTime at(int hour,[int minute=0])=>DateTime.utc(2026,11,15,hour,minute);
Matcher code(String value)=>isA<DomainException>().having((e)=>e.code,'code',value);
RecipeGraph loaf({bool variable=false})=>RecipeGraph(recipeVersion:'test-v1',profileVersion:'fixture-not-baking-guidance',steps:[
 RecipeStep(id:'preheat',title:'Preheat',nominalDuration:const Duration(minutes:45),handsOn:[ActiveInterval(Duration.zero,const Duration(minutes:1))],resources:{'oven':1}),
 RecipeStep(id:'bake',title:'Bake',nominalDuration:const Duration(minutes:45),dependencies:['preheat'],handsOn:[ActiveInterval(Duration.zero,const Duration(minutes:5))],resources:{'oven':1}),
 RecipeStep(id:'cool',title:'Cool',nominalDuration:const Duration(hours:2),minimumDuration:variable?const Duration(hours:1):null,maximumDuration:variable?const Duration(hours:3):null,dependencies:['bake']),
]);
PlanningRequest request({RecipeGraph? graph,List<TimeWindow> unavailable=const [],List<ResourceReservation> reservations=const [],Map<String,ScheduleTask> completed=const {},int maxSearchNodes=20000})=>PlanningRequest(graph:graph??loaf(),anchor:at(11),horizon:TimeWindow(at(0),at(23)),direction:PlanningDirection.backward,kitchenTimeZone:'Europe/London',resourceCapacities:{'oven':1},unavailable:unavailable,reservations:reservations,completed:completed,maxSearchNodes:maxSearchNodes);
void main(){
 group('Exact rational and formula',(){
  test('decimal and scientific input never uses binary float arithmetic',(){expect(Rational.parse('0.1')+Rational.parse('.2'.replaceFirst('.','0.')),r(.3));expect(Rational.parse('1.5e-3'),Rational.parse('3/2000'));expect(Rational.parse('-2.5').round(),BigInt.from(-3));expect(r(2.5).round(),BigInt.from(3));});
  test('100% starter golden fixture counts levain once',(){final result=const FormulaEngine().calculate(FormulaDefinition.fromNumbers(totalFlour:1000,hydration:.75));expect(result.addedFlour,r(900));expect(result.addedWater,r(650));expect(result.starterMass,r(200));expect(result.salt,r(20));expect(result.totalDough,r(1770));});
  test('multiple preferments keep independent hydrations and one physical mass each',(){
   final result=const FormulaEngine().calculate(FormulaDefinition.fromNumbers(totalFlour:1000,hydration:.75,preferments:[Preferment(id:'liquid',flourFraction:r(.1),hydration:r(1)),Preferment(id:'stiff',flourFraction:r(.1),hydration:r(.5))]));
   expect(result.addedFlour,r(800));expect(result.addedWater,r(600));expect(result.ingredients['preferment:liquid'],r(200));expect(result.ingredients['preferment:stiff'],r(150));expect(result.totalDough,r(1770));expect(result.starterMass,r(350));
   final copy=FormulaDefinition.fromJson(jsonDecode(jsonEncode(result.definition.toJson())));
   expect(const FormulaEngine().calculate(copy).toJson(),result.toJson());
  });
  test('mass conservation across deterministic fractional scale fixtures',(){
   final engine=const FormulaEngine();
   for(var i=1;i<=30;i++){
    final f=FormulaDefinition.fromNumbers(totalFlour:100+i*11.3,hydration:.5+i*.01,prefermentedFlourFraction:.05+i*.005,starterHydration:.5+i*.02);
    final result=engine.calculate(f);
    expect(result.ingredients.values.fold(Rational.zero,(a,b)=>a+b),result.totalDough);
    expect(result.addedWater+result.starterWater,f.totalFlour*f.hydration);
    expect(result.addedFlour+result.starterFlour,f.totalFlour);
   }
  });
  test('stiff starter preserves total hydration and yield' ,(){final result=const FormulaEngine().calculate(FormulaDefinition.fromNumbers(totalFlour:1000,hydration:.75,starterHydration:.5));expect(result.addedWater,r(700));expect(result.starterMass,r(150));expect(result.totalDough,r(1770));});
  test('negative water additions are rejected',(){expect(()=>const FormulaEngine().calculate(FormulaDefinition.fromNumbers(totalFlour:1000,hydration:.4,prefermentedFlourFraction:.5)),throwsA(code('FORMULA_NEGATIVE_ADDITION')));});
  test('scale round trip and displayed mass conservation',(){final engine=const FormulaEngine();final f=FormulaDefinition.fromNumbers(totalFlour:333,hydration:.73);final result=engine.calculate(f,targetDoughWeight:r(1000));expect(result.totalDough,r(1000));final rounded=result.roundForScale(incrementGrams:.1);expect(rounded.ingredients.values.fold(Rational.zero,(a,b)=>a+b),rounded.totalDough);expect(engine.calculate(f.scale(r(3)).scale(Rational.parse('1/3'))).totalDough,engine.calculate(f).totalDough);});
  test('JSON rational quantities round trip',(){final f=FormulaDefinition.fromNumbers(totalFlour:333.3,hydration:.7,inclusions:{'seeds':20});final copy=FormulaDefinition.fromJson(jsonDecode(jsonEncode(f.toJson())));expect(const FormulaEngine().calculate(copy).totalDough,const FormulaEngine().calculate(f).totalDough);});
  test('feed includes recipe use and retained mother',(){final build=const FormulaEngine().buildStarter(FeedBuildRequest(requiredMass:r(200),retainMass:r(20),availableSeed:r(50)));expect(build.seed,r(44));expect(build.flour,r(88));expect(build.water,r(88));expect(build.total,r(220));expect(build.hydration,r(1));expect(()=>const FormulaEngine().buildStarter(FeedBuildRequest(requiredMass:r(200),retainMass:r(20),availableSeed:r(20))),throwsA(code('FEED_INSUFFICIENT_SEED')));});
  test('physical ingredient catalogue totals count levain composition once',(){
   final f=PhysicalFormula([
    PhysicalIngredient(id:'flour',grams:r(450),flourGrams:r(450)),
    PhysicalIngredient(id:'water',grams:r(300),waterGrams:r(300)),
    PhysicalIngredient(id:'starter',grams:r(100),flourGrams:r(50),waterGrams:r(50)),
    PhysicalIngredient(id:'salt',grams:r(10)),
   ]);
   expect(f.totalDough,r(860));expect(f.totalFlour,r(500));expect(f.hydration,r(.7));expect(f.toDoughWeight(r(1000)).totalDough,r(1000));expect(f.scale(r(2)).hydration,r(.7));
   expect(()=>PhysicalIngredient(id:'bad',grams:r(100),flourGrams:r(150)),throwsA(code('FORMULA_INVALID_COMPOSITION')));
  });
  test('density requires provenance and temperature conversion is reversible',(){expect(()=>IngredientDensity(r(.5),source:'',uncertainty:'approximate'),throwsArgumentError);final density=IngredientDensity(r(.5),source:'measured pack',uncertainty:'packing varies');expect(density.gramsFor(r(100)),r(50));expect(fahrenheitToCelsius(celsiusToFahrenheit(r(23))),r(23));});
 });
 group('Schedule constraints',(){
  test('backward serving accounts for cooling bake and preheat',(){final result=const PlanningEngine().solve(request());expect(result.status,PlanningStatus.feasible);final c=result.candidates.first;expect(c.task('bake').start,at(8,15));expect(c.task('bake').end,at(9));expect(c.task('preheat').start,at(7,30));expect(c.task('cool').end,at(11));expect(c.requiresObservation,isFalse);expect(const PlanningEngine().validate(c,request()).isValid,isTrue);});
  test('hands-on absence before 09:00 cannot be silently ignored',(){final result=const PlanningEngine().solve(request(unavailable:[TimeWindow(at(0),at(9))]));expect(result.status,PlanningStatus.infeasible);expect(result.issues.any((i)=>i.code=='AVAILABILITY_CONFLICT'),isTrue);});
  test('passive cooling can span unavailable time',(){final result=const PlanningEngine().solve(request(unavailable:[TimeWindow(at(9),at(11))]));expect(result.status,PlanningStatus.feasible);});
  test('one occupied oven rejects a concurrent loaf',(){final result=const PlanningEngine().solve(request(reservations:[ResourceReservation(resourceId:'oven',owner:'other-bake',window:TimeWindow(at(8),at(9)))]));expect(result.status,PlanningStatus.infeasible);expect(result.issues.any((i)=>i.code=='RESOURCE_CAPACITY_CONFLICT'),isTrue);});
  test('completed events remain pinned despite changed target',(){final actual=ScheduleTask(stepId:'preheat',start:at(7,30),end:at(8,15),actual:true);final result=const PlanningEngine().solve(request(completed:{'preheat':actual}));expect(result.status,PlanningStatus.feasible);expect(result.candidates.first.task('preheat').toJson(),actual.toJson());});
  test('cold branch bridges fixed shaping actual with an exact in-range duration',(){
   final shaped=DateTime.utc(2026,11,14,20);
   final g=RecipeGraph(recipeVersion:'cold-fixture',profileVersion:'fixture-only',steps:[
    RecipeStep(id:'shape',title:'Shape',nominalDuration:const Duration(minutes:15)),
    RecipeStep(id:'cold',title:'Cold proof',nominalDuration:const Duration(hours:12),minimumDuration:const Duration(hours:10),maximumDuration:const Duration(hours:14),dependencies:['shape']),
    RecipeStep(id:'bake',title:'Bake',nominalDuration:const Duration(minutes:45),dependencies:['cold']),
    RecipeStep(id:'cool',title:'Cool',nominalDuration:const Duration(hours:2),dependencies:['bake']),
   ]);
   final req=PlanningRequest(graph:g,anchor:at(11),horizon:TimeWindow(DateTime.utc(2026,11,14),at(23)),direction:PlanningDirection.backward,completed:{'shape':ScheduleTask(stepId:'shape',start:shaped.subtract(const Duration(minutes:15)),end:shaped,actual:true)});
   final result=const PlanningEngine().solve(req);expect(result.status,PlanningStatus.feasible);expect(result.candidates.first.task('cold').duration,const Duration(hours:12,minutes:15));
   final tooLate=PlanningRequest(graph:g,anchor:at(17,15),horizon:req.horizon,direction:PlanningDirection.backward,completed:req.completed);
   expect(const PlanningEngine().solve(tooLate).candidates,isEmpty);
  });
  test('replan cannot be committed against changed revision' ,(){final previous=const PlanningEngine().solve(request()).candidates.first;final proposal=const PlanningEngine().proposeRecovery(previous:previous,request:request(),expectedRevision:3);expect(()=>proposal.requireCurrentRevision(4),throwsA(code('REVISION_CONFLICT')));});
  test('search exhaustion is not infeasibility',(){final result=const PlanningEngine().solve(request(maxSearchNodes:1));expect(result.status,PlanningStatus.searchIncomplete);});
  test('variable duration fit is observation-dependent not robust claim',(){final result=const PlanningEngine().solve(request(graph:loaf(variable:true)));expect(result.status,PlanningStatus.feasible);expect(result.candidates.first.requiresObservation,isTrue);});
  test('dependency cycle is unsupported rather than an endless search',(){final g=RecipeGraph(recipeVersion:'x',profileVersion:'x',steps:[RecipeStep(id:'a',title:'A',nominalDuration:Duration.zero,dependencies:['b']),RecipeStep(id:'b',title:'B',nominalDuration:Duration.zero,dependencies:['a'])]);expect(const PlanningEngine().solve(request(graph:g)).issues.first.code,'GRAPH_CYCLE');});
  test('forward anchor is preserved exactly',(){final req=PlanningRequest(graph:loaf(),anchor:at(7,30),horizon:TimeWindow(at(0),at(23)),resourceCapacities:{'oven':1});final c=const PlanningEngine().solve(req).candidates.first;expect(c.startsAt,at(7,30));expect(c.finishesAt,at(11));});
  test('JSON graph and candidate round trip',(){final req=request();final g=RecipeGraph.fromJson(jsonDecode(jsonEncode(req.graph.toJson())));expect(g.toJson(),req.graph.toJson());final c=const PlanningEngine().solve(req).candidates.first;expect(ScheduleCandidate.fromJson(jsonDecode(jsonEncode(c.toJson()))).toJson(),c.toJson());});
 });
 group('Starter empirical check windows',(){
  FeedContext context([String starter='jar'])=>FeedContext(starterId:starter,flourMixKey:'white-v1',hydration:r(1),flourParts:r(2),waterParts:r(2),temperatureC:23);
  List<PeakRecord> history(int count)=>List.generate(count,(i)=>PeakRecord(id:'feed-$i',context:context(),fedAt:at(8).subtract(Duration(days:i+1)),peakAt:at(13,i*10).subtract(Duration(days:i+1)),status:PeakStatus.observed));
  test('four feeds use supplied broad guidance',(){final e=const StarterEstimator().estimate(context:context(),fedAt:at(8),now:at(9),history:history(4),reviewedEarliest:const Duration(hours:3),reviewedLatest:const Duration(hours:10));expect(e.personalized,isFalse);expect(e.checkWindow.start,at(11));expect(e.comparableCount,4);expect(e.statisticallyCalibrated,isFalse);});
  test('five genuinely comparable peaks enable empirical broad window',(){final records=history(5);records.add(PeakRecord(id:'unknown',context:context(),fedAt:at(8).subtract(const Duration(days:1)),status:PeakStatus.missedUnknown));final e=const StarterEstimator().estimate(context:context(),fedAt:at(8),now:at(9),history:records,reviewedEarliest:const Duration(hours:3),reviewedLatest:const Duration(hours:10));expect(e.personalized,isTrue);expect(e.comparableCount,5);expect(e.sourceRecordIds,hasLength(5));});
  test('other jars and unknown temperatures never enter personal model',(){final e=const StarterEstimator().estimate(context:context('different'),fedAt:at(8),now:at(9),history:history(6),reviewedEarliest:const Duration(hours:3),reviewedLatest:const Duration(hours:10));expect(e.comparableCount,0);});
  test('rise calculation needs calibrated geometry and is not readiness',(){expect(risePercentage(baselineHeight:r(25),currentHeight:r(42),straightSidedOrCalibrated:true),r(68));expect(()=>risePercentage(baselineHeight:r(25),currentHeight:r(42),straightSidedOrCalibrated:false),throwsA(code('CONTAINER_UNCALIBRATED')));});
 });
 group('Immutable event reducer',(){
  BakeEvent event(int n,BakeEventType type,{Map<String,dynamic> payload=const {}})=>BakeEvent(id:'e$n',operationId:'op$n',bakeId:'b',actorId:'u',type:type,occurredAt:at(10,n),recordedAt:at(10,n),sequence:n,payload:payload);
  BakeSnapshot active()=>const BakeReducer().replay(bakeId:'b',recipeVersion:'v1',events:[event(1,BakeEventType.planAccepted,payload:{'scheduleId':'s1'}),event(2,BakeEventType.bakeStarted)]);
  test('nested event payload is immutable and detached from caller maps',(){
   final source=<String,dynamic>{'context':<String,dynamic>{'measurements':<Object?>[23]}};
   final e=event(1,BakeEventType.observationRecorded,payload:source);
   (source['context'] as Map)['measurements']=[99];
   expect((e.payload['context'] as Map)['measurements'],[23]);
   expect(()=>((e.payload['context'] as Map)['measurements'] as List).add(24),throwsUnsupportedError);
  });
  test('duplicate network delivery is a no-op' ,(){final a=active();final e=event(3,BakeEventType.stepCompleted,payload:{'stepId':'fold-1'});final b=const BakeReducer().apply(a,e);expect(identical(const BakeReducer().apply(b,e),b),isTrue);expect(b.completedSteps['fold-1'],at(10,3));expect(a.completedSteps,isEmpty);});
  test('two physical completion claims retain both but count once',(){var b=const BakeReducer().apply(active(),event(3,BakeEventType.stepCompleted,payload:{'stepId':'fold-1'}));b=const BakeReducer().apply(b,event(4,BakeEventType.stepCompleted,payload:{'stepId':'fold-1'}));expect(b.completedSteps,hasLength(1));expect(b.completedSteps['fold-1'],at(10,3));expect(b.events,hasLength(4));expect(b.reconciliationWarnings.single,contains('DUPLICATE_PHYSICAL_ACTION_REVIEW'));});
  test('out-of-order accepted sequence rejected',(){expect(()=>const BakeReducer().apply(active(),event(4,BakeEventType.observationRecorded,payload:{'rise':20})),throwsA(code('REVISION_CONFLICT')));});
  test('bake complete requires an explicit cooling transition',(){expect(()=>const BakeReducer().apply(active(),event(3,BakeEventType.bakeCompleted)),throwsA(code('BAKE_ILLEGAL_TRANSITION')));});
  test('unapproved skip cannot change a recipe method',(){expect(()=>const BakeReducer().apply(active(),event(3,BakeEventType.stepSkipped,payload:{'stepId':'fold-1','reason':'late'})),throwsA(code('METHOD_UNSUPPORTED')));});
  test('event serialization retains original occurrence and actor',(){final e=event(1,BakeEventType.planAccepted,payload:{'scheduleId':'s'});expect(BakeEvent.fromJson(jsonDecode(jsonEncode(e.toJson()))).toJson(),e.toJson());});
 });
}
