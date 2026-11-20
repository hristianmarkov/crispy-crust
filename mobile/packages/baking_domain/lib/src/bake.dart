import 'common.dart';

enum BakeState { draft,planned,active,cooling,complete,abandoned,archived }
enum BakeEventType { planAccepted,bakeStarted,stepStarted,stepCompleted,stepSkipped,observationRecorded,coolingStarted,bakeCompleted,bakeAbandoned,bakeArchived,recordCorrected }
final class BakeEvent {
 final String id,operationId,bakeId,actorId;
 final BakeEventType type;
 final DateTime occurredAt,recordedAt;
 final int sequence;
 final Map<String,dynamic> payload;
 BakeEvent({required this.id,required this.operationId,required this.bakeId,required this.actorId,required this.type,required this.occurredAt,required this.recordedAt,required this.sequence,Map<String,dynamic> payload=const {}}):payload=immutableJsonMap(payload) {
  if([id,operationId,bakeId,actorId].any((s)=>s.isEmpty)||!occurredAt.isUtc||!recordedAt.isUtc||sequence<1)throw ArgumentError('Event identity, sequence and UTC times are required');
 }
 Map<String,dynamic> toJson()=>{'id':id,'operationId':operationId,'bakeId':bakeId,'actorId':actorId,'type':type.name,'occurredAt':occurredAt.toIso8601String(),'recordedAt':recordedAt.toIso8601String(),'sequence':sequence,'payload':payload};
 factory BakeEvent.fromJson(Map<String,dynamic> j)=>BakeEvent(id:j['id'],operationId:j['operationId'],bakeId:j['bakeId'],actorId:j['actorId'],type:BakeEventType.values.byName(j['type']),occurredAt:DateTime.parse(j['occurredAt']).toUtc(),recordedAt:DateTime.parse(j['recordedAt']).toUtc(),sequence:j['sequence'],payload:Map<String,dynamic>.from(j['payload']));
}
final class BakeSnapshot {
 final String id,recipeVersion;
 final BakeState state;
 final int revision;
 final List<BakeEvent> events;
 final Map<String,DateTime> completedSteps,startedSteps;
 final Set<String> skippedSteps;
 final List<String> reconciliationWarnings;
 final String? scheduleId;
 BakeSnapshot({required this.id,required this.recipeVersion,this.state=BakeState.draft,this.revision=0,List<BakeEvent> events=const [],Map<String,DateTime> completedSteps=const {},Map<String,DateTime> startedSteps=const {},Set<String> skippedSteps=const {},List<String> reconciliationWarnings=const [],this.scheduleId})
 :events=List.unmodifiable(events),completedSteps=Map.unmodifiable(completedSteps),startedSteps=Map.unmodifiable(startedSteps),skippedSteps=Set.unmodifiable(skippedSteps),reconciliationWarnings=List.unmodifiable(reconciliationWarnings);
 Map<String,dynamic> toJson()=>{'id':id,'recipeVersion':recipeVersion,'state':state.name,'revision':revision,'events':events.map((e)=>e.toJson()).toList(),'completedSteps':completedSteps.map((k,v)=>MapEntry(k,v.toIso8601String())),'startedSteps':startedSteps.map((k,v)=>MapEntry(k,v.toIso8601String())),'skippedSteps':skippedSteps.toList()..sort(),'reconciliationWarnings':reconciliationWarnings,'scheduleId':scheduleId};
}
final class BakeReducer {
 const BakeReducer();
 BakeSnapshot apply(BakeSnapshot previous,BakeEvent event) {
  if(previous.id!=event.bakeId)throw const DomainException('BAKE_ID_MISMATCH','Event belongs to another bake.');
  final duplicates=previous.events.where((e)=>e.id==event.id||e.operationId==event.operationId);
  if(duplicates.isNotEmpty){
   if(canonicalJson(duplicates.first.toJson())!=canonicalJson(event.toJson()))throw const DomainException('IDEMPOTENCY_MISMATCH','Duplicate operation has different content.');
   return previous;
  }
  if(event.sequence!=previous.revision+1)throw const DomainException('REVISION_CONFLICT','Events must be accepted in aggregate sequence order.');
  var state=previous.state;
  var schedule=previous.scheduleId;
  final done=Map<String,DateTime>.from(previous.completedSteps),started=Map<String,DateTime>.from(previous.startedSteps);
  final skipped=Set<String>.from(previous.skippedSteps),warnings=List<String>.from(previous.reconciliationWarnings);
  final step=event.payload['stepId'] as String?;
  void requireState(Set<BakeState> allowed){if(!allowed.contains(state))throw DomainException('BAKE_ILLEGAL_TRANSITION','${event.type.name} cannot apply in ${state.name}.');}
  void requireStep(){if(step==null||step.isEmpty)throw const DomainException('EVENT_MISSING_STEP','Step identifier is required.');}
  switch(event.type){
   case BakeEventType.planAccepted:
    requireState({BakeState.draft,BakeState.planned,BakeState.active,BakeState.cooling});
    final value=event.payload['scheduleId'];if(value is! String||value.isEmpty)throw const DomainException('EVENT_MISSING_PLAN','Schedule identifier is required.');
    schedule=value;if(state==BakeState.draft)state=BakeState.planned;
   case BakeEventType.bakeStarted:
    requireState({BakeState.planned});state=BakeState.active;
   case BakeEventType.stepStarted:
    requireState({BakeState.active});requireStep();
    if(done.containsKey(step)||skipped.contains(step))throw const DomainException('STEP_ALREADY_FINISHED','This stage is already finished.');
    if(started.containsKey(step)){warnings.add('Duplicate start for $step kept in history.');}else{started[step!]=event.occurredAt;}
   case BakeEventType.stepCompleted:
    requireState({BakeState.active,BakeState.cooling});requireStep();
    if(skipped.contains(step))throw const DomainException('STEP_ALREADY_SKIPPED','Resolve the earlier skip before recording completion.');
    if(done.containsKey(step)){warnings.add('DUPLICATE_PHYSICAL_ACTION_REVIEW:$step');}else{
     if(started[step]!=null&&event.occurredAt.isBefore(started[step]!))throw const DomainException('EVENT_INVALID_TIME','Completion cannot precede its start.');
     done[step!]=event.occurredAt;
    }
   case BakeEventType.stepSkipped:
    requireState({BakeState.active});requireStep();
    if(event.payload['recipeAllowsSkip']!=true||event.payload['reason'] is! String||(event.payload['reason'] as String).trim().isEmpty)throw const DomainException('METHOD_UNSUPPORTED','Skipping needs recipe permission and a reason.');
    if(done.containsKey(step))throw const DomainException('STEP_ALREADY_FINISHED','A completed action cannot be skipped retroactively.');
    skipped.add(step!);
   case BakeEventType.observationRecorded:
    requireState({BakeState.active,BakeState.cooling,BakeState.complete});
    if(event.payload.isEmpty)throw const DomainException('OBSERVATION_EMPTY','Record at least one actual observation.');
   case BakeEventType.coolingStarted:
    requireState({BakeState.active});state=BakeState.cooling;
   case BakeEventType.bakeCompleted:
    requireState({BakeState.cooling});state=BakeState.complete;
   case BakeEventType.bakeAbandoned:
    requireState({BakeState.planned,BakeState.active,BakeState.cooling});state=BakeState.abandoned;
   case BakeEventType.bakeArchived:
    requireState({BakeState.complete,BakeState.abandoned});state=BakeState.archived;
   case BakeEventType.recordCorrected:
    final corrected=event.payload['correctsEventId'];
    final originals=previous.events.where((e)=>e.id==corrected);
    if(originals.isEmpty)throw const DomainException('CORRECTION_TARGET_MISSING','Original event is absent.');
    final original=originals.first;
    if(original.type!=BakeEventType.stepCompleted||event.payload['occurredAt'] is! String)throw const DomainException('CORRECTION_UNSUPPORTED','Only explicit completion timestamp corrections are supported by this reducer.');
    final at=DateTime.parse(event.payload['occurredAt']).toUtc();
    final target=original.payload['stepId'] as String;
    if(started[target]!=null&&at.isBefore(started[target]!))throw const DomainException('EVENT_INVALID_TIME','Corrected completion precedes stage start.');
    done[target]=at;warnings.add('Completion corrected for $target; dependent plans need review.');
  }
  return BakeSnapshot(id:previous.id,recipeVersion:previous.recipeVersion,state:state,revision:event.sequence,events:[...previous.events,event],completedSteps:done,startedSteps:started,skippedSteps:skipped,reconciliationWarnings:warnings,scheduleId:schedule);
 }
 BakeSnapshot replay({required String bakeId,required String recipeVersion,required Iterable<BakeEvent> events}) {
  final ordered=events.toList()..sort((a,b)=>a.sequence.compareTo(b.sequence));
  var snapshot=BakeSnapshot(id:bakeId,recipeVersion:recipeVersion);
  for(final e in ordered)snapshot=apply(snapshot,e);
  return snapshot;
 }
}
