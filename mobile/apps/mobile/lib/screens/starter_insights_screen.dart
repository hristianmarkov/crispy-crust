import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:baking_domain/baking_domain.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../data/app_store.dart';
import '../platform/export_share.dart';
import '../platform/local_media.dart';

num? _number(Object? value) {
  final n=value is num?value:num.tryParse(value?.toString()??'');
  return n!=null&&n.isFinite?n:null;
}
DateTime? _time(Object? value)=>DateTime.tryParse(value?.toString()??'')?.toUtc();
String _stamp(DateTime? value)=>value==null?'Not recorded':value.toLocal().toString().split('.').first;
FeedContext? _feedContext(AppRecord feed,Map context) {
  final seed=_number(feed.fields['seed']),flour=_number(feed.fields['flour']),water=_number(feed.fields['water']);
  final hydration=_number(context['hydrationPercent']),temperature=_number(context['temperatureC']);
  final mix=context['flourMixKey']?.toString().trim().toLowerCase().replaceAll(RegExp(r'\s+'),' ');
  final mode=context['storageMode']?.toString();
  if(seed==null||seed<=0||flour==null||flour<=0||water==null||water<0||hydration==null||hydration<=0||hydration>1000||temperature==null||temperature< -10||temperature>60||mix==null||mix.isEmpty||!{'counter','fridge','revival'}.contains(mode))return null;
  return FeedContext(starterId:feed.text('starterId'),flourMixKey:mix,hydration:Rational.fromNum(hydration)/Rational.fromNum(100),flourParts:Rational.fromNum(flour)/Rational.fromNum(seed),waterParts:Rational.fromNum(water)/Rational.fromNum(seed),storageMode:mode!,temperatureC:temperature.toDouble());
}
class StarterEvidence {
  const StarterEvidence({required this.currentFeed,required this.estimate,
    required this.comparableCount,required this.history,required this.excludedCount,
    required this.explanation,required this.lastObservationAt});
  final AppRecord? currentFeed;
  final PeakEstimate? estimate;
  final int comparableCount,excludedCount;
  final List<PeakRecord> history;
  final String explanation;
  final DateTime? lastObservationAt;
}

