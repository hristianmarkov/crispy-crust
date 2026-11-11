import 'package:baking_domain/baking_domain.dart';
import 'app_store.dart';

/// Converts authored content and local commitments to the same deterministic
/// planner used by the pure domain tests. Draft estimates stay labelled drafts.
ScheduleCandidate planRecipe(Map<String,dynamic> recipe, List<AppRecord> unavailable,
    List<AppRecord> bakes, Map<String,int> capacities, {DateTime? serveAt}) {
  final now=DateTime.now().toUtc();
  if(serveAt!=null && !serveAt.toUtc().isAfter(now))throw const FormatException('Choose a future serving time.');
  final graph=graphForRecipe(recipe);
  final busy=<TimeWindow>[];
  for(final row in unavailable) {
    final start=row.date('startAt'),end=row.date('endAt');
    if(start!=null&&end!=null&&end.isAfter(start))busy.add(TimeWindow(start.toUtc(),end.toUtc()));
  }
  final reservations=<ResourceReservation>[];
  for(final bake in bakes.where((b)=>!['complete','abandoned','archived'].contains(b.text('status')))) {
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
    anchor:(serveAt??now).toUtc(),direction:serveAt==null?PlanningDirection.forward:PlanningDirection.backward,
    horizon:TimeWindow(now,now.add(const Duration(days:14))),
    kitchenTimeZone:'UTC',unavailable:busy,resourceCapacities:allResources,reservations:reservations));
  if(result.candidates.isEmpty)throw StateError(result.issues.isEmpty
    ? 'No plan was found within the draft method and current availability. Change the target or availability. No cold-rest recovery is validated for this draft.'
    : result.issues.map((i)=>i.message).toSet().join(' '));
  return result.candidates.first;
}
RecipeGraph graphForRecipe(Map<String,dynamic> recipe) {
  final raw=(recipe['steps'] as List).cast<Map>();
  return RecipeGraph(recipeVersion:'${recipe['id']}:${recipe['version']}',profileVersion:'draft-estimates-1',steps:raw.map((s) {
    final minutes=(s['durationMinutes'] as num).toInt();
    final duration=Duration(minutes:minutes);
    final active=s['kind']=='handsOn';
    return RecipeStep(id:s['id'] as String,title:s['title'] as String,
      nominalDuration:duration,dependencies:List<String>.from(s['after'] as List? ?? []),
      readinessGate:s['kind']=='check',handsOn:active?[ActiveInterval(Duration.zero,duration)]:s['kind']=='check'?[ActiveInterval(duration-const Duration(minutes:1),const Duration(minutes:1))]:[],
      resources:{for(final r in s['resources'] as List? ?? [])r.toString():1});
  }).toList());
}
