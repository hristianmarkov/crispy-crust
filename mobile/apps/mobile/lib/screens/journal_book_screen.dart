import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:baking_domain/baking_domain.dart';
import '../data/app_store.dart';
import '../platform/local_media.dart';
import '../platform/recipe_book_export.dart';

class JournalBookScreen extends StatefulWidget {
  const JournalBookScreen({super.key,required this.store,this.exporter});
  final AppStore store;
  final RecipeBookExporter? exporter;
  @override State<JournalBookScreen> createState()=>_JournalBookScreenState();
}
class _JournalBookScreenState extends State<JournalBookScreen> {
  final title=TextEditingController(text:'My Crispy Crust recipe book');
  final selected=<String>{},selectedPhotos=<String>{};
  bool notes=false,times=true,photos=false,busy=false;
  String message='Select only the bakes and fields you want to include. Nothing is uploaded.';
  RecipeBookResult? result;
  late final exporter=widget.exporter??RecipeBookExporter();
  List<AppRecord> get bakes=>widget.store.records('bake').where((b)=>b.fields['ingredients'] is List).toList();
  List<(AppRecord,LocalPhoto)> photosFor(String bakeId){final result=<(AppRecord,LocalPhoto)>[];for(final o in widget.store.records('observation').where((o)=>o.text('objectId')==bakeId)){try{if(o.fields['photo'] is Map)result.add((o,LocalPhoto.fromJson(Map<String,dynamic>.from(o.fields['photo'] as Map))));}catch(_){/* Invalid references are excluded; they never grant arbitrary file access. */}}return result;}
  List<RecipeBookEntry> entries()=>[for(final b in bakes.where((b)=>selected.contains(b.id)))RecipeBookEntry.fromBake(id:b.id,bake:b.fields,photos:photos?[for(final p in photosFor(b.id))if(selectedPhotos.contains(p.$2.id))p.$2]:[])];
  void change(VoidCallback update)=>setState((){update();result=null;});
  Future<void> generate()async{if(busy)return;setState(()=>busy=true);try{final current=entries();final built=await exporter.build(current,title:title.text.trim(),includeNotes:notes,includeTimes:times,includePhotos:photos).timeout(const Duration(seconds:45));if(mounted)setState((){result=built;message='Prepared locally: ${built.pages} pages, ${built.includedPhotos} selected photos. ${built.warnings.isEmpty?'Review before sharing.':built.warnings.join(' ')}';});}catch(e){if(mounted)setState(()=>message='PDF was not prepared: $e. Your selection and source records are unchanged.');}finally{if(mounted)setState(()=>busy=false);}}
  Future<void> output(bool print)async{final current=result;if(current==null||busy)return;setState(()=>busy=true);try{final accepted=print?await exporter.printBook(current):await exporter.shareBook(current);if(mounted)setState(()=>message=accepted?'The system ${print?'print':'share'} flow accepted the document. This does not prove a physical print or recipient delivery.':'The system ${print?'print':'share'} flow was cancelled or unavailable. Your PDF selection is retained.');}catch(e){if(mounted)setState(()=>message='System output was not completed: $e. No source records were changed.');}finally{if(mounted)setState(()=>busy=false);}}
  @override void dispose(){title.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('My recipe book')),body:SafeArea(child:ListView(key:const ValueKey('recipe-book-scroll'),padding:const EdgeInsets.all(20),children:[
    Semantics(liveRegion:true,child:Text(message)),if(busy)const LinearProgressIndicator(),const SizedBox(height:16),
    TextField(controller:title,maxLength:160,decoration:const InputDecoration(labelText:'Book title'),onChanged:(_)=>change((){})),
    const Text('A PDF is a selected human-readable copy, not a full backup. The structured JSON archive remains available in Data & privacy. PDF times are shown in UTC with dates to avoid timezone ambiguity.'),
    const SizedBox(height:16),
    Text('${selected.length} bakes selected · ${photos?selectedPhotos.length:0} photos chosen',style:Theme.of(context).textTheme.titleMedium),
    if(bakes.isEmpty)const Padding(padding:EdgeInsets.all(16),child:Text('No saved bake formulas yet. Complete or save a bake before creating a recipe book.')),
    for(final bake in bakes)CheckboxListTile(contentPadding:EdgeInsets.zero,title:Text(bake.text('name','Saved bake')),subtitle:Text('${bake.text('state','unknown')} · ${photosFor(bake.id).length} valid local photo references'),value:selected.contains(bake.id),onChanged:busy?null:(v)=>change((){if(v==true){selected.add(bake.id);}else{selected.remove(bake.id);selectedPhotos.removeAll(photosFor(bake.id).map((p)=>p.$2.id));}})),
    const Divider(),
    SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Include my outcome and next-time notes'),subtitle:const Text('Off by default. Read each chosen note in the preview.'),value:notes,onChanged:busy?null:(v)=>change(()=>notes=v)),
    SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Include planned and actual times'),subtitle:const Text('Missing actuals remain “Not recorded”; plans are never relabelled as actuals.'),value:times,onChanged:busy?null:(v)=>change(()=>times=v)),
    SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Choose private observation photos'),subtitle:const Text('Off by default. Choose individual photos below; no automatic all-photo export.'),value:photos,onChanged:busy?null:(v)=>change(()=>photos=v)),
    if(photos)for(final bake in bakes.where((b)=>selected.contains(b.id)))...[Text('Photos for ${bake.text('name')}',style:Theme.of(context).textTheme.titleMedium),for(final p in photosFor(bake.id))CheckboxListTile(title:Text('Observation ${p.$1.updatedAt.toLocal()}'),subtitle:Text('${p.$2.width} × ${p.$2.height} · private local attachment'),value:selectedPhotos.contains(p.$2.id),onChanged:busy?null:(v)=>change((){if(v==true){selectedPhotos.add(p.$2.id);}else{selectedPhotos.remove(p.$2.id);}}))],
    const SizedBox(height:16),
    OutlinedButton(onPressed:busy||selected.isEmpty?null:()=>showDialog<void>(context:context,builder:(c)=>AlertDialog(title:const Text('Exactly what this book will include'),content:SizedBox(width:560,child:SingleChildScrollView(child:SelectableText(const JsonEncoder.withIndent('  ').convert([for(final e in entries())e.preview(includeNotes:notes,includeTimes:times,includePhotos:photos)])))),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Return to selection'))])),child:const Text('Preview selected data')),
    FilledButton(onPressed:busy||selected.isEmpty?null:generate,child:const Text('Prepare selected PDF locally')),
    if(result!=null)...[const SizedBox(height:12),Text('${result!.pages} pages · ${result!.bytes.length} bytes · ${result!.includedPhotos} photos'),OutlinedButton.icon(onPressed:busy?null:()=>output(false),icon:const Icon(Icons.ios_share),label:const Text('Save or share PDF')),OutlinedButton.icon(onPressed:busy?null:()=>output(true),icon:const Icon(Icons.print_outlined),label:const Text('Open system print preview'))],
    const SizedBox(height:20),const Text('Limits: 20 bakes, 12 photos (at most 3 per bake), 80 pages, 32 MB, 80,000 selected text characters, 1,000 method/ingredient rows and 1,000 hard line breaks. Unavailable photos are omitted with an explicit warning. This tool sends nothing to a cloud service; a destination chosen in the system share/print dialog may receive your selected document.'),
    const SizedBox(height:20),OutlinedButton(onPressed:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>JournalInsightsScreen(store:widget.store))),child:const Text('Compare recorded bakes and experiments')),
  ])));
}

