import 'common.dart';

enum PlanningStatus { feasible, infeasible, unsupported, searchIncomplete }
enum PlanningDirection { forward, backward }

final class TimeWindow {
 final DateTime start,end;
 TimeWindow(this.start,this.end) {
  if (!start.isUtc || !end.isUtc || end.isBefore(start)) throw ArgumentError('Use ordered UTC instants');
 }
 bool contains(DateTime a,DateTime b)=>!a.isBefore(start)&&!b.isAfter(end);
 bool overlaps(DateTime a,DateTime b)=>a.isBefore(end)&&b.isAfter(start);
 Map<String,dynamic> toJson()=>{'start':start.toIso8601String(),'end':end.toIso8601String()};
 factory TimeWindow.fromJson(Map<String,dynamic> j)=>TimeWindow(DateTime.parse(j['start']).toUtc(),DateTime.parse(j['end']).toUtc());
}
final class ActiveInterval {
 final Duration offset,duration;
 ActiveInterval(this.offset,this.duration) {
  if (offset.isNegative||duration.isNegative) throw ArgumentError('Active intervals must be nonnegative');
 }
 Map<String,dynamic> toJson()=>{'offsetSeconds':offset.inSeconds,'durationSeconds':duration.inSeconds};
}
final class RecipeStep {
 final String id,title;
 final List<String> dependencies;
 final Duration minimumDuration,nominalDuration,maximumDuration;
 final Duration maxWaitAfterDependencies;
 final List<ActiveInterval> handsOn;
 final Map<String,int> resources;
 final bool readinessGate;
 final TimeWindow? startWindow;
 RecipeStep({required this.id,required this.title,required this.nominalDuration,
  Duration? minimumDuration,Duration? maximumDuration,List<String> dependencies=const [],
  this.maxWaitAfterDependencies=Duration.zero,List<ActiveInterval> handsOn=const [],
  Map<String,int> resources=const {},this.readinessGate=false,this.startWindow})
  : minimumDuration=minimumDuration??nominalDuration,maximumDuration=maximumDuration??nominalDuration,
  dependencies=List.unmodifiable(dependencies),handsOn=List.unmodifiable(handsOn),resources=Map.unmodifiable(resources) {
  if (id.isEmpty || title.isEmpty || this.minimumDuration.isNegative || nominalDuration<this.minimumDuration || this.maximumDuration<nominalDuration || maxWaitAfterDependencies.isNegative || resources.values.any((v)=>v<1) || handsOn.any((a)=>a.offset+a.duration>this.minimumDuration)) {
   throw const DomainException('GRAPH_INVALID_STEP','Check durations, active intervals and resource requirements.');
  }
 }
 bool get variable=>minimumDuration!=maximumDuration;
 Map<String,dynamic> toJson()=>{'id':id,'title':title,'dependencies':dependencies,'minimumSeconds':minimumDuration.inSeconds,'nominalSeconds':nominalDuration.inSeconds,'maximumSeconds':maximumDuration.inSeconds,'maxWaitSeconds':maxWaitAfterDependencies.inSeconds,'handsOn':handsOn.map((x)=>x.toJson()).toList(),'resources':resources,'readinessGate':readinessGate,'startWindow':startWindow?.toJson()};
 factory RecipeStep.fromJson(Map<String,dynamic> j)=>RecipeStep(id:j['id'],title:j['title'],nominalDuration:Duration(seconds:j['nominalSeconds']),minimumDuration:Duration(seconds:j['minimumSeconds']),maximumDuration:Duration(seconds:j['maximumSeconds']),dependencies:List<String>.from(j['dependencies']),maxWaitAfterDependencies:Duration(seconds:j['maxWaitSeconds']),handsOn:(j['handsOn'] as List).map((x)=>ActiveInterval(Duration(seconds:x['offsetSeconds']),Duration(seconds:x['durationSeconds']))).toList(),resources:Map<String,int>.from(j['resources']),readinessGate:j['readinessGate'],startWindow:j['startWindow']==null?null:TimeWindow.fromJson(j['startWindow']));
}
final class RecipeGraph {
 final String recipeVersion,profileVersion;
 final List<RecipeStep> steps;
 RecipeGraph({required this.recipeVersion,required this.profileVersion,required List<RecipeStep> steps}):steps=List.unmodifiable(steps);
 List<RecipeStep> topologicalOrder() {
  final byId={for(final s in steps)s.id:s};
  if (steps.isEmpty || byId.length!=steps.length) throw const DomainException('GRAPH_INVALID_ID','Steps must have unique identifiers and not be empty.');
  final ordered=<RecipeStep>[],visiting=<String>{},visited=<String>{};
  void visit(RecipeStep step) {
   if (visiting.contains(step.id)) throw const DomainException('GRAPH_CYCLE','Recipe dependencies contain a cycle.');
   if (visited.contains(step.id)) return;
   visiting.add(step.id);
   for(final id in step.dependencies) {
    final dep=byId[id];
    if(dep==null) throw DomainException('GRAPH_MISSING_DEPENDENCY','A recipe dependency is missing.',{'step':step.id,'dependency':id});
    visit(dep);
   }
   visiting.remove(step.id);visited.add(step.id);ordered.add(step);
  }
  for(final step in steps)visit(step);
  return ordered;
 }
 Map<String,dynamic> toJson()=>{'recipeVersion':recipeVersion,'profileVersion':profileVersion,'steps':steps.map((s)=>s.toJson()).toList()};
 factory RecipeGraph.fromJson(Map<String,dynamic> j)=>RecipeGraph(recipeVersion:j['recipeVersion'],profileVersion:j['profileVersion'],steps:(j['steps'] as List).map((s)=>RecipeStep.fromJson(s)).toList());
}
final class ResourceReservation {
 final String resourceId,owner;
 final int units;
 final TimeWindow window;
 ResourceReservation({required this.resourceId,required this.owner,required this.window,this.units=1}) {
  if(units<1)throw ArgumentError('Resource units must be positive');
 }
}
final class ScheduleTask {
 final String stepId;
 final DateTime start,end;
 final bool actual,readinessGate;
 ScheduleTask({required this.stepId,required this.start,required this.end,this.actual=false,this.readinessGate=false}) {
  if(!start.isUtc||!end.isUtc||end.isBefore(start))throw ArgumentError('Use ordered UTC task instants');
 }
 Duration get duration=>end.difference(start);
 Map<String,dynamic> toJson()=>{'stepId':stepId,'start':start.toIso8601String(),'end':end.toIso8601String(),'actual':actual,'readinessGate':readinessGate};
 factory ScheduleTask.fromJson(Map<String,dynamic> j)=>ScheduleTask(stepId:j['stepId'],start:DateTime.parse(j['start']).toUtc(),end:DateTime.parse(j['end']).toUtc(),actual:j['actual']??false,readinessGate:j['readinessGate']??false);
}
final class ScheduleCandidate {
 final List<ScheduleTask> tasks;
 final String recipeVersion,profileVersion,engineVersion,kitchenTimeZone;
 /// A candidate is never labelled biologically robust from three duration samples.
 final bool requiresObservation;
 final List<String> assumptions;
 ScheduleCandidate({required List<ScheduleTask> tasks,required this.recipeVersion,required this.profileVersion,required this.kitchenTimeZone,this.engineVersion='1.0.0',required this.requiresObservation,List<String> assumptions=const []}) :tasks=List.unmodifiable(tasks),assumptions=List.unmodifiable(assumptions);
 DateTime get startsAt=>tasks.map((t)=>t.start).reduce((a,b)=>a.isBefore(b)?a:b);
 DateTime get finishesAt=>tasks.map((t)=>t.end).reduce((a,b)=>a.isAfter(b)?a:b);
 ScheduleTask task(String id)=>tasks.firstWhere((t)=>t.stepId==id);
 Map<String,dynamic> toJson()=>{'tasks':tasks.map((t)=>t.toJson()).toList(),'recipeVersion':recipeVersion,'profileVersion':profileVersion,'engineVersion':engineVersion,'kitchenTimeZone':kitchenTimeZone,'requiresObservation':requiresObservation,'assumptions':assumptions};
 factory ScheduleCandidate.fromJson(Map<String,dynamic> j)=>ScheduleCandidate(tasks:(j['tasks'] as List).map((t)=>ScheduleTask.fromJson(t)).toList(),recipeVersion:j['recipeVersion'],profileVersion:j['profileVersion'],kitchenTimeZone:j['kitchenTimeZone'],engineVersion:j['engineVersion'],requiresObservation:j['requiresObservation'],assumptions:List<String>.from(j['assumptions']));
}
final class PlanningRequest {
 final RecipeGraph graph;
 final PlanningDirection direction;
 /// Forward: earliest start. Backward: exact finish/serve instant, cooling included.
 final DateTime anchor;
 final TimeWindow horizon;
 final String kitchenTimeZone;
 final List<TimeWindow> unavailable;
 final Map<String,int> resourceCapacities;
 final List<ResourceReservation> reservations;
 final Map<String,ScheduleTask> completed;
 final int maxSearchNodes,maxCandidates;
 PlanningRequest({required this.graph,required this.anchor,required this.horizon,
  this.direction=PlanningDirection.forward,this.kitchenTimeZone='UTC',List<TimeWindow> unavailable=const [],
  Map<String,int> resourceCapacities=const {},List<ResourceReservation> reservations=const [],
  Map<String,ScheduleTask> completed=const {},this.maxSearchNodes=20000,this.maxCandidates=3})
  :unavailable=List.unmodifiable(unavailable),resourceCapacities=Map.unmodifiable(resourceCapacities),reservations=List.unmodifiable(reservations),completed=Map.unmodifiable(completed) {
   if(!anchor.isUtc||maxSearchNodes<1||maxCandidates<1||kitchenTimeZone.isEmpty||resourceCapacities.values.any((n)=>n<0))throw ArgumentError('Invalid planning parameters');
 }
}
final class PlanningIssue {
 final String code,message;
 final String? stepId,resourceId;
 const PlanningIssue(this.code,this.message,{this.stepId,this.resourceId});
 Map<String,dynamic> toJson()=>{'code':code,'message':message,'stepId':stepId,'resourceId':resourceId};
}
final class PlanningResult {
 final PlanningStatus status;
 final List<ScheduleCandidate> candidates;
 final List<PlanningIssue> issues;
 final int searchedNodes;
 final bool searchExhausted;
 PlanningResult(this.status,List<ScheduleCandidate> candidates,List<PlanningIssue> issues,this.searchedNodes,{required this.searchExhausted}):candidates=List.unmodifiable(candidates),issues=List.unmodifiable(issues);
}
final class PlanValidation {
 final List<PlanningIssue> issues;
 PlanValidation(List<PlanningIssue> issues):issues=List.unmodifiable(issues);
 bool get isValid=>issues.isEmpty;
}