/// Only explicit feed links, confirmed peaks and user-confirmed condition
/// snapshots count. Current jar settings never rewrite historical feed context.
StarterEvidence analyseStarterEvidence(AppStore store,String starterId,{DateTime? now}) {
  final at=(now??DateTime.now()).toUtc();
  final feeds=store.records('feed').where((f)=>f.text('starterId')==starterId&&_time(f.fields['occurredAt'])!=null).toList()..sort((a,b)=>_time(b.fields['occurredAt'])!.compareTo(_time(a.fields['occurredAt'])!));
  final observations=store.records('observation').where((o)=>o.text('objectId')==starterId).toList()..sort((a,b)=>(_time(b.fields['occurredAt'])??b.updatedAt).compareTo(_time(a.fields['occurredAt'])??a.updatedAt));
  final current=feeds.isEmpty?null:feeds.first;
  final byFeed={for(final f in feeds)f.id:f};
  final confirmed=<String,List<AppRecord>>{};
  var excluded=0;
  for(final row in observations) {
    final feedId=row.text('feedId');
    if(row.text('peak')!='observed'||!row.flag('peakConfirmed'))continue;
    if(!byFeed.containsKey(feedId)||!row.flag('contextConfirmed')||row.fields['feedContext'] is! Map) {excluded++;continue;}
    confirmed.putIfAbsent(feedId,()=>[]).add(row);
  }
  final history=<PeakRecord>[];
  for(final group in confirmed.entries) {
    final feed=byFeed[group.key]!;
    final stamps=group.value.map((o)=>_time(o.fields['peakAt'])).toSet();
    // Competing physical-peak claims are not silently averaged or chosen.
    if(stamps.length!=1||stamps.single==null||group.value.map((o)=>canonicalJson(o.fields['feedContext'])).toSet().length!=1) {excluded+=group.value.length;continue;}
    final peak=stamps.single!,fed=_time(feed.fields['occurredAt'])!;
    final first=group.value.first;
    final context=_feedContext(feed,first.fields['feedContext'] as Map);
    if(context==null||peak.isBefore(fed)||peak.isAfter(at)) {excluded++;continue;}
    history.add(PeakRecord(id:feed.id,context:context,fedAt:fed,peakAt:peak,status:PeakStatus.observed));
  }
  final last=observations.isEmpty?null:(_time(observations.first.fields['occurredAt'])??observations.first.updatedAt);
  if(current==null)return StarterEvidence(currentFeed:null,estimate:null,comparableCount:0,history:List.unmodifiable(history),excludedCount:excluded,explanation:'Log an actual weighed feed first. No peak window can be inferred from the age of a culture.',lastObservationAt:last);
  final linked=observations.where((o)=>o.text('feedId')==current.id&&o.flag('contextConfirmed')&&o.fields['feedContext'] is Map).toList();
  final context=linked.isEmpty?null:_feedContext(current,linked.first.fields['feedContext'] as Map);
  if(context==null)return StarterEvidence(currentFeed:current,estimate:null,comparableCount:0,history:List.unmodifiable(history),excludedCount:excluded,explanation:'Confirm the actual conditions of this feed, including temperature, before comparing it. Existing jar settings are not historical measurements.',lastObservationAt:last);
  final fedAt=_time(current.fields['occurredAt'])!;
  final eligible=history.where((r)=>r.fedAt.isBefore(fedAt)&&!r.peakAt!.isAfter(at)&&at.difference(r.fedAt)<=const Duration(days:180)&&context.comparableTo(r.context,temperatureToleranceC:2)).toList();
  final estimate=const StarterEstimator().estimatePersonalized(context:context,fedAt:fedAt,now:at,history:history);
  return StarterEvidence(currentFeed:current,estimate:estimate,comparableCount:eligible.length,history:List.unmodifiable(history),excludedCount:excluded,explanation:estimate?.explanation??'${eligible.length} comparable confirmed prior feeds. At least five are needed. No reviewed broad timing profile is available, so no time window is invented.',lastObservationAt:last);
}

/// Pausing one jar cannot cancel a bake or a different starter's reminders.
Future<void> setStarterCareMode(AppStore store,String starterId,String mode) async {
  if(!{'counter','fridge','travel','paused','revival'}.contains(mode))throw ArgumentError('Unknown care mode');
  final starter=store.find(starterId);if(starter==null||starter.kind!='starter')throw StateError('Starter not found');
  await store.save('starter',{...starter.fields,'storage':mode},id:starterId);
  if(mode=='paused'||mode=='travel') {
    for(final timer in store.records('timer').where((t)=>t.text('starterId')==starterId&&t.text('state')=='running').toList()) {
      await store.save('timer',{...timer.fields,'state':'canceled','canceledReason':'Jar care $mode','canceledAt':DateTime.now().toUtc().toIso8601String()},id:timer.id);
    }
  }
}