class JournalInsightsScreen extends StatefulWidget {
  const JournalInsightsScreen({super.key,required this.store});
  final AppStore store;
  @override State<JournalInsightsScreen> createState()=>_JournalInsightsScreenState();
}
class _JournalInsightsScreenState extends State<JournalInsightsScreen> {
  String? baselineId,otherId;
  final intended=<String>{};
  String message='A personal comparison does not establish cause. Missing measurements are not zeros.';
  static const labels={'hydration_percent':'Hydration (%)','temperature_c':'Latest recorded dough temperature (°C)','rise_percent':'Latest recorded rise (%)','recorded_span_minutes':'Span of recorded bake actuals (min)'};
  List<AppRecord> get bakes=>widget.store.records('bake').where((b)=>b.text('state')=='complete').toList();
  Rational? number(dynamic value){final n=value is num?value:num.tryParse('$value');return n!=null&&n.isFinite?Rational.fromNum(n):null;}
  BakeMeasurements measurements(AppRecord bake){
    final snapshot=bake.fields['recipeSnapshot'] is Map?bake.fields['recipeSnapshot'] as Map:<String,dynamic>{};
    final observations=widget.store.records('observation').where((o)=>o.text('objectId')==bake.id).toList()..sort((a,b)=>(b.date('occurredAt')??b.updatedAt).compareTo(a.date('occurredAt')??a.updatedAt));
    Rational? latest(String key){for(final o in observations){final v=number(o.fields[key]);if(v!=null)return v;}return null;}
    final start=bake.date('startedAt'),end=bake.date('completedAt');
    return BakeMeasurements(bakeId:bake.id,recipeVersion:'${snapshot['id']??bake.fields['recipeId']??'unknown'}:${snapshot['version']??bake.fields['recipeVersion']??'unknown'}',measurements:{'hydration_percent':number(snapshot['hydrationPercent']??snapshot['hydration']),'temperature_c':latest('temperature'),'rise_percent':latest('rise'),'recorded_span_minutes':start!=null&&end!=null&&!end.isBefore(start)?Rational.fromNum(end.difference(start).inSeconds)/Rational.fromNum(60):null},conditions:{'starter':bake.text('starterId').isEmpty?null:bake.text('starterId'),'formula':jsonEncode(bake.fields['ingredients']??[])});
  }
  Widget chart(String key,Rational? left,Rational? right){
    final values=[if(left!=null)left.toDouble(),if(right!=null)right.toDouble()];
    final low=values.isEmpty?0.0:values.reduce((a,b)=>a<b?a:b),high=values.isEmpty?1.0:values.reduce((a,b)=>a>b?a:b);
    double fraction(double value){if(high==low)return 1;final scale=high.abs()>low.abs()?high.abs():low.abs();final normal=(value/scale-low/scale)/(high/scale-low/scale);return (.15+.85*normal).clamp(.15,1).toDouble();}
    Widget row(String name,Rational? value)=>Padding(padding:const EdgeInsets.only(top:8),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[Text('$name: ${value==null?'Not recorded':value.toDouble().toStringAsFixed(2)}'),if(value!=null)Semantics(label:'$name ${labels[key]} ${value.toDouble()}',child:LayoutBuilder(builder:(c,constraints)=>Align(alignment:Alignment.centerLeft,child:Container(width:constraints.maxWidth*fraction(value.toDouble()),height:8,color:Theme.of(context).colorScheme.primary))))]));
    return Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[Text(labels[key]!,style:Theme.of(context).textTheme.titleMedium),row('Baseline',left),row('Comparison',right),const SizedBox(height:8),const Text('Bar lengths are normalised within this pair; read the numeric units above. Unknown values have no bar.')])));
  }
  @override Widget build(BuildContext context){
    final baseline=bakes.where((b)=>b.id==baselineId).firstOrNull,other=bakes.where((b)=>b.id==otherId).firstOrNull;
    final a=baseline==null?null:measurements(baseline),b=other==null?null:measurements(other);
    final comparison=a!=null&&b!=null&&a.bakeId!=b.bakeId?const BakeComparator().compare(a,b,intendedVariables:intended):null;
    return Scaffold(appBar:AppBar(title:const Text('Journal comparisons')),body:ListView(padding:const EdgeInsets.all(20),children:[
      Text(message),if(bakes.length<2)const Text('Complete at least two bakes to compare recorded results.'),
      for(final first in [true,false])Padding(padding:const EdgeInsets.symmetric(vertical:8),child:DropdownButtonFormField<String>(isExpanded:true,initialValue:first?baselineId:otherId,decoration:InputDecoration(labelText:first?'Baseline bake':'Comparison bake'),items:bakes.map((b)=>DropdownMenuItem(value:b.id,child:Text(b.text('name'),overflow:TextOverflow.ellipsis))).toList(),onChanged:(v)=>setState((){if(first){baselineId=v;}else{otherId=v;}}))),
      if(a!=null&&b!=null&&a.bakeId==b.bakeId)const Text('Choose two different bakes; one bake is not a two-sample comparison.'),
      if(comparison!=null)...[
        Text(comparison.explanation,style:Theme.of(context).textTheme.titleMedium),
        Text('2 selected bakes · ${widget.store.records('observation').where((o)=>o.text('objectId')==baselineId||o.text('objectId')==otherId).length} observation records. These are personal records, not a controlled population study.'),
        for(final key in labels.keys)chart(key,a!.measurements[key],b!.measurements[key]),
        Text('Missing fields: ${comparison.missingFields.isEmpty?'none':comparison.missingFields.join(', ')}'),
        Text('Other recorded changes: ${comparison.uncontrolledChanges.isEmpty?'none detected':comparison.uncontrolledChanges.join(', ')}'),
        const SizedBox(height:16),const Text('Name the variables you intended to change. Any other changed or missing conditions remain visible.'),
        for(final entry in labels.entries)CheckboxListTile(contentPadding:EdgeInsets.zero,title:Text(entry.value),value:intended.contains(entry.key),onChanged:(v)=>setState((){if(v==true){intended.add(entry.key);}else{intended.remove(entry.key);}})),
        FilledButton(onPressed:()async{try{await widget.store.save('experiment',{'name':'Recorded comparison','baselineBakeId':baselineId,'comparisonBakeId':otherId,'intendedVariables':intended.toList(),'uncontrolledChanges':comparison.uncontrolledChanges,'missingFields':comparison.missingFields,'supportsCausalClaim':false});if(mounted)setState(()=>message='Experiment comparison saved. It records differences and uncertainty; it does not prove a cause.');}catch(e){if(mounted)setState(()=>message='Comparison was not saved: $e');}},child:const Text('Save this experiment comparison')),
      ],
    ]));
  }
}
