import 'dart:isolate';
import 'package:baking_domain/baking_domain.dart';
import 'package:flutter/material.dart';
import '../data/app_store.dart';
import '../data/planning_adapter.dart';
import '../platform/export_share.dart';

class ProductionSolveInput {
  const ProductionSolveInput(this.blueprint,this.horizon,this.capacities,this.unavailable,this.reservations);
  final ProductionBlueprint blueprint;
  final TimeWindow horizon;
  final Map<String,int> capacities;
  final List<TimeWindow> unavailable;
  final List<ResourceReservation> reservations;
}
ProductionPlanResult solveProduction(ProductionSolveInput input)=>const ProductionPlanner().solve(blueprint:input.blueprint,horizon:input.horizon,resourceCapacities:input.capacities,unavailable:input.unavailable,reservations:input.reservations,kitchenTimeZone:'UTC',maxSearchNodes:5000);
Future<ProductionPlanResult> _workerSolve(ProductionSolveInput input)=>Isolate.run(()=>solveProduction(input));

class ProductionScreen extends StatefulWidget {
  ProductionScreen({super.key,required this.store,ExportShareService? exporter,DateTime Function()? clock,Future<ProductionPlanResult> Function(ProductionSolveInput)? solver})
    :exporter=exporter??ExportShareService(),clock=clock??DateTime.now,solver=solver??_workerSolve;
  final AppStore store;
  final ExportShareService exporter;
  final DateTime Function() clock;
  final Future<ProductionPlanResult> Function(ProductionSolveInput) solver;
  @override State<ProductionScreen> createState()=>_ProductionScreenState();
}
class _ProductionLine {
  final String id;
  final Map<String,dynamic> recipe;
  final int pieces,perLoad;
  final DateTime pickupStart,pickupEnd;
  final Rational ovenC;
  const _ProductionLine(this.id,this.recipe,this.pieces,this.perLoad,this.pickupStart,this.pickupEnd,this.ovenC);
}
class _ProductionScreenState extends State<ProductionScreen> {
  final name=TextEditingController(),count=TextEditingController(text:'1'),perLoad=TextEditingController(text:'1'),temperature=TextEditingController(text:'230'),pickupStart=TextEditingController(),pickupEnd=TextEditingController(),reload=TextEditingController(text:'10'),warmChange=TextEditingController(text:'20'),coolChange=TextEditingController(text:'30'),notes=TextEditingController();
  final capacities=<String,TextEditingController>{},prices=<String,TextEditingController>{};
  final perPieceResources=<String>{'vessel','tin','tray','coolingRack','fridgeSlot','bakingSurface'};
  final lines=<_ProductionLine>[];
  String? selectedRecipe;
  String status='No production plan accepted. Home bakes and production records stay separate.';
  bool experimentalAccepted=false,busy=false;
  ProductionPlanResult? result;
  Map<String,dynamic>? savedRun;
  BatchCost? costPreview;
  @override void initState(){super.initState();selectedRecipe=widget.store.recipes.firstOrNull?['id']?.toString();final t=widget.clock().toLocal().add(const Duration(days:2));pickupStart.text=_localInput(DateTime(t.year,t.month,t.day,18));pickupEnd.text=_localInput(DateTime(t.year,t.month,t.day,19));}
  @override void dispose(){for(final c in [name,count,perLoad,temperature,pickupStart,pickupEnd,reload,warmChange,coolChange,notes,...capacities.values,...prices.values])c.dispose();super.dispose();}
  static String _localInput(DateTime d)=>'${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')} ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
  static DateTime _parseLocal(String input){
    if(!RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$').hasMatch(input.trim()))throw const FormatException('Use local date and time as YYYY-MM-DD HH:mm.');
    final parsed=DateTime.parse(input.trim().replaceFirst(' ','T'));
    if(_localInput(parsed)!=input.trim())throw const FormatException('Enter a valid calendar date and time.');
    return parsed;
  }
  int _integer(TextEditingController c,String label,{int minimum=1,int maximum=500}){final n=int.tryParse(c.text.trim());if(n==null||n<minimum||n>maximum)throw FormatException('$label must be a whole number from $minimum to $maximum.');return n;}
  Rational _number(String text,String label,{bool positive=false}){final n=num.tryParse(text.trim());if(n==null||!n.isFinite||n<0||(positive&&n==0))throw FormatException('$label must be ${positive?'positive':'nonnegative'}.');return Rational.fromNum(n);}
  void _invalidate(){result=null;savedRun=null;costPreview=null;}
  Future<void> _run(Future<void> Function() action) async {
    if(busy)return;setState(()=>busy=true);
    try{await action();}catch(e){if(mounted)setState(()=>status='Not completed: $e');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Widget _heading(String text)=>Padding(padding:const EdgeInsets.only(top:24,bottom:12),child:Text(text,style:Theme.of(context).textTheme.titleLarge));
  Widget _field(String label,TextEditingController controller,{bool numeric=false,String? key,bool affectsPlan=true})=>Padding(padding:const EdgeInsets.only(bottom:14),child:TextField(key:key==null?null:ValueKey(key),controller:controller,enabled:!busy&&savedRun==null,keyboardType:numeric?const TextInputType.numberWithOptions(decimal:true):null,decoration:InputDecoration(labelText:label),onChanged:(_){if(affectsPlan&&result!=null){setState(_invalidate);}else if(costPreview!=null){setState(()=>costPreview=null);}}));
  Widget _panel(List<Widget> children)=>Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:children)));
  List<Map<String,dynamic>> _maps(dynamic value)=>(value is List?value:const []).whereType<Map>().map((m)=>Map<String,dynamic>.from(m)).toList();
  Map<String,dynamic> _recipe()=>widget.store.recipes.firstWhere((r)=>'${r['id']}'==selectedRecipe);
  Future<void> _addLine() async {
    if(!experimentalAccepted)throw StateError('Acknowledge experimental assumptions before adding quantities.');
    final recipe=_recipe();final pieces=_integer(count,'Pieces'),load=_integer(perLoad,'Pieces per load',maximum:100);
    final start=_parseLocal(pickupStart.text),end=_parseLocal(pickupEnd.text);
    if(!end.isAfter(start)||!start.isAfter(widget.clock()))throw const FormatException('Choose a future pickup window with end after start.');
    final temp=_number(temperature.text,'Oven set point',positive:true);if(temp>Rational.fromNum(350))throw const FormatException('Oven set point must be 350°C or lower.');
    for(final s in graphForRecipe(recipe).steps){for(final resource in s.resources.keys)capacities.putIfAbsent(resource,()=>TextEditingController(text:'1'));}
    for(final ingredient in _maps(recipe['ingredients']))prices.putIfAbsent('${ingredient['id']}',()=>TextEditingController());
    setState((){lines.add(_ProductionLine('item_${lines.length+1}_${widget.clock().microsecondsSinceEpoch}',recipe,pieces,load,start,end,temp));_invalidate();status='Product added as experimental assumptions. No oven time is reserved until you review and accept a feasible plan.';});
  }
  ProductionMethod _method(_ProductionLine line){
    final graph=graphForRecipe(line.recipe);final yieldCount=(line.recipe['yieldCount'] as num? ?? 1);
    if(!yieldCount.isFinite||yieldCount<=0)throw const FormatException('Recipe yield is unknown; define a per-piece formula before production.');
    final physical=PhysicalFormula(_maps(line.recipe['ingredients']).map((i)=>PhysicalIngredient(id:'${i['id']}',grams:_number('${i['grams']}','Ingredient weight'),flourGrams:_number('${i['flourGrams']??0}','Ingredient flour'),waterGrams:_number('${i['waterGrams']??0}','Ingredient water'))).toList()).scale(Rational.one/Rational.fromNum(yieldCount));
    return ProductionMethod(recipeId:'${line.recipe['id']}',title:'${line.recipe['title']}',validationEvidenceId:'',experimental:true,readyStepId:graph.topologicalOrder().last.id,perPieceFormula:physical,graph:graph,maximumPiecesPerLoad:line.perLoad,perPieceResources:perPieceResources,ovenTemperatures:{for(final s in graph.steps)if(s.resources.containsKey('oven'))s.id:line.ovenC});
  }
  List<ResourceReservation> _existingReservations(){
    final reservations=<ResourceReservation>[];
    for(final record in widget.store.records('production')){
      if(['complete','packed','abandoned','archived'].contains(record.text('status',record.text('state'))))continue;
      for(final row in _maps(record.fields['reservations'])){
        reservations.add(ResourceReservation(resourceId:'${row['resourceId']}',owner:record.id,window:TimeWindow(DateTime.parse('${row['start']}').toUtc(),DateTime.parse('${row['end']}').toUtc()),units:(row['units'] as num).toInt()));
      }
    }
    for(final record in widget.store.records('bake')){
      if(['complete','abandoned','archived'].contains(record.text('status')))continue;
      final schedule=record.fields['schedule'],snapshot=record.fields['recipeSnapshot'];if(schedule is! Map||snapshot is! Map)continue;
      final graph=graphForRecipe(Map<String,dynamic>.from(snapshot));
      final candidate=ScheduleCandidate.fromJson(Map<String,dynamic>.from(schedule));
      for(final task in candidate.tasks){final step=graph.steps.where((s)=>s.id==task.stepId).firstOrNull;if(step==null)continue;for(final resource in step.resources.entries)reservations.add(ResourceReservation(resourceId:resource.key,owner:record.id,window:TimeWindow(task.start,task.end),units:resource.value));}
    }
    return reservations;
  }
  Future<void> _plan() async {
    if(name.text.trim().isEmpty||lines.isEmpty)throw const FormatException('Name the run and add at least one product.');
    if(!experimentalAccepted)throw StateError('Experimental assumptions must be acknowledged.');
    final now=widget.clock().toUtc();final horizon=TimeWindow(now,now.add(const Duration(days:14)));
    final reloadMinutes=_integer(reload,'Reload minutes',minimum:0,maximum:240),warmMinutes=_integer(warmChange,'Warm-up changeover',minimum:0,maximum:240),coolMinutes=_integer(coolChange,'Cool-down changeover',minimum:0,maximum:240);
    final temperatures=lines.map((l)=>l.ovenC).toSet();
    final blueprint=const ProductionPlanner().compose(items:lines.map((l)=>ProductionItem(id:l.id,method:_method(l),pieces:l.pieces,pickupWindow:TimeWindow(l.pickupStart.toUtc(),l.pickupEnd.toUtc()))).toList(),horizon:horizon,reloadDuration:Duration(minutes:reloadMinutes),reloadAttendedDuration:Duration(minutes:reloadMinutes),changeovers:[for(final a in temperatures)for(final b in temperatures)if(a!=b)OvenChangeover(fromC:a,toC:b,duration:Duration(minutes:b>a?warmMinutes:coolMinutes))]);
    final unavailable=<TimeWindow>[];
    for(final row in widget.store.records('availability')){final start=row.date('startAt'),end=row.date('endAt');if(start!=null&&end!=null&&end.isAfter(start))unavailable.add(TimeWindow(start.toUtc(),end.toUtc()));}
    final planned=await widget.solver(ProductionSolveInput(blueprint,horizon,{for(final e in capacities.entries)e.key:_integer(e.value,'${e.key} capacity',minimum:0,maximum:100)},unavailable,_existingReservations()));
    if(!mounted)return;
    setState((){result=planned;savedRun=null;status=planned.feasible?'Review the separate loads, cooling completion and assumptions below. Nothing is saved yet.':'No fit found for this experimental load order. Change counts, load size, equipment, availability or pickup time. No refrigeration or proof hold has been invented.';});
  }
  List<Map<String,dynamic>> _reservations(ProductionPlanResult plan){
    final schedule=plan.planning.candidates.first;
    return [for(final task in schedule.tasks)for(final entry in plan.blueprint.graph.steps.firstWhere((s)=>s.id==task.stepId).resources.entries){'resourceId':entry.key,'units':entry.value,'start':task.start.toIso8601String(),'end':task.end.toIso8601String(),'batchStepId':task.stepId}];
  }
  List<IngredientPrice> _priceRows(){
    final rows=<IngredientPrice>[];
    for(final p in prices.entries){if(p.value.text.trim().isEmpty)continue;final price=_number(p.value.text,'${p.key} price');final minor=price*Rational.fromNum(100);if(minor.denominator!=BigInt.one||price>Rational.fromNum(1000000))throw const FormatException('Enter GBP/kg prices with at most two decimal places, no more than 1,000,000. Prices are not silently rounded.');rows.add(IngredientPrice(ingredientId:p.key,currency:'GBP',packageGrams:Rational.fromNum(1000),packageCostMinorUnits:minor.numerator.toInt(),recordedAt:widget.clock().toUtc()));}
    return rows;
  }
  Future<void> _save() async {
    final plan=result;if(plan==null||!plan.feasible)throw StateError('Review a feasible plan first.');
    // Re-run against current local reservations immediately before persistence.
    // Shared-kitchen CAS is handled by cloud APIs; this is a local run only.
    final prior=plan.planning.candidates.first;
    final horizon=TimeWindow(widget.clock().toUtc(),widget.clock().toUtc().add(const Duration(days:14)));
    final validation=const PlanningEngine().validate(prior,PlanningRequest(graph:plan.blueprint.graph,anchor:plan.blueprint.readyBy,horizon:horizon,direction:PlanningDirection.backward,resourceCapacities:{for(final e in capacities.entries)e.key:_integer(e.value,'Capacity',minimum:0,maximum:100)},reservations:_existingReservations(),unavailable:[for(final row in widget.store.records('availability'))if(row.date('startAt')!=null&&row.date('endAt')!=null)TimeWindow(row.date('startAt')!.toUtc(),row.date('endAt')!.toUtc())]));
    if(!validation.isValid)throw StateError('Kitchen reservations changed. Generate and review the plan again.');
    final cost=plan.blueprint.cost(_priceRows(),currency:'GBP');
    final fields=<String,dynamic>{'name':name.text.trim(),'notes':notes.text.trim(),'status':'planned','state':'planned','experimental':true,'validationStatus':'experimental_user_assumptions','actualYield':null,'createdAt':widget.clock().toUtc().toIso8601String(),'timeDisplay':'Device local time at entry; absolute UTC schedule','deviceOffsetMinutes':widget.clock().timeZoneOffset.inMinutes,'graph':plan.blueprint.graph.toJson(),'schedule':prior.toJson(),'batches':plan.blueprint.packList,'reservations':_reservations(plan),'shopping':plan.blueprint.shoppingDemand.map((k,v)=>MapEntry(k,v.toJson())),'currency':'GBP','knownCostMinorUnits':cost.knownCostMinorUnits.toJson(),'totalCostMinorUnits':cost.totalCostMinorUnits?.toJson(),'missingPrices':cost.missingPrices};
    final record=await widget.store.save('production',fields);
    if(mounted)setState((){savedRun={...fields,'id':record.id};status='Saved locally as a separate production run with ${plan.blueprint.batches.length} named loads and resource reservations. Actual packed yield remains unknown.';});
  }
  Future<void> _recordYield(AppRecord run) async {
    final input=TextEditingController();
    final answer=await showDialog<String>(context:context,builder:(c)=>AlertDialog(title:const Text('Record actual packed quantity'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[const Text('Enter what was actually packed across this run. This releases future reservations and does not rewrite planned load quantities.'),TextField(controller:input,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Actual packed pieces'))])),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(c,input.text),child:const Text('Record actual yield'))]));
    await Future<void>.delayed(const Duration(milliseconds:250));input.dispose();
    if(answer==null)return;final yieldCount=int.tryParse(answer.trim());
    if(yieldCount==null||yieldCount<0)throw const FormatException('Actual yield must be a nonnegative whole number.');
    await widget.store.save('production',{...run.fields,'actualYield':yieldCount,'actualYieldAt':widget.clock().toUtc().toIso8601String(),'status':'complete','state':'packed'},id:run.id);
    if(mounted)setState(()=>status='Actual packed quantity recorded. Original planned quantities are retained; future reservations released.');
  }
  String _csv(ProductionPlanResult plan){
    final schedule=plan.planning.candidates.first;
    return safeCsv([
      ['Crispy Crust production run',name.text.trim()],['Status','EXPERIMENTAL — not kitchen validated'],['Acceptance',savedRun==null?'Unaccepted draft':'Accepted local run'],['Times','Device local display; saved schedule uses absolute UTC instants'],
      ['Batch','Product','Planned pieces','Planned dough g','Ready by (local)','Pickup ends (local)','Actual packed'],
      for(final b in plan.blueprint.batches)[b.id,b.title,b.pieces,b.formula.totalDough.toDouble().toStringAsFixed(1),_localInput(schedule.task(b.readyStepId).start.toLocal()),_localInput(b.pickupWindow.end.toLocal()),'Unknown'],
      [],['Ingredient','Total grams'],for(final e in plan.blueprint.shoppingDemand.entries)[e.key,e.value.toDouble().toStringAsFixed(1)],[],['Notes',notes.text],['Notice','Confirm ingredient/allergen labels and local requirements; no food-business certification.'],
    ]);
  }
  Future<void> _share() async {final plan=result;if(plan==null||!plan.feasible)throw StateError('Generate a feasible plan first.');final shared=await widget.exporter.shareTextFile(fileName:'crispy-crust-production.csv',content:_csv(plan),mimeType:'text/csv');if(mounted)setState(()=>status=shared.message);}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Production workspace')),body:SafeArea(child:AnimatedBuilder(animation:widget.store,builder:(context,_)=>ListView(key:const ValueKey('production-scroll'),padding:const EdgeInsets.all(20),children:[
    const Text('For gifting, events and home production. Separate dough loads, oven reservations and packing notes; no customer orders, payments or compliance certification.'),
    const SizedBox(height:12),Semantics(liveRegion:true,child:Text(status)),if(busy)const LinearProgressIndicator(),
    _heading('Run and product'),_field('Run / event name',name,key:'production-name',affectsPlan:false),
    Text('All entered dates use this device’s local time (${widget.clock().timeZoneName}). Saved times are absolute UTC instants, not a promise of an IANA kitchen timezone. Recheck the plan when travelling or changing time settings.'),
    if(widget.store.recipes.isEmpty)const Text('Add a recipe with a complete formula and method before planning production.')else DropdownButtonFormField<String>(initialValue:selectedRecipe,isExpanded:true,decoration:const InputDecoration(labelText:'Recipe'),items:[for(final r in widget.store.recipes)DropdownMenuItem(value:'${r['id']}',child:Text('${r['title']}',overflow:TextOverflow.ellipsis))],onChanged:busy?null:(v)=>setState(()=>selectedRecipe=v)),
    _field('Planned pieces',count,numeric:true,key:'production-count'),_field('Assumed maximum pieces per load',perLoad,numeric:true,key:'production-per-load'),
    _field('Assumed oven set point (°C)',temperature,numeric:true),_field('Pickup starts · YYYY-MM-DD HH:mm',pickupStart,key:'production-pickup-start'),_field('Pickup ends · YYYY-MM-DD HH:mm',pickupEnd,key:'production-pickup-end'),
    CheckboxListTile(key:const ValueKey('production-experimental'),value:experimentalAccepted,onChanged:busy?null:(v)=>setState((){experimentalAccepted=v??false;_invalidate();}),contentPadding:EdgeInsets.zero,title:const Text('I understand these are experimental production assumptions'),subtitle:const Text('Current recipe drafts and load sizes are not kitchen-tested. Changing a load count does not validate its temperature, timing or food safety. No adaptive proof hold is approved.')),
    FilledButton.icon(key:const ValueKey('production-add'),onPressed:busy||!experimentalAccepted||widget.store.recipes.isEmpty?null:()=>_run(_addLine),icon:const Icon(Icons.add),label:const Text('Add this product to the run')),
    for(final line in lines)_panel([Text('${line.recipe['title']} · ${line.pieces} pieces · up to ${line.perLoad}/load'),Text('Pickup ${_localInput(line.pickupStart)}–${_localInput(line.pickupEnd)} · ${line.ovenC.toDouble()}°C assumed'),TextButton(onPressed:busy?null:()=>setState((){lines.remove(line);_invalidate();}),child:const Text('Remove product'))]),
    if(lines.isNotEmpty)...[
      _heading('Equipment and changeovers'),const Text('Capacities below are assumptions to confirm for this kitchen. Oven loads use one conservative serial queue; additional ovens are not automatically optimised.'),
      for(final entry in capacities.entries)_field('${entry.key} capacity',entry.value,numeric:true,key:'production-capacity-${entry.key}'),
      const Text('Resources counted per piece (rather than per load):'),Wrap(spacing:8,children:[for(final id in capacities.keys.where((s)=>s!='oven'))FilterChip(label:Text(id),selected:perPieceResources.contains(id),onSelected:busy?null:(v)=>setState((){v?perPieceResources.add(id):perPieceResources.remove(id);_invalidate();}))]),
      _field('Reload / turnaround minutes',reload,numeric:true),_field('Additional warmer-set-point minutes',warmChange,numeric:true),_field('Additional cooler-set-point minutes',coolChange,numeric:true),
      OutlinedButton(key:const ValueKey('production-generate'),onPressed:busy||!experimentalAccepted?null:()=>_run(_plan),child:const Text('Generate and review separate loads')),
    ],
    if(result!=null)..._resultViews(result!),
    if(savedRun!=null)TextButton(onPressed:busy?null:()=>setState((){lines.clear();name.clear();notes.clear();_invalidate();status='Start another separate run. Previously accepted reservations are still included in conflict checks.';}),child:const Text('Start a new production run')),
    _heading('Saved production runs'),
    for(final run in widget.store.records('production'))_panel([Text(run.text('name'),style:Theme.of(context).textTheme.titleMedium),Text('${_maps(run.fields['batches']).length} separate planned loads · ${run.text('state')}'),Text('Actual packed yield: ${run.text('actualYield','Unknown')}'),if(run.flag('experimental'))const Text('Experimental assumptions — not kitchen-validated.'),TextButton(onPressed:busy?null:()=>_run(()=>_recordYield(run)),child:const Text('Record actual packed quantity')),TextButton(onPressed:busy?null:()=>_run(()async{await widget.store.save('production',{...run.fields,'state':'abandoned','status':'abandoned'},id:run.id);if(mounted)setState(()=>status='Run abandoned; future production reservations released. Historical plan kept.');}),child:const Text('Abandon run and release reservations'))]),
  ]))));
  List<Widget> _resultViews(ProductionPlanResult plan)=>[
    _heading(plan.feasible?'Review loads and pickup readiness':'Review conflicts'),
    for(final assumption in plan.blueprint.assumptions)Padding(padding:const EdgeInsets.only(bottom:8),child:Text(assumption)),
    if(!plan.feasible)for(final issue in plan.planning.issues)_panel([Text(issue.message),if(issue.stepId!=null)Text('Affected step: ${issue.stepId}'),if(issue.resourceId!=null)Text('Equipment: ${issue.resourceId}')]),
    if(plan.feasible)...[
      for(final batch in plan.blueprint.batches)_panel([Text('${batch.title} · ${batch.id}',style:Theme.of(context).textTheme.titleMedium),Text('${batch.pieces} planned pieces · ${batch.formula.totalDough.toDouble().toStringAsFixed(1)} g dough'),Text('Cool/ready: ${_localInput(plan.planning.candidates.first.task(batch.readyStepId).start.toLocal())}'),Text('Pickup: ${_localInput(batch.pickupWindow.start.toLocal())}–${_localInput(batch.pickupWindow.end.toLocal())}'),for(final task in plan.planning.candidates.first.tasks.where((t)=>t.stepId.startsWith('${batch.id}/')))...[const Divider(),Text('${plan.blueprint.graph.steps.firstWhere((s)=>s.id==task.stepId).title}\n${_localInput(task.start.toLocal())} – ${_localInput(task.end.toLocal())}')]]),
      _heading('Ingredients and your prices'),const Text('Prices are optional GBP per kilogram, entered by you today. Unknown prices remain unknown; this is not a retailer quote or tax calculation.'),
      for(final ingredient in plan.blueprint.shoppingDemand.entries)...[Text('${ingredient.key}: ${ingredient.value.toDouble().toStringAsFixed(1)} g'),_field('${ingredient.key} price · GBP/kg (optional)',prices[ingredient.key]!,numeric:true,affectsPlan:false)],
      OutlinedButton(onPressed:busy?null:()=>_run(()async{final total=plan.blueprint.cost(_priceRows(),currency:'GBP');setState(()=>costPreview=total);}),child:const Text('Calculate ingredient cost from my prices')),
      if(costPreview!=null)_panel([
        Text(costPreview!.complete?'Estimated ingredient cost: GBP ${(costPreview!.totalCostMinorUnits!.toDouble()/100).toStringAsFixed(2)}':'Total cost unknown — missing prices: ${costPreview!.missingPrices.join(', ')}'),
        Text('Known-price subtotal: GBP ${(costPreview!.knownCostMinorUnits.toDouble()/100).toStringAsFixed(2)}. Prices entered by you; displayed amounts rounded to pennies.'),
        if(costPreview!.perPortionCostMinorUnits!=null)Text('Ingredient cost per planned piece: GBP ${(costPreview!.perPortionCostMinorUnits!.toDouble()/100).toStringAsFixed(2)}'),
      ]),
      _field('Private packing / ingredient notes',notes,affectsPlan:false),
      FilledButton(key:const ValueKey('production-save'),onPressed:busy||savedRun!=null?null:()=>_run(_save),child:const Text('Accept and save production reservations')),
      OutlinedButton.icon(onPressed:busy?null:()=>_run(_share),icon:const Icon(Icons.ios_share),label:const Text('Share printable pack list CSV')),
      const Text('Labels describe planned pieces and dough mass. Confirm actual packed yield and all ingredient/allergen information before distributing food.'),
    ],
  ];
}
