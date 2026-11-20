import 'package:baking_domain/baking_domain.dart';
import 'app_store.dart';
import 'fermentation.dart';

typedef BakeScheduleOptions = ({
  Map<String, dynamic> recipe, List<ScheduleCandidate> candidates,
  DateTime? serveAt, DateTime? startAt, String? warning,
});

BakeScheduleOptions prepareBakeSchedule(Map<String, dynamic> recipe,
  List<AppRecord> unavailable, List<AppRecord> bakes, Map<String, int> capacities,
  {DateTime? serveAt, DateTime? startAt, double doughTemperatureC = 24, bool shiftAnchor = true}) {
  final method = recipeAtDoughTemperature(recipe, doughTemperatureC);
  final referenceWarning = doughTemperatureC < 18 || doughTemperatureC > 27
    ? 'This kitchen temperature is outside the forecast range. The schedule uses the recipe’s reference timings.'
    : null;
  final now = DateTime.now().toUtc();
  final windows = unavailable
    .where((record) => record.date('startAt') != null && (record.date('endAt')?.isAfter(now) ?? false))
    .toList()..sort((a, b) => a.date('endAt')!.compareTo(b.date('endAt')!));

  BakeScheduleOptions? tryMethod(Map<String, dynamic> proposed, DateTime? mix, DateTime? serve, [String? warning]) {
    try {
      final candidates = planRecipeCandidates(proposed, windows, bakes, capacities, serveAt: serve, startAt: mix);
      return (recipe: proposed, candidates: candidates, startAt: mix, serveAt: serve,
        warning: [referenceWarning, warning].whereType<String>().isEmpty ? null :
          [referenceWarning, warning].whereType<String>().join(' '));
    } on StateError {
      return null;
    }
  }

  if (windows.isNotEmpty && (startAt != null || serveAt != null) && recipe['coldBulkMinutes'] == null) {
    ScheduleCandidate? baseline;
    try {
      baseline = planRecipe(method, const [], bakes, capacities, startAt: startAt, serveAt: serveAt);
    } on StateError {
      // The same equipment is reserved even with no time-away constraints.
    }
    if (baseline != null) {
      final tasks = baseline.tasks.where((task) => ['bulk', 'rest', 'wait1'].contains(task.stepId));
      for (final task in tasks) {
        for (final window in windows) {
          final leaves = window.date('startAt')!, back = window.date('endAt')!;
          if (!back.isAfter(task.end) || !leaves.isBefore(task.end)) continue;
          if (startAt != null && leaves.isBefore(task.start.add(const Duration(minutes: 3)))) continue;
          final isBulk = task.stepId == 'bulk';
          if (!isBulk && (back.difference(task.start).inMinutes > 120)) continue;
          final first = startAt != null
            ? (back.difference(task.start).inSeconds / 60).ceil() - 3
            : (back.difference(leaves).inSeconds / 60).ceil().clamp(isBulk ? 60 : 30, 481);
          final lengths = startAt != null ? [first] : [
            for (var duration = first; duration <= (isBulk ? 480 : 120); duration += 15) duration,
          ];
          for (final minutes in lengths) {
            final cold = coldBulkOption(method, coldMinutes: minutes,
              stageId: task.stepId, kitchenTemperatureC: doughTemperatureC);
            if (cold == null) continue;
            final fit = tryMethod(cold, startAt, serveAt,
              'This plan uses a fridge hold to fit your time away. Check the dough when it comes out. Cooling speed varies by dough and container.');
            if (fit != null) return fit;
          }
        }
      }
    }
  }
  final original = tryMethod(method, startAt, serveAt);
  if (original != null) return original;

  if (shiftAnchor && windows.isNotEmpty && (startAt != null || serveAt != null)) {
    final requested = startAt ?? serveAt!;
    final limit = now.add(const Duration(days: 13));
    final offsetCandidates = <DateTime>{
      for (final minutes in [15, 30, 45, 60, 90, 120, 180, 240, 360, 720, 1440])
        requested.add(Duration(minutes: minutes)),
      for (final window in windows)
        if (window.date('endAt')!.isAfter(requested)) window.date('endAt')!,
    }.where((date) => date.isAfter(now) && date.isBefore(limit)).toList()..sort();
    for (final anchor in offsetCandidates) {
      final fit = tryMethod(method, startAt == null ? null : anchor, serveAt == null ? null : anchor,
        startAt == null ? 'Your original ready time overlaps time away. This option finishes later.'
          : 'Your original start overlaps time away. This option starts later.');
      if (fit != null) return fit;
    }
  }
  throw const FormatException('There is no workable timeline for these times. Try a shorter time away, a different mix time or a later ready time.');
}


/// Converts authored content and local commitments to the same deterministic
/// planner used by the pure domain tests. Draft estimates stay labelled drafts.
ScheduleCandidate planRecipe(Map<String,dynamic> recipe, List<AppRecord> unavailable,
    List<AppRecord> bakes, Map<String,int> capacities, {DateTime? serveAt,DateTime? startAt}) =>
    planRecipeCandidates(recipe, unavailable, bakes, capacities, serveAt: serveAt, startAt: startAt).first;

List<ScheduleCandidate> planRecipeCandidates(Map<String,dynamic> recipe, List<AppRecord> unavailable,
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
    final otherGraph=graphForRecipe({
      ...Map<String,dynamic>.from(snapshot),
      if (bake.fields['steps'] is List && (bake.fields['steps'] as List).isNotEmpty)
        'steps': bake.fields['steps'],
    });
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
  return result.candidates;
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