class StarterInsightsScreen extends StatefulWidget {
  const StarterInsightsScreen({super.key,required this.store,required this.starterId});
  final AppStore store;
  final String starterId;
  @override State<StarterInsightsScreen> createState()=>_StarterInsightsScreenState();
}
class _StarterInsightsScreenState extends State<StarterInsightsScreen> {
  bool busy=false;String message='';
  Future<void> run(Future<void> Function() action) async {
    if(busy)return;setState((){busy=true;message='';});
    try{await action();}catch(e){if(mounted)setState(()=>message=e.toString());}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> remind(AppRecord starter) async {
    final today=DateTime.now();
    final date=await showDatePicker(context:context,initialDate:today,firstDate:DateTime(today.year,today.month,today.day),lastDate:today.add(const Duration(days:365)));
    if(date==null||!mounted)return;
    final time=await showTimePicker(context:context,initialTime:TimeOfDay.now());
    if(time==null||!mounted)return;
    final due=DateTime(date.year,date.month,date.day,time.hour,time.minute);
    if(!due.isAfter(DateTime.now())){setState(()=>message='Choose a future manual check time.');return;}
    await run(()async {
      await widget.store.save('timer',{'name':'Check ${starter.text('name')}','starterId':starter.id,'bakeId':starter.id,'bakeName':starter.text('name'),'dueAt':due.toUtc().toIso8601String(),'state':'running','isCheck':true,'source':'user_selected_jar_check'});
      if(mounted)setState(()=>message='Manual check saved for ${_stamp(due)}. Notification delivery still depends on device permissions.');
    });
  }
  Future<void> mode(AppRecord starter) async {
    final selected=await showModalBottomSheet<String>(context:context,showDragHandle:true,builder:(c)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[for(final value in ['counter','fridge','travel','paused','revival'])ListTile(title:Text(value),subtitle:Text(value=='travel'||value=='paused'?'Cancels only this jar’s running care reminders':'Does not log a feed or reactivate old reminders'),onTap:()=>Navigator.pop(c,value))])));
    if(selected!=null)await run(()=>setStarterCareMode(widget.store,starter.id,selected));
  }
  Future<void> careCard(AppRecord starter,List<AppRecord> feeds) async {
    final last=feeds.isEmpty?null:feeds.first;
    final data={'format':'crispy-crust-starter-care','version':1,'exportedAt':DateTime.now().toUtc().toIso8601String(),'starter':{'name':starter.fields['name'],'flour':starter.fields['flour'],'hydrationPercent':starter.fields['hydration'],'storage':starter.fields['storage'],'recordedJarMassGrams':starter.fields['mass'],'lastActualFeed':last==null?null:{'sourceFeedId':last.id,'occurredAt':last.fields['occurredAt'],'seedGrams':last.fields['seed'],'flourAddedGrams':last.fields['flour'],'waterAddedGrams':last.fields['water'],'recordedBuildGrams':last.fields['total']}},'retentionNote':'Recorded jar amount is not a live stock guarantee. Confirm the physical amount and retain a mother portion before sharing. No mass is deducted by this export.','privacy':'No photos, private notes, calendar blocks or account details included.','guidanceReviewStatus':'Source-linked editorial guidance pending independent review'};
    final text=const JsonEncoder.withIndent('  ').convert(data);
    await showDialog<void>(context:context,builder:(c)=>AlertDialog(title:const Text('Preview starter care card'),content:SizedBox(width:540,child:SingleChildScrollView(child:SelectableText(text))),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Keep private')),FilledButton(onPressed:()async {Navigator.pop(c);await run(()async {final result=await ExportShareService().shareTextFile(fileName:'crispy-crust-starter-care.json',content:text,mimeType:'application/json');if(mounted)setState(()=>message=result.message);});},child:const Text('Save or share this card'))]));
  }
  Widget card(List<Widget> children)=>Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:children)));
  @override Widget build(BuildContext context)=>AnimatedBuilder(animation:widget.store,builder:(context,_) {
    final starter=widget.store.find(widget.starterId);
    if(starter==null)return Scaffold(appBar:AppBar(title:const Text('Starter insights')),body:const Center(child:Text('This jar is no longer available.')));
    final evidence=analyseStarterEvidence(widget.store,starter.id);
    final feeds=widget.store.records('feed').where((f)=>f.text('starterId')==starter.id).toList()..sort((a,b)=>(_time(b.fields['occurredAt'])??b.updatedAt).compareTo(_time(a.fields['occurredAt'])??a.updatedAt));
    final observations=widget.store.records('observation').where((o)=>o.text('objectId')==starter.id).toList()..sort((a,b)=>(_time(a.fields['occurredAt'])??a.updatedAt).compareTo(_time(b.fields['occurredAt'])??b.updatedAt));
    final current=observations.where((o)=>o.text('feedId')==evidence.currentFeed?.id&&_number(o.fields['height'])!=null).toList();
    final window=evidence.estimate?.checkWindow;
    final latest=evidence.lastObservationAt;
    return Scaffold(appBar:AppBar(title:Text('${starter.text('name')} · insights')),body:ListView(padding:const EdgeInsets.all(20),children:[
      Text('Recorded evidence, not a health score',style:Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height:12),const Text('A time estimate does not establish readiness or food safety. Unknown peaks stay unknown. No cloud analysis is used here.'),
      if(busy)const LinearProgressIndicator(),if(message.isNotEmpty)Semantics(liveRegion:true,child:card([Text(message)])),
      card([Text('Next check',style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:8),
        if(window!=null)...[Text('${_stamp(window.start)} – ${_stamp(window.end)}',style:Theme.of(context).textTheme.titleMedium),if(window.end.isBefore(DateTime.now().toUtc()))const Text('This empirical window has passed. It is not a live measurement; check the jar and record what you find.')],
        Text(evidence.explanation),Text('${evidence.excludedCount} conflicting, incomplete or unsupported peak records excluded.'),
        Text('Last actual observation: ${_stamp(latest)}${latest!=null?' · ${DateTime.now().toUtc().difference(latest).inMinutes} minutes old':''}'),
        if(evidence.estimate!=null)...[Text('Model: ${evidence.estimate!.modelVersion} · empirical, not statistically calibrated'),ExpansionTile(title:const Text('Which actual feeds were compared?'),children:[for(final id in evidence.estimate!.sourceRecordIds)ListTile(title:Text('Feed $id'))])],
        const SizedBox(height:12),FilledButton(onPressed:busy?null:()=>Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>_StarterObservationForm(store:widget.store,starterId:starter.id))),child:const Text('Record a linked observation')),
        OutlinedButton(onPressed:busy?null:()=>remind(starter),child:const Text('Choose a manual check reminder')),
        TextButton(onPressed:busy?null:()=>mode(starter),child:Text('Storage, pause or travel · ${starter.text('storage','counter')}')),
      ]),
      card([Text('Measured height in the current feed',style:Theme.of(context).textTheme.titleLarge),
        const Text('Height is not volume unless the container is straight-sided or calibrated. Lines join recorded readings; there is no predicted rise curve.'),
        if(current.isEmpty)const Text('No feed-linked height readings. Older unlinked observations remain below; they are not assigned to a feed automatically.')
        else...[
          Semantics(label:'Height chart, ${current.length} actual readings. The timestamped readings are listed below.',child:ExcludeSemantics(child:SizedBox(height:180,width:double.infinity,child:CustomPaint(painter:_HeightChart(current.map((o)=>(at:_time(o.fields['occurredAt'])??o.updatedAt,height:_number(o.fields['height'])!.toDouble())).toList(),Theme.of(context).colorScheme.primary))))),
          for(final row in current)Text('${_stamp(_time(row.fields['occurredAt']))}: ${row.text('height')} mm')
        ],
      ]),
      card([Text('Guided private photo sequence',style:Theme.of(context).textTheme.titleLarge),const Text('Use the same marked container, angle and visible scale. Every frame is an explicit capture. The app does not infer height, peak or safety from these images and does not monitor a suspended phone.'),
        OutlinedButton(onPressed:busy||feeds.isEmpty?null:()=>Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>_PhotoSequenceScreen(store:widget.store,starterId:starter.id,feedId:feeds.first.id))),child:const Text('Capture or replay current-feed sequence'))]),
      card([Text('New culture practice',style:Theme.of(context).textTheme.titleLarge),
        Text(feeds.isEmpty?'Begin by recording your actual weighed mix. A suggested feed is never logged for you.':observations.isEmpty?'Next: record what you can observe, including unknown peak.':evidence.history.isEmpty?'Next: watch the response across actual feeds. A calendar day does not certify maturity.':'Next: compare repeated behaviour and consult the source guide before choosing a first bake. No automatic “ready” state is awarded.'),
        const Text('Clean equipment and reviewed safety guidance matter. Source-linked starter guidance in this build still awaits independent editorial review.'),
        TextButton(onPressed:()=>showDialog<void>(context:context,builder:(c)=>AlertDialog(title:const Text('Source-linked help · review pending'),content:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[for(final guide in widget.store.guidance)...[Text(guide['title']?.toString()??'Guidance'),for(final paragraph in guide['body'] as List? ?? [])Text(paragraph.toString()),for(final source in guide['sources'] as List? ?? [])SelectableText((source as Map)['url'].toString()),const SizedBox(height:12)]])),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Return to jar'))])),child:const Text('Open starter and spoilage guidance')),
      ]),
      card([Text('Keep uncertainty visible',style:Theme.of(context).textTheme.titleLarge),for(final row in observations.reversed.take(15))ListTile(contentPadding:EdgeInsets.zero,title:Text('${_stamp(_time(row.fields['occurredAt']))} · ${row.text('peak','unknown')}'),subtitle:Text('Feed link: ${row.text('feedId','not linked')}\n${row.text('note')}\nTemperature: ${row.text('temperature','unknown')} °C'))]),
      OutlinedButton(onPressed:busy?null:()=>careCard(starter,feeds),child:const Text('Preview starter care export')),
    ]));
  });
}

