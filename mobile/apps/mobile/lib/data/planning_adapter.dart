import 'package:baking_domain/baking_domain.dart';
import 'app_store.dart';

/// Converts authored content and local commitments to the same deterministic
/// planner used by the pure domain tests. Draft estimates stay labelled drafts.
ScheduleCandidate planRecipe(Map<String,dynamic> recipe, List<AppRecord> unavailable,
    List<AppRecord> bakes, Map<String,int> capacities, {DateTime? serveAt,DateTime? startAt}) {
  final now=DateTime.now().toUtc();
  if(serveAt!=null&&startAt!=null)throw const FormatException('Choose a mixing start or a serving target, not both.');
  if(startAt!=null&&!startAt.toUtc().isAfter(now))throw const FormatException('Choose a future mixing time.');
  if(serveAt!=null && !serveAt.toUtc().isAfter(now))throw const FormatException('Choose a future serving time.');
  final graph=graphForRecipe(recipe);
  final busy=<TimeWindow>[];
  for(final row in unavailable) {
    final start=row.date('startAt'),end=row.date('endAt');
    if(start!=null&&end!=null&&end.isAfter(start))busy.add(TimeWindow(start.toUtc(),end.toUtc()));
  }
  final reservations=<ResourceReservation>[];
  for(final bake in bakes.where((b)=>!['complete','packed','abandoned','archived'].contains(b.text('status',b.text('state'))))) {
    if(bake.kind=='production') {
      final values=bake.fields['reservations'];
      if(values==null)continue;
      if(values is! List)throw const FormatException('A production reservation needs review before this kitchen can be planned.');
      for(final row in values) {
        if(row is! Map)throw const FormatException('A production reservation is not readable.');
        final start=DateTime.tryParse('${row['start']}'),end=DateTime.tryParse('${row['end']}'),units=row['units'];
        final resource=row['resourceId'];
        if(start==null||end==null||end.isBefore(start)||resource is! String||resource.isEmpty||units is! num||!units.isFinite||units<1||units!=units.toInt())throw const FormatException('A production reservation has invalid equipment, capacity or timing. Review that run first.');
        reservations.add(ResourceReservation(resourceId:resource,owner:bake.id,window:TimeWindow(start.toUtc(),end.toUtc()),units:units.toInt()));
      }
      continue;
    }
    final snapshot=bake.fields['recipeSnapshot'];
    final schedule=bake.fields['schedule'];
    if(snapshot is! Map || schedule is! Map)continue;
    final otherGraph=graphForRecipe(Map<String,dynamic>.from(snapshot));
    final candidate=ScheduleCandidate.fromJson(Map<String,dynamic>.from(schedule));
    for(final task in candidate.tasks) {
      final step=otherGraph.steps.where((s)=>s.id==task.stepId).firstOrNull;
      if(step==null)continue;
      for(final resource in step.resources.entries) {
        reservations.add(ResourceReservation(resourceId:resource.key,owner:bake.id,window:TimeWindow(task.start,task.end),units:resource.value));
      }
    }
  }
  final allResources={for(final s in graph.steps)for(final r in s.resources.keys)r:1,...capacities};
  final result=const PlanningEngine().solve(PlanningRequest(graph:graph,
    anchor:(serveAt??startAt??now).toUtc(),direction:serveAt==null?PlanningDirection.forward:PlanningDirection.backward,
    horizon:TimeWindow(now,now.add(const Duration(days:14))),
    kitchenTimeZone:'UTC',unavailable:busy,resourceCapacities:allResources,reservations:reservations));
  if(result.candidates.isEmpty)throw StateError(result.issues.isEmpty
    ? 'No plan was found within the draft method and current availability. Change the target or availability. No cold-rest recovery is validated for this draft.'
    : result.issues.map((i)=>i.message).toSet().join(' '));
  return result.candidates.first;
}
RecipeGraph graphForRecipe(Map<String,dynamic> recipe) {
  final raw=(recipe['steps'] as List).cast<Map>();
  if(raw.isEmpty||!raw.any((s)=>s['durationMinutes'] is num&&(s['durationMinutes'] as num)>0))throw const FormatException('This recipe needs explicit positive stage durations before scheduling. Keep it as a draft until its execution method is reviewed.');
  return RecipeGraph(recipeVersion:'${recipe['id']}:${recipe['version']}',profileVersion:'draft-estimates-1',steps:raw.map((s) {
    if(s['id'] is! String||s['title'] is! String||!['handsOn','wait','check'].contains(s['kind'])||s['after'] is! List)throw const FormatException('Review step identities, attention types and dependency links before this recipe can be scheduled.');
    final minutes=s['durationMinutes'];
    if(minutes is! num||!minutes.isFinite||minutes<0||minutes>14*24*60)throw const FormatException('Recipe step duration is missing or outside the supported range.');
    final duration=Duration(milliseconds:(minutes*60000).round());
    if(s['kind']=='check'&&duration==Duration.zero)throw const FormatException('A readiness check needs a positive observation interval.');
    final attention=duration<const Duration(minutes:1)?duration:const Duration(minutes:1);
    final active=s['kind']=='handsOn';
    return RecipeStep(id:s['id'] as String,title:s['title'] as String,
      nominalDuration:duration,dependencies:List<String>.from(s['after'] as List? ?? []),
      readinessGate:s['kind']=='check',handsOn:active?[ActiveInterval(Duration.zero,duration)]:s['kind']=='check'?[ActiveInterval(duration-attention,attention)]:[],
      resources:{for(final r in s['resources'] as List? ?? [])r.toString():1});
  }).toList());
}
