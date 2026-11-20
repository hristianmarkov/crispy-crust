import 'common.dart';
import 'formula.dart';
import 'planning.dart';
import 'comparison.dart';

/// Caller supplies the actually reviewed load envelope; the engine does not
/// certify that merely increasing a number of loaves preserves a bake method.
final class ProductionMethod {
 final String recipeId,title,validationEvidenceId,readyStepId;
 final bool experimental;
 final PhysicalFormula perPieceFormula;
 final RecipeGraph graph;
 final int maximumPiecesPerLoad;
 final Set<String> perPieceResources;
 final Map<String,Rational> ovenTemperatures;
 ProductionMethod({required this.recipeId,required this.title,required this.validationEvidenceId,
  required this.readyStepId,required this.perPieceFormula,required this.graph,
  required this.maximumPiecesPerLoad,this.experimental=false,Set<String> perPieceResources=const {},Map<String,Rational> ovenTemperatures=const {}})
  :perPieceResources=Set.unmodifiable(perPieceResources),ovenTemperatures=Map.unmodifiable(ovenTemperatures) {
  if(recipeId.isEmpty||title.isEmpty||(!experimental&&validationEvidenceId.trim().isEmpty)||maximumPiecesPerLoad<1||perPieceFormula.totalDough<=Rational.zero)throw const DomainException('PRODUCTION_METHOD_UNVALIDATED','A positive formula and explicit reviewed load envelope/evidence are required.');
  final order=graph.topologicalOrder(),byId={for(final s in graph.steps)s.id:s};
  if(order.any((s)=>s.id.startsWith('__production_')))throw const DomainException('PRODUCTION_RESERVED_STEP_ID','Recipe step uses an internal production identifier.');
  if(!byId.containsKey(readyStepId))throw const DomainException('PRODUCTION_READY_STEP_MISSING','Identify the method step that completes cooling/readiness for pickup.');
  final ancestors=<String>{};
  void visit(String id){if(!ancestors.add(id))return;for(final dep in byId[id]!.dependencies)visit(dep);}
  visit(readyStepId);
  if(ancestors.length!=order.length)throw const DomainException('PRODUCTION_METHOD_UNSUPPORTED','All method tasks must lead to the declared ready/cooling step.');
  if(ovenTemperatures.keys.any((id)=>!byId.containsKey(id))||ovenTemperatures.values.any((t)=>t.isNegative))throw ArgumentError('Temperature profiles must identify actual graph steps');
 }
}
final class ProductionItem {
 final String id;
 final ProductionMethod method;
 final int pieces;
 final TimeWindow pickupWindow;
 ProductionItem({required this.id,required this.method,required this.pieces,required this.pickupWindow}){
  if(!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)||pieces<1)throw ArgumentError('Production item needs positive quantity and identity');
 }
}
final class OvenChangeover {
 final Rational fromC,toC;
 final Duration duration,attendedDuration;
 OvenChangeover({required this.fromC,required this.toC,required this.duration,this.attendedDuration=Duration.zero}) {
  if(fromC.isNegative||toC.isNegative||duration.isNegative||attendedDuration.isNegative||attendedDuration>duration)throw ArgumentError('Invalid documented oven transition');
 }
}
final class ProductionBatch {
 final String id,itemId,title;
 final int pieces;
 final PhysicalFormula formula;
 final TimeWindow pickupWindow;
 final String readyStepId;
 ProductionBatch({required this.id,required this.itemId,required this.title,required this.pieces,required this.formula,required this.pickupWindow,required this.readyStepId});
 Map<String,dynamic> label()=>{'batchId':id,'itemId':itemId,'title':title,'plannedPieces':pieces,'plannedDoughGrams':formula.totalDough.toJson(),'pickupWindow':pickupWindow.toJson(),'foodLabellingCompliance':'not_certified'};
}
final class ProductionBlueprint {
 final List<ProductionBatch> batches;
 final RecipeGraph graph;
 final DateTime readyBy;
 final List<String> assumptions;
 ProductionBlueprint({required List<ProductionBatch> batches,required this.graph,required this.readyBy,required List<String> assumptions}):batches=List.unmodifiable(batches),assumptions=List.unmodifiable(assumptions);
 List<IngredientUse> get ingredientDemand=>[for(final b in batches)for(final i in b.formula.ingredients)IngredientUse(i.id,i.grams)];
 Map<String,Rational> get shoppingDemand=>const CostAndShoppingEngine().aggregate(ingredientDemand);
 List<Map<String,dynamic>> get packList=>batches.map((b)=>b.label()).toList();
 BatchCost cost(List<IngredientPrice> prices,{required String currency})=>const CostAndShoppingEngine().cost(ingredientDemand,prices,currency:currency,portions:batches.fold(0,(sum,b)=>sum+b.pieces));
}
final class ProductionPlanResult {
 final ProductionBlueprint blueprint;
 final PlanningResult planning;
 const ProductionPlanResult(this.blueprint,this.planning);
 bool get feasible=>planning.candidates.isNotEmpty;
}
final class ProductionPlanner {
 const ProductionPlanner();
 ProductionBlueprint compose({required List<ProductionItem> items,required TimeWindow horizon,
  String ovenResourceId='oven',required Duration reloadDuration,List<OvenChangeover> changeovers=const [],
  Duration reloadAttendedDuration=Duration.zero,List<String>? loadOrder,int maximumGeneratedLoads=500}) {
  if(items.isEmpty||items.map((i)=>i.id).toSet().length!=items.length||reloadDuration.isNegative||reloadAttendedDuration.isNegative||reloadAttendedDuration>reloadDuration)throw ArgumentError('Unique items and valid reload durations are required');
  final batches=<ProductionBatch>[],methods=<String,ProductionMethod>{};
  final requestedLoads=items.fold<int>(0,(n,i)=>n+(i.pieces+i.method.maximumPiecesPerLoad-1)~/i.method.maximumPiecesPerLoad);
  if(maximumGeneratedLoads<1||requestedLoads>maximumGeneratedLoads)throw const DomainException('PRODUCTION_SIZE_UNSUPPORTED','This production request exceeds the configured load limit. Split it into separately reviewed runs.');
  for(final item in items){
   if(item.pickupWindow.start.isBefore(horizon.start)||item.pickupWindow.start.isAfter(horizon.end))throw const DomainException('PICKUP_OUTSIDE_HORIZON','Pickup must start within the planning horizon.');
   var remaining=item.pieces,index=1;
   while(remaining>0){
    final count=remaining>item.method.maximumPiecesPerLoad?item.method.maximumPiecesPerLoad:remaining;
    final id='${item.id}:load-${index++}';
    batches.add(ProductionBatch(id:id,itemId:item.id,title:item.method.title,pieces:count,formula:item.method.perPieceFormula.scale(Rational.fromNum(count)),pickupWindow:item.pickupWindow,readyStepId:'$id/__production_ready__'));
    methods[id]=item.method;remaining-=count;
   }
  }
  if(loadOrder!=null){
   if(loadOrder.length!=batches.length||loadOrder.toSet().length!=batches.length||loadOrder.any((id)=>!methods.containsKey(id)))throw ArgumentError('Load order must name each generated batch exactly once');
   batches.sort((a,b)=>loadOrder.indexOf(a.id).compareTo(loadOrder.indexOf(b.id)));
  }else{batches.sort((a,b){final order=a.pickupWindow.start.compareTo(b.pickupWindow.start);return order!=0?order:a.id.compareTo(b.id);});}
  final combined=<RecipeStep>[];
  String? previousOvenStep,previousBatch;
  Rational? previousTemp;
  for(final batch in batches){
   final method=methods[batch.id]!;
   for(final step in method.graph.topologicalOrder()){
    final id='${batch.id}/${step.id}';
    final dependencies=step.dependencies.map((d)=>'${batch.id}/$d').toList();
    final occupiesOven=step.resources.containsKey(ovenResourceId);
    final temperature=method.ovenTemperatures[step.id];
    if(occupiesOven&&temperature==null)throw DomainException('OVEN_PROFILE_MISSING','Every oven occupancy step needs its documented temperature.',{'batchId':batch.id,'stepId':step.id});
    if(occupiesOven&&previousOvenStep!=null&&previousBatch!=batch.id){
     var transition=reloadDuration,attended=reloadAttendedDuration;
     if(previousTemp!=temperature){
      final matches=changeovers.where((r)=>r.fromC==previousTemp&&r.toC==temperature);
      if(matches.isEmpty)throw const DomainException('OVEN_CHANGEOVER_UNSUPPORTED','A documented temperature transition is missing.');
      transition+=matches.first.duration;attended+=matches.first.attendedDuration;
     }
     final transitionId='${batch.id}/__production_changeover__';
     combined.add(RecipeStep(id:transitionId,title:'Reload/change oven for ${batch.title}',nominalDuration:transition,dependencies:[previousOvenStep],resources:{ovenResourceId:1},handsOn:attended==Duration.zero?[]:[ActiveInterval(Duration.zero,attended)]));
     dependencies.add(transitionId);
    }
    combined.add(RecipeStep(id:id,title:'${batch.title} · ${step.title}',nominalDuration:step.nominalDuration,minimumDuration:step.minimumDuration,maximumDuration:step.maximumDuration,
     dependencies:dependencies,maxWaitAfterDependencies:step.maxWaitAfterDependencies,handsOn:step.handsOn,readinessGate:step.readinessGate,startWindow:step.startWindow,
     resources:step.resources.map((key,value)=>MapEntry(key,value*(method.perPieceResources.contains(key)?batch.pieces:1)))));
    if(occupiesOven){previousOvenStep=id;previousBatch=batch.id;previousTemp=temperature;}
   }
   combined.add(RecipeStep(id:batch.readyStepId,title:'${batch.title} · ready for packing/pickup',nominalDuration:Duration.zero,dependencies:['${batch.id}/${method.readyStepId}'],startWindow:TimeWindow(horizon.start,batch.pickupWindow.start)));
  }
  final graph=RecipeGraph(recipeVersion:canonicalJson(items.map((i)=>{'itemId':i.id,'recipeVersion':i.method.graph.recipeVersion}).toList()),profileVersion:canonicalJson(items.map((i)=>{'evidence':i.method.validationEvidenceId,'experimental':i.method.experimental}).toList()),steps:combined);
  graph.topologicalOrder();
  return ProductionBlueprint(batches:batches,graph:graph,readyBy:items.map((i)=>i.pickupWindow.start).reduce((a,b)=>a.isAfter(b)?a:b),assumptions:[
   if(items.any((i)=>i.method.experimental))'Experimental plan: load sizes and timing are user-confirmed assumptions, not kitchen-validated bounds.',
   'Pieces are separate named loads within the caller-supplied load envelope.',
   'Oven occupancies are conservatively serialised in the displayed load order; this is not a globally optimal production schedule.',
   'Published oven transitions and per-piece resource units are supplied by the caller.',
   'Cooling/readiness must finish before pickup begins. This is not a food-business compliance or shelf-life certification.',
  ]);
 }
 ProductionPlanResult solve({required ProductionBlueprint blueprint,required TimeWindow horizon,
  required Map<String,int> resourceCapacities,List<TimeWindow> unavailable=const [],List<ResourceReservation> reservations=const [],String kitchenTimeZone='UTC',int maxSearchNodes=50000}) {
  final request=PlanningRequest(graph:blueprint.graph,anchor:blueprint.readyBy,horizon:horizon,direction:PlanningDirection.backward,kitchenTimeZone:kitchenTimeZone,resourceCapacities:resourceCapacities,unavailable:unavailable,reservations:reservations,maxSearchNodes:maxSearchNodes);
  var result=const PlanningEngine().solve(request);
  // Failure of one displayed oven order does not prove every production order
  // impossible. No-fit cases
  // ask for another explicit order/target rather than inventing a dough hold.
  if(result.status==PlanningStatus.infeasible){
   result=PlanningResult(PlanningStatus.searchIncomplete,[],[...result.issues,const PlanningIssue('PRODUCTION_ORDER_REVIEW','No fit was found for this load order. Review another order, quantities or pickup windows.')],result.searchedNodes,searchExhausted:result.searchExhausted);
  }
  return ProductionPlanResult(blueprint,result);
 }
}