/// Bounded deterministic boundary search. It cannot certify global optimality or
/// robust feasibility across continuous fermentation ranges. Variable-duration
/// no-fit results are SEARCH_INCOMPLETE, never mathematical infeasibility.
final class PlanningEngine {
 const PlanningEngine();
 PlanningResult solve(PlanningRequest request) {
  late List<RecipeStep> order;
  try {order=request.graph.topologicalOrder();} on DomainException catch(e) {
   return PlanningResult(PlanningStatus.unsupported,[],[PlanningIssue(e.code,e.message)],0,searchExhausted:true);
  }
  final ids=order.map((s)=>s.id).toSet();
  if(request.completed.keys.any((id)=>!ids.contains(id)))return PlanningResult(PlanningStatus.unsupported,[],[const PlanningIssue('HISTORY_UNKNOWN_STEP','A completed step is not in this recipe version.')],0,searchExhausted:true);
  for(final s in order) {
   for(final entry in s.resources.entries) {
    if((request.resourceCapacities[entry.key]??0)<entry.value)return PlanningResult(PlanningStatus.infeasible,[],[PlanningIssue('RESOURCE_CAPACITY_CONFLICT','Required equipment capacity is unavailable.',stepId:s.id,resourceId:entry.key)],0,searchExhausted:true);
   }
  }
  final backward=request.direction==PlanningDirection.backward;
  final traversal=backward?order.reversed.toList():order;
  final placed=<String,ScheduleTask>{};
  final candidates=<ScheduleCandidate>[];
  final issues=<String,PlanningIssue>{};
  var nodes=0,cutoff=false;
  DateTime later(DateTime a,DateTime b)=>a.isAfter(b)?a:b;
  DateTime earlier(DateTime a,DateTime b)=>a.isBefore(b)?a:b;
  void search(int index) {
   if(candidates.length>=request.maxCandidates)return;
   if(nodes>=request.maxSearchNodes){cutoff=true;return;}
   if(index==traversal.length) {
    final candidate=ScheduleCandidate(tasks:order.map((s)=>placed[s.id]!).toList(),recipeVersion:request.graph.recipeVersion,profileVersion:request.graph.profileVersion,kitchenTimeZone:request.kitchenTimeZone,requiresObservation:order.any((s)=>s.variable||s.readinessGate),assumptions:['Recipe-specific duration bounds supplied by the caller.','Dates resolved to UTC by the kitchen timezone adapter.','A schedule is not proof that dough is ready.']);
    final valid=validate(candidate,request);
    if(valid.isValid&&!candidates.any((c)=>canonicalJson(c.toJson())==canonicalJson(candidate.toJson())))candidates.add(candidate);
    for(final issue in valid.issues)issues['${issue.code}:${issue.stepId}:${issue.resourceId}']=issue;
    return;
   }
   final step=traversal[index];
   final propagated=_propagate(order,request,placed);
   if(propagated==null)return;
   final bounds=propagated[step.id]!;
   final actual=request.completed[step.id];
   final durations=actual!=null?[actual.duration]:_durationOptions(step,placed,order,request);
   for(final duration in durations) {
    var lo=DateTime.fromMicrosecondsSinceEpoch(bounds.startLo,isUtc:true);
    var hi=DateTime.fromMicrosecondsSinceEpoch(bounds.startHi,isUtc:true);
    lo=later(lo,DateTime.fromMicrosecondsSinceEpoch(bounds.endLo,isUtc:true).subtract(duration));
    hi=earlier(hi,DateTime.fromMicrosecondsSinceEpoch(bounds.endHi,isUtc:true).subtract(duration));
    if(step.startWindow!=null){lo=later(lo,step.startWindow!.start);hi=earlier(hi,step.startWindow!.end);}
    if(backward) {
     final children=order.where((s)=>s.dependencies.contains(step.id));
     if(children.isEmpty){hi=earlier(hi,request.anchor.subtract(duration));}
     for(final child in children){final next=placed[child.id];if(next!=null){hi=earlier(hi,next.start.subtract(duration));lo=later(lo,next.start.subtract(duration+child.maxWaitAfterDependencies));}}
    } else {
     if(step.dependencies.isEmpty){lo=later(lo,request.anchor);}
     for(final dep in step.dependencies){final before=placed[dep];if(before!=null){lo=later(lo,before.end);hi=earlier(hi,before.end.add(step.maxWaitAfterDependencies));}}
    }
    if(actual!=null){lo=later(lo,actual.start);hi=earlier(hi,actual.start);}
    if(hi.isBefore(lo))continue;
    final starts=<DateTime>{backward?hi:lo,backward?lo:hi};
    for(final busy in request.unavailable){for(final active in step.handsOn){starts.add(busy.start.subtract(active.offset+active.duration));starts.add(busy.end.subtract(active.offset));}}
    for(final reserved in [...request.reservations,..._reservations(placed.values,order)]) {
     if(step.resources.containsKey(reserved.resourceId)){starts.add(reserved.window.start.subtract(duration));starts.add(reserved.window.end);}
    }
    final sorted=starts.where((s)=>!s.isBefore(lo)&&!s.isAfter(hi)).toList()..sort((a,b)=>backward?b.compareTo(a):a.compareTo(b));
    for(final start in sorted){
     if(nodes++>=request.maxSearchNodes){cutoff=true;return;}
     final task=ScheduleTask(stepId:step.id,start:start,end:start.add(duration),actual:actual!=null,readinessGate:step.readinessGate);
     final partial=_taskIssues(task,step,request,[...request.reservations,..._reservations(placed.values,order)]);
     if(partial.isNotEmpty){for(final issue in partial)issues['${issue.code}:${issue.stepId}:${issue.resourceId}']=issue;continue;}
     placed[step.id]=task;search(index+1);placed.remove(step.id);
     if(candidates.length>=request.maxCandidates||cutoff)return;
    }
   }
  }
  search(0);
  if(candidates.isNotEmpty)return PlanningResult(PlanningStatus.feasible,candidates,[],nodes,searchExhausted:!cutoff&&candidates.length<request.maxCandidates);
  final incomplete=cutoff||order.any((s)=>s.variable);
  if(incomplete)issues['SEARCH_INCOMPLETE']=const PlanningIssue('SEARCH_INCOMPLETE','No candidate was found within this bounded search. Change the target or review the recipe; this is not proof that no plan exists.');
  if(issues.isEmpty)issues['DEADLINE_INFEASIBLE']=const PlanningIssue('DEADLINE_INFEASIBLE','The supplied fixed recipe cannot fit this target, horizon and history.');
  return PlanningResult(incomplete?PlanningStatus.searchIncomplete:PlanningStatus.infeasible,[],issues.values.toList(),nodes,searchExhausted:!cutoff);
 }
 PlanValidation validate(ScheduleCandidate candidate,PlanningRequest request) {
  final issues=<PlanningIssue>[];
  final graph=request.graph;
  if(candidate.recipeVersion!=graph.recipeVersion||candidate.profileVersion!=graph.profileVersion||candidate.kitchenTimeZone!=request.kitchenTimeZone)issues.add(const PlanningIssue('VERSION_MISMATCH','Schedule belongs to another recipe/profile version.'));
  final tasks={for(final t in candidate.tasks)t.stepId:t};
  if(tasks.length!=candidate.tasks.length||tasks.length!=graph.steps.length)issues.add(const PlanningIssue('GRAPH_TASK_MISMATCH','Schedule must contain every step exactly once.'));
  for(final step in graph.steps){
   final task=tasks[step.id];if(task==null){issues.add(PlanningIssue('GRAPH_TASK_MISMATCH','Step is absent.',stepId:step.id));continue;}
   final actual=request.completed[step.id];
   if(actual!=null&&(task.start!=actual.start||task.end!=actual.end))issues.add(PlanningIssue('COMPLETED_HISTORY_CHANGED','Completed history cannot move.',stepId:step.id));
   if(actual==null&&(task.duration<step.minimumDuration||task.duration>step.maximumDuration))issues.add(PlanningIssue('DURATION_OUT_OF_RANGE','Duration is outside the supplied recipe range.',stepId:step.id));
   if(!request.horizon.contains(task.start,task.end))issues.add(PlanningIssue('HORIZON_CONFLICT','Task is outside the planning horizon.',stepId:step.id));
   if(step.startWindow!=null&&!step.startWindow!.contains(task.start,task.start))issues.add(PlanningIssue('STEP_WINDOW_CONFLICT','Task begins outside its allowed window.',stepId:step.id));
   for(final dep in step.dependencies){final before=tasks[dep];if(before!=null){final gap=task.start.difference(before.end);if(gap.isNegative||gap>step.maxWaitAfterDependencies)issues.add(PlanningIssue('PRECEDENCE_CONFLICT','Dependency wait is outside the recipe range.',stepId:step.id));}}
   issues.addAll(_taskIssues(task,step,request,[...request.reservations,..._reservations(candidate.tasks.where((t)=>t.stepId!=step.id),graph.steps)]));
  }
  if(candidate.tasks.isNotEmpty){
   final anchorOkay=request.direction==PlanningDirection.backward?candidate.finishesAt==request.anchor:candidate.startsAt==request.anchor;
   if(!anchorOkay)issues.add(const PlanningIssue('ANCHOR_MISMATCH','Schedule does not respect its requested anchor.'));
  }
  return PlanValidation(issues);
 }
 ReplanProposal proposeRecovery({required ScheduleCandidate previous,required PlanningRequest request,required int expectedRevision}) {
  final result=solve(request);
  return ReplanProposal(expectedRevision,previous,result,[for(final c in result.candidates)[for(final t in c.tasks)if(previous.tasks.any((p)=>p.stepId==t.stepId&&(p.start!=t.start||p.end!=t.end)))t.stepId]]);
 }
 Map<String,_TimingBounds>? _propagate(List<RecipeStep> order,PlanningRequest request,Map<String,ScheduleTask> placed) {
  final bounds=<String,_TimingBounds>{};
  final actuals={...request.completed,...placed};
  final a=request.horizon.start.microsecondsSinceEpoch,z=request.horizon.end.microsecondsSinceEpoch,anchor=request.anchor.microsecondsSinceEpoch;
  for(final step in order){
   final actual=actuals[step.id];
   final min=(actual?.duration??step.minimumDuration).inMicroseconds,max=(actual?.duration??step.maximumDuration).inMicroseconds;
   final b=_TimingBounds(a,z-min,a+min,z,min,max);
   if(actual!=null){b.startLo=actual.start.microsecondsSinceEpoch;b.startHi=b.startLo;b.endLo=actual.end.microsecondsSinceEpoch;b.endHi=b.endLo;}
   if(step.startWindow!=null){b.raiseStart(step.startWindow!.start.microsecondsSinceEpoch);b.lowerStart(step.startWindow!.end.microsecondsSinceEpoch);}
   if(request.direction==PlanningDirection.forward&&step.dependencies.isEmpty)b.raiseStart(anchor);
   if(request.direction==PlanningDirection.backward&&!order.any((s)=>s.dependencies.contains(step.id)))b.lowerEnd(anchor);
   bounds[step.id]=b;
  }
  // Interval propagation also carries a later load's oven constraint through
  // an earlier load's bake/cool/ready branch. No arbitrary dough hold is added.
  for(var pass=0;pass<order.length*2+2;pass++){
   var changed=false;
   for(final step in order){
    final b=bounds[step.id]!;
    changed=b.raiseEnd(b.startLo+b.minimum)||changed;
    changed=b.lowerEnd(b.startHi+b.maximum)||changed;
    changed=b.raiseStart(b.endLo-b.maximum)||changed;
    changed=b.lowerStart(b.endHi-b.minimum)||changed;
    for(final dep in step.dependencies){
     final parent=bounds[dep]!,gap=step.maxWaitAfterDependencies.inMicroseconds;
     changed=b.raiseStart(parent.endLo)||changed;
     changed=b.lowerStart(parent.endHi+gap)||changed;
     changed=parent.raiseEnd(b.startLo-gap)||changed;
     changed=parent.lowerEnd(b.startHi)||changed;
    }
   }
   if(bounds.values.any((b)=>b.startLo>b.startHi||b.endLo>b.endHi||b.startLo<a||b.endHi>z))return null;
   if(!changed)break;
  }
  return bounds;
 }
 List<Duration> _durationOptions(RecipeStep step,Map<String,ScheduleTask> placed,List<RecipeStep> order,PlanningRequest request) {
  final durations=<Duration>{step.nominalDuration,step.minimumDuration,step.maximumDuration};
  if(step.variable){
   final known={...request.completed,...placed};
   final starts=<DateTime>{
    for(final dep in step.dependencies)if(known.containsKey(dep))known[dep]!.end,
    if(step.startWindow!=null)step.startWindow!.start,
    if(step.startWindow!=null)step.startWindow!.end,
   };
   if(step.dependencies.isEmpty&&request.direction==PlanningDirection.forward)starts.add(request.anchor);
   final children=order.where((s)=>s.dependencies.contains(step.id));
   final ends=<DateTime>{
    for(final child in children)if(known.containsKey(child.id))known[child.id]!.start,
    if(children.isEmpty&&request.direction==PlanningDirection.backward)request.anchor,
    for(final w in request.unavailable)w.start,
    for(final w in request.unavailable)w.end,
    for(final r in request.reservations)r.window.start,
    for(final r in request.reservations)r.window.end,
   };
   // Include exact duration needed to bridge fixed actuals or a busy boundary.
   // These are still only placements inside the caller's reviewed bounds.
   for(final a in starts){for(final b in ends){final d=b.difference(a);if(d>=step.minimumDuration&&d<=step.maximumDuration)durations.add(d);}}
  }
  return durations.toList();
 }
 List<ResourceReservation> _reservations(Iterable<ScheduleTask> tasks,List<RecipeStep> steps) {
  final byId={for(final s in steps)s.id:s};
  return [for(final t in tasks)for(final r in byId[t.stepId]?.resources.entries??<MapEntry<String,int>>[])ResourceReservation(resourceId:r.key,owner:t.stepId,window:TimeWindow(t.start,t.end),units:r.value)];
 }
 List<PlanningIssue> _taskIssues(ScheduleTask task,RecipeStep step,PlanningRequest request,List<ResourceReservation> reservations) {
  final issues=<PlanningIssue>[];
  // Actual events remain true even if recorded during a formerly busy block.
  if(!task.actual){for(final active in step.handsOn){final a=task.start.add(active.offset),b=task.start.add(active.offset+active.duration);if(request.unavailable.any((w)=>w.overlaps(a,b)))issues.add(PlanningIssue('AVAILABILITY_CONFLICT','Hands-on work overlaps unavailable time.',stepId:step.id));}}
  for(final demand in step.resources.entries){
   final related=reservations.where((r)=>r.resourceId==demand.key&&r.window.overlaps(task.start,task.end)).toList();
   final instants=<DateTime>{task.start,...related.map((r)=>r.window.start).where((t)=>!t.isBefore(task.start)&&t.isBefore(task.end))};
   final capacity=request.resourceCapacities[demand.key]??0;
   if(instants.any((at)=>demand.value+related.where((r)=>!at.isBefore(r.window.start)&&at.isBefore(r.window.end)).fold<int>(0,(a,r)=>a+r.units)>capacity))issues.add(PlanningIssue('RESOURCE_CAPACITY_CONFLICT','Equipment is already reserved.',stepId:step.id,resourceId:demand.key));
  }
  return issues;
 }
}
final class ReplanProposal {
 final int expectedRevision;
 final ScheduleCandidate previous;
 final PlanningResult result;
 final List<List<String>> changedStepIds;
 const ReplanProposal(this.expectedRevision,this.previous,this.result,this.changedStepIds);
 void requireCurrentRevision(int revision){if(revision!=expectedRevision)throw const DomainException('REVISION_CONFLICT','Bake changed; generate a new proposal.');}
}

final class _TimingBounds {
 int startLo,startHi,endLo,endHi;
 final int minimum,maximum;
 _TimingBounds(this.startLo,this.startHi,this.endLo,this.endHi,this.minimum,this.maximum);
 bool raiseStart(int n){if(n<=startLo)return false;startLo=n;return true;}
 bool lowerStart(int n){if(n>=startHi)return false;startHi=n;return true;}
 bool raiseEnd(int n){if(n<=endLo)return false;endLo=n;return true;}
 bool lowerEnd(int n){if(n>=endHi)return false;endHi=n;return true;}
}