class _HeightChart extends CustomPainter {
  _HeightChart(this.points,this.color);
  final List<({DateTime at,double height})> points;
  final Color color;
  @override void paint(Canvas canvas,Size size) {
    if(points.isEmpty)return;
    final left=points.first.at.millisecondsSinceEpoch.toDouble(),right=points.last.at.millisecondsSinceEpoch.toDouble();
    final maxHeight=math.max(1.0,points.map((p)=>p.height).reduce(math.max));
    final path=Path();
    final paint=Paint()..color=color..style=PaintingStyle.stroke..strokeWidth=2;
    for(var i=0;i<points.length;i++) {
      final x=12+(size.width-24)*(right == left ? 0.5 : (points[i].at.millisecondsSinceEpoch-left)/(right-left));
      final y=size.height-12-(size.height-24)*points[i].height/maxHeight;
      if(i==0)path.moveTo(x,y);else path.lineTo(x,y);
      canvas.drawCircle(Offset(x,y),3,Paint()..color=color);
    }
    canvas.drawPath(path,paint);
  }
  @override bool shouldRepaint(covariant _HeightChart old)=>old.points!=points||old.color!=color;
}

class _StarterObservationForm extends StatefulWidget {
  const _StarterObservationForm({required this.store,required this.starterId});
  final AppStore store;final String starterId;
  @override State<_StarterObservationForm> createState()=>_StarterObservationFormState();
}
class _StarterObservationFormState extends State<_StarterObservationForm> {
  final form=GlobalKey<FormState>();
  final at=TextEditingController(text:DateTime.now().toLocal().toIso8601String());
  final temperature=TextEditingController(),height=TextEditingController(),baseline=TextEditingController(),note=TextEditingController();
  late final hydration=TextEditingController(text:widget.store.find(widget.starterId)?.text('hydration')??'');
  late final mix=TextEditingController(text:widget.store.find(widget.starterId)?.text('flour')??'');
  String? feedId;String peak='unknown',storage='counter',error='';
  bool contextConfirmed=false,peakConfirmed=false,calibrated=false,busy=false;
  @override void initState(){super.initState();final feeds=widget.store.records('feed').where((f)=>f.text('starterId')==widget.starterId).toList()..sort((a,b)=>(_time(b.fields['occurredAt'])??b.updatedAt).compareTo(_time(a.fields['occurredAt'])??a.updatedAt));feedId=feeds.firstOrNull?.id;}
  @override void dispose(){for(final controller in [at,temperature,height,baseline,note,hydration,mix])controller.dispose();super.dispose();}
  Widget field(TextEditingController controller,String label,{bool numeric=false})=>Padding(padding:const EdgeInsets.only(bottom:16),child:TextFormField(controller:controller,decoration:InputDecoration(labelText:label),keyboardType:numeric?const TextInputType.numberWithOptions(decimal:true,signed:true):TextInputType.text,validator:(v){if(numeric&&v!=null&&v.isNotEmpty&&_number(v)==null)return 'Enter a finite number or leave unknown.';return null;}));
  Future<void> save() async {
    if(busy||!form.currentState!.validate())return;
    final observedAt=_time(at.text),feed=feedId==null?null:widget.store.find(feedId!);
    if(observedAt==null||observedAt.isAfter(DateTime.now().toUtc())||(feed!=null&&observedAt.isBefore(_time(feed.fields['occurredAt'])??observedAt))) {setState(()=>error='Use an actual observation time after this feed and no later than now.');return;}
    if(peak=='observed'&&(!peakConfirmed||feed==null)){setState(()=>error='A confirmed peak needs a linked actual feed and your confirmation of its observed time.');return;}
    final conditions={'flourMixKey':mix.text,'hydrationPercent':_number(hydration.text),'temperatureC':_number(temperature.text),'storageMode':storage};
    if(contextConfirmed&&(feed==null||_feedContext(feed,conditions)==null)){setState(()=>error='Comparable context needs the actual feed weights, flour, hydration, storage mode and representative temperature. Leave confirmation off when these are unknown.');return;}
    final measured=_number(height.text),start=_number(baseline.text);
    if((measured!=null&&measured<=0)||(start!=null&&start<=0)){setState(()=>error='Measured heights must be positive; unknown can stay empty.');return;}
    if(height.text.isEmpty&&temperature.text.isEmpty&&note.text.isEmpty&&peak=='unknown'&&feed==null){setState(()=>error='Record an observation or link a feed; unknown measurements can stay empty.');return;}
    setState((){busy=true;error='';});
    try {
      await widget.store.save('observation',{'objectId':widget.starterId,'feedId':feedId,'occurredAt':observedAt.toIso8601String(),'peak':peak,'peakConfirmed':peak=='observed'&&peakConfirmed,if(peak=='observed')'peakAt':observedAt.toIso8601String(),'contextConfirmed':contextConfirmed,'feedContext':conditions,'temperature':temperature.text,'height':height.text,'baseline':baseline.text,'straightSidedOrCalibrated':calibrated,if(calibrated&&measured!=null&&start!=null)'rise':risePercentage(baselineHeight:Rational.fromNum(start),currentHeight:Rational.fromNum(measured),straightSidedOrCalibrated:true).toDouble(),'note':note.text,'source':'manual_confirmed'});
      if(mounted)Navigator.pop(context);
    }catch(e){if(mounted)setState(()=>error=e.toString());}finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context) {
    final feeds=widget.store.records('feed').where((f)=>f.text('starterId')==widget.starterId).toList();
    return Scaffold(appBar:AppBar(title:const Text('Link an actual starter observation')),body:Form(key:form,child:ListView(padding:const EdgeInsets.all(20),children:[
      const Text('Link a measured feed explicitly. Current jar defaults below are suggestions to verify, not historical facts.'),const SizedBox(height:16),
      DropdownButtonFormField<String>(initialValue:feedId,isExpanded:true,itemHeight:null,decoration:const InputDecoration(labelText:'Actual feed'),items:[const DropdownMenuItem(value:null,child:Text('No feed link / unknown')),for(final f in feeds)DropdownMenuItem(value:f.id,child:Text('${_stamp(_time(f.fields['occurredAt']))} · ${f.text('seed')}:${f.text('flour')}:${f.text('water')} g'))],onChanged:busy?null:(value)=>setState((){feedId=value;contextConfirmed=false;peakConfirmed=false;})),
      const SizedBox(height:16),field(at,'Actual observation date/time (ISO, local offset accepted)'),
      DropdownButtonFormField<String>(initialValue:peak,isExpanded:true,itemHeight:null,decoration:const InputDecoration(labelText:'What happened to the peak?'),items:const [DropdownMenuItem(value:'unknown',child:Text('Peak not observed / missed / unknown')),DropdownMenuItem(value:'not_yet',child:Text('Not yet peaked')),DropdownMenuItem(value:'observed',child:Text('I observed the peak')),DropdownMenuItem(value:'falling',child:Text('Falling; peak time unknown unless logged'))],onChanged:busy?null:(v)=>setState(()=>peak=v??'unknown')),
      if(peak=='observed')CheckboxListTile(contentPadding:EdgeInsets.zero,value:peakConfirmed,onChanged:busy?null:(v)=>setState(()=>peakConfirmed=v??false),title:const Text('I saw this jar peak at the actual time above'),subtitle:const Text('Do not tick this if you returned after the peak or inferred it from a photo.')),
      const SizedBox(height:16),field(temperature,'Representative temperature for this feed (°C, optional)',numeric:true),field(height,'Measured height now (mm, optional)',numeric:true),field(baseline,'Starting height for this feed (mm, optional)',numeric:true),
      CheckboxListTile(contentPadding:EdgeInsets.zero,value:calibrated,onChanged:busy?null:(v)=>setState(()=>calibrated=v??false),title:const Text('The container is straight-sided or calibrated'),subtitle:const Text('Only then can these heights support a rise percentage.')),
      field(mix,'Actual flour mix for this feed'),field(hydration,'Actual starter hydration for this feed (%)',numeric:true),
      DropdownButtonFormField<String>(initialValue:storage,isExpanded:true,decoration:const InputDecoration(labelText:'Actual feed storage conditions'),items:const [DropdownMenuItem(value:'counter',child:Text('Counter')),DropdownMenuItem(value:'fridge',child:Text('Fridge')),DropdownMenuItem(value:'revival',child:Text('Revival'))],onChanged:busy?null:(v)=>setState(()=>storage=v??'counter')),
      CheckboxListTile(contentPadding:EdgeInsets.zero,value:contextConfirmed,onChanged:busy?null:(v)=>setState(()=>contextConfirmed=v??false),title:const Text('I confirm these actual feed conditions'),subtitle:const Text('Leave off when any conditions are unknown. The observation still saves; it is excluded from personal timing.')),
      field(note,'Notes (optional)'),if(error.isNotEmpty)Semantics(liveRegion:true,child:Text(error)),if(busy)const LinearProgressIndicator(),FilledButton(onPressed:busy?null:save,child:const Text('Save actual observation')),
    ])));
  }
}

class _PhotoSequenceScreen extends StatefulWidget {
  const _PhotoSequenceScreen({required this.store,required this.starterId,required this.feedId});
  final AppStore store;final String starterId,feedId;
  @override State<_PhotoSequenceScreen> createState()=>_PhotoSequenceScreenState();
}
class _PhotoSequenceScreenState extends State<_PhotoSequenceScreen> {
  final media=LocalMediaService();final sessionId=const Uuid().v4();
  bool aligned=false,busy=false,playing=false;int frame=0;String error='';Timer? playback;
  List<AppRecord> get frames=>widget.store.records('observation').where((o)=>o.text('objectId')==widget.starterId&&o.text('feedId')==widget.feedId&&o.fields['photo'] is Map).toList()..sort((a,b)=>(_time(a.fields['occurredAt'])??a.updatedAt).compareTo(_time(b.fields['occurredAt'])??b.updatedAt));
  Future<void> capture(bool camera) async {
    if(busy||!aligned)return;setState((){busy=true;error='';});LocalPhoto? selected;var persisted=false;
    try {
      selected=await media.pickPhoto(camera:camera);if(selected==null)return;
      await widget.store.save('observation',{'objectId':widget.starterId,'feedId':widget.feedId,'captureSessionId':sessionId,'alignmentConfirmed':true,'occurredAt':DateTime.now().toUtc().toIso8601String(),'peak':'unknown','source':'manual_photo_sequence','photoTimeBasis':'app_recorded_at_not_exif','captureMethod':camera?'camera':'gallery_import','photoId':selected.id,'photo':selected.toJson(),'note':'Aligned frame; no automatic rise measurement.'});persisted=true;if(mounted)setState(()=>aligned=false);
    }catch(e){if(mounted)setState(()=>error='Frame not saved: $e. Existing observations remain.');}
    finally{if(selected!=null&&!persisted){try{await media.delete(selected);}catch(_){if(mounted)setState(()=>error='Frame not saved; an unlinked private photo also needs cleanup.');}}if(mounted)setState(()=>busy=false);}
  }
  void play() {
    playback?.cancel();if(playing){setState(()=>playing=false);return;}
    if(frames.isEmpty)return;setState(()=>playing=true);
    playback=Timer.periodic(const Duration(seconds:1),(_){if(!mounted)return;final count=frames.length;if(count==0){playback?.cancel();setState(()=>playing=false);return;}setState(()=>frame=(frame+1)%count);});
  }
  @override void dispose(){playback?.cancel();super.dispose();}
  @override Widget build(BuildContext context)=>AnimatedBuilder(animation:widget.store,builder:(context,_) {
    final entries=frames;final current=entries.isEmpty?null:entries[frame%entries.length];
    return Scaffold(appBar:AppBar(title:const Text('Private starter photo sequence')),body:ListView(padding:const EdgeInsets.all(20),children:[
      const Text('Use the same marked, straight-sided container, camera distance, angle and visible scale. Keep the phone away from heat and water. This is explicit capture and replay, not unattended monitoring or image measurement.'),
      CheckboxListTile(contentPadding:EdgeInsets.zero,value:aligned,onChanged:busy?null:(v)=>setState(()=>aligned=v??false),title:const Text('I have checked alignment and the visible reference mark')),
      Wrap(spacing:8,runSpacing:8,children:[OutlinedButton(onPressed:busy||!aligned?null:()=>capture(true),child:const Text('Capture one aligned frame')),OutlinedButton(onPressed:busy||!aligned?null:()=>capture(false),child:const Text('Select one recorded frame'))]),
      if(busy)const LinearProgressIndicator(),if(error.isNotEmpty)Semantics(liveRegion:true,child:Text(error)),
      Text('${entries.length} recorded frames for this feed; gaps are not filled in. Times below are app recording times, not inferred image capture times.'),
      if(current!=null)...[Text('Frame ${frame%entries.length+1} · ${_stamp(_time(current.fields['occurredAt']))}'),FutureBuilder<File>(key:ValueKey(current.id),future:media.resolve(LocalPhoto.fromJson(Map<String,dynamic>.from(current.fields['photo'] as Map))),builder:(context,snapshot)=>snapshot.hasData?Image.file(snapshot.data!,semanticLabel:'Recorded starter frame, added in app ${_stamp(_time(current.fields['occurredAt']))}'):Text(snapshot.hasError?'This local frame is unavailable. Its observation is retained.':'Opening local frame…')),OutlinedButton(onPressed:play,child:Text(playing?'Pause local replay':'Replay recorded frames'))],
      for(final entry in entries)ListTile(title:Text(_stamp(_time(entry.fields['occurredAt']))),subtitle:Text(entry.text('note'))),
    ]));
  });
}
