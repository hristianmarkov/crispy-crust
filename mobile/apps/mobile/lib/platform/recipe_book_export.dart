import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:image/image.dart' as image;
import 'local_media.dart';

class RecipeBookEntry {
  const RecipeBookEntry({required this.id,required this.title,required this.recipeVersion,required this.ingredients,required this.steps,required this.actualSteps,this.notes='',this.source='',this.photos=const []});
  final String id,title,recipeVersion,notes,source;
  final List<Map<String,dynamic>> ingredients,steps,actualSteps;
  final List<LocalPhoto> photos;
  static List<Map<String,dynamic>> _rows(dynamic v)=>v is List?v.whereType<Map>().map((v)=>Map<String,dynamic>.from(v)).toList():[];
  factory RecipeBookEntry.fromBake({required String id,required Map<String,dynamic> bake,List<LocalPhoto> photos=const []}){
    final snapshot=bake['recipeSnapshot'] is Map?Map<String,dynamic>.from(bake['recipeSnapshot'] as Map):<String,dynamic>{};
    return RecipeBookEntry(id:id,title:'${bake['name']??snapshot['title']??'Saved bake'}',recipeVersion:'${snapshot['id']??bake['recipeId']??'Unknown recipe'} · version ${snapshot['version']??bake['recipeVersion']??'not recorded'}',ingredients:_rows(bake['ingredients']),steps:_rows(bake['steps']),actualSteps:_rows(bake['completedSteps']),notes:'${bake['notes']??''}',source:'${snapshot['source']??snapshot['attribution']??''}',photos:List.unmodifiable(photos));
  }
  /// Human preview and tests use this same allowlisted projection. It does not
  /// include account identity, full raw snapshots, calendar blocks or coach text.
  Map<String,dynamic> preview({required bool includeNotes,required bool includeTimes,required bool includePhotos})=>{
    'title':title,'recipeVersion':recipeVersion,'source':source,
    'ingredients':[for(final i in ingredients){'name':i['name']??i['ingredientId']??'Ingredient','grams':i['grams']}],
    'steps':[for(final s in steps){'id':s['id'],'title':s['title'],'instructions':s['instructions'],'readinessCue':s['readinessCue'],if(includeTimes)'plannedStart':s['plannedStart'],if(includeTimes)'plannedEnd':s['plannedEnd']}],
    if(includeTimes)'actualCompletions':[for(final s in actualSteps){'stepId':s['stepId'],'occurredAt':s['occurredAt']}],
    if(includeNotes)'notes':notes,
    if(includePhotos)'selectedPhotoCount':photos.length,
  };
}
class RecipeBookResult {
  const RecipeBookResult(this.bytes,this.pages,this.includedPhotos,this.warnings);
  final Uint8List bytes;
  final int pages,includedPhotos;
  final List<String> warnings;
}
class RecipeBookExporter {
  RecipeBookExporter({Future<ByteData> Function(String)? fontLoader,Future<Uint8List> Function(LocalPhoto)? photoReader})
    :fontLoader=fontLoader??rootBundle.load,photoReader=photoReader??_readPhoto;
  final Future<ByteData> Function(String) fontLoader;
  final Future<Uint8List> Function(LocalPhoto) photoReader;
  static Future<Uint8List> _readPhoto(LocalPhoto photo)async=>(await LocalMediaService().resolve(photo)).readAsBytes();
  Future<RecipeBookResult> build(List<RecipeBookEntry> entries,{bool includeNotes=false,bool includeTimes=true,bool includePhotos=false,String title='My Crispy Crust recipe book'})async{
    if(entries.isEmpty||entries.length>20){ throw const FormatException('Choose between 1 and 20 bakes per PDF. The JSON archive remains the full-data exit.'); }
    if(title.isEmpty||title.length>160){ throw const FormatException('Use a title between 1 and 160 characters.'); }
    if(entries.map((e)=>e.id).toSet().length!=entries.length){ throw const FormatException('Select each bake once.'); }
    final photos=includePhotos?entries.fold<int>(0,(n,e)=>n+e.photos.length):0;
    if(photos>12){ throw const FormatException('Choose at most 12 photos per PDF.'); }
    for(final e in entries){
      if(e.title.length>160||e.recipeVersion.length>300||e.ingredients.length>120||e.steps.length>80||(includePhotos&&e.photos.length>3)){ throw const FormatException('An entry exceeds the bounded recipe-book size. Choose fewer rows/photos.'); }
      if(includeNotes&&e.notes.length>4000){ throw const FormatException('A note exceeds 4000 characters. Use the full JSON archive for the unabridged record.'); }
      if(e.source.length>2000){ throw const FormatException('An attribution exceeds the PDF size limit.'); }
      for(final i in e.ingredients){if('${i['name']??i['ingredientId']??''}'.length>160||i['grams'] is! num||!(i['grams'] as num).isFinite||(i['grams'] as num)<0){ throw const FormatException('Ingredient weights must be recorded finite grams, not assumed or missing.'); }}
      for(final s in e.steps){if('${s['instructions']??''}'.length>1200||'${s['readinessCue']??''}'.length>600){ throw const FormatException('A method step exceeds the PDF text limit. Use the JSON archive for the unabridged record.'); }}
    }
    // Bound work before font/image I/O or PDF layout. Count only the explicit
    // export projection; excluded private notes/metadata never enter the budget.
    var selectedText=title.length,selectedRows=0,selectedHardLines=0;
    void countLines(dynamic value){if(value is String)selectedHardLines+=RegExp(r'\r\n|\r|\n').allMatches(value).length;}
    countLines(title);
    for(final e in entries){
      selectedText+=e.title.length+e.recipeVersion.length+e.source.length;
      for(final value in [e.title,e.recipeVersion,e.source]){countLines(value);}
      if(includeNotes)countLines(e.notes);
      if(includeNotes)selectedText+=e.notes.length;
      selectedRows+=e.ingredients.length+e.steps.length;
      for(final i in e.ingredients){selectedText+='${i['name']??i['ingredientId']??'Ingredient'}'.length+'${i['grams']}'.length;countLines(i['name']??i['ingredientId']);}
      for(final step in e.steps){for(final value in [step['title'],step['instructions'],step['readinessCue']]){countLines(value);}selectedText+='${step['title']??''}'.length+'${step['instructions']??''}'.length+'${step['readinessCue']??''}'.length;if(includeTimes)selectedText+=_time(step['plannedStart']).length+_time(step['plannedEnd']).length;}
      if(includeTimes){final counts=<dynamic,int>{};final includedStepIds=e.steps.map((step)=>step['id']).toSet();for(final actual in e.actualSteps.where((a)=>includedStepIds.contains(a['stepId']))){selectedText+=_time(actual['occurredAt']).length;final id=actual['stepId'];counts[id]=(counts[id]??0)+1;if(counts[id]!>5)throw const FormatException('Repeated actual completions need review before PDF export. Use the full JSON archive for the history.');}}
    }
    if(selectedText>80000||selectedRows>1000||selectedHardLines>1000)throw const FormatException('Selected book exceeds 80,000 text characters, 1,000 method/ingredient rows or 1,000 hard line breaks. Choose fewer bakes; no content was truncated.');
    final sans=pw.Font.ttf(await fontLoader('assets/brand/DMSans-Variable.ttf'));
    final serif=pw.Font.ttf(await fontLoader('assets/brand/DMSerifDisplay-Regular.ttf'));
    final document=pw.Document(title:title,author:'',creator:'Crispy Crust local export',theme:pw.ThemeData.withFont(base:sans,bold:sans));
    final warnings=<String>[];var includedPhotos=0,photoBytes=0;
    for(final entry in entries){
      final contents=<pw.Widget>[
        pw.Text(entry.title,style:pw.TextStyle(font:serif,fontSize:24,color:const PdfColor.fromInt(0xff263024))),
        pw.SizedBox(height:8),pw.Text(entry.recipeVersion),
        pw.SizedBox(height:8),pw.Text('Exact saved weigh-out quantities. Timing records are observations or plans, never proof of readiness.',style:const pw.TextStyle(fontSize:9)),
        if(entry.source.isNotEmpty)pw.Padding(padding:const pw.EdgeInsets.only(top:8),child:pw.Text('Attribution: ${entry.source}',style:const pw.TextStyle(fontSize:9))),
        pw.SizedBox(height:16),pw.Text('Formula',style:pw.TextStyle(fontSize:16,fontWeight:pw.FontWeight.bold)),
        pw.TableHelper.fromTextArray(headers:['Ingredient','Saved mass (g)'],data:[for(final i in entry.ingredients)['${i['name']??i['ingredientId']??'Ingredient'}','${i['grams']}']],headerStyle:pw.TextStyle(fontWeight:pw.FontWeight.bold),cellStyle:const pw.TextStyle(fontSize:10),headerDecoration:const pw.BoxDecoration(color:PdfColors.grey200),cellAlignment:pw.Alignment.centerLeft),
        pw.SizedBox(height:16),pw.Text('Method and records',style:pw.TextStyle(fontSize:16,fontWeight:pw.FontWeight.bold)),
      ];
      for(var n=0;n<entry.steps.length;n++){
        final s=entry.steps[n];final actual=includeTimes?entry.actualSteps.where((a)=>a['stepId']==s['id']).map((a)=>a['occurredAt']).toList():const <dynamic>[];
        contents.addAll([pw.SizedBox(height:10),pw.Text('${n+1}. ${s['title']??'Step'}',style:pw.TextStyle(fontWeight:pw.FontWeight.bold)),if('${s['instructions']??''}'.isNotEmpty)pw.Text('${s['instructions']}'),if('${s['readinessCue']??''}'.isNotEmpty)pw.Text('Observe: ${s['readinessCue']}',style:const pw.TextStyle(fontSize:10)),if(includeTimes)pw.Text('Planned: ${_time(s['plannedStart'])} to ${_time(s['plannedEnd'])}\nActual completion: ${actual.isEmpty?'Not recorded':actual.map(_time).join('; ')}',style:const pw.TextStyle(fontSize:9))]);
      }
      if(includeNotes&&entry.notes.isNotEmpty)contents.addAll([pw.SizedBox(height:16),pw.Text('My notes / next time',style:pw.TextStyle(fontWeight:pw.FontWeight.bold)),pw.Text(entry.notes)]);
      if(includePhotos)for(final photo in entry.photos){
        try{
          final bytes=await photoReader(photo);
          if(bytes.length>4*1024*1024||photoBytes+bytes.length>24*1024*1024){ throw const FormatException('Photo byte budget exceeded.'); }
          final decoded=image.decodeImage(bytes);if(decoded==null||decoded.width>1600||decoded.height>1600){ throw const FormatException('Photo cannot be rendered within the export limit.'); }
          photoBytes+=bytes.length;includedPhotos++;
          contents.addAll([pw.SizedBox(height:12),pw.Image(pw.MemoryImage(bytes),height:180,fit:pw.BoxFit.contain),pw.Text('Selected private observation photo. It is not a diagnosis or a guaranteed recipe result.',style:const pw.TextStyle(fontSize:9))]);
        }catch(_){warnings.add('${entry.title}: selected photo ${photo.id} was unavailable or exceeded the export limit; it was not included.');contents.add(pw.Text('A selected photo could not be included. The formula and text remain available.',style:const pw.TextStyle(fontSize:9)));}
      }
      await Future<void>.delayed(Duration.zero);
      document.addPage(pw.MultiPage(pageFormat:PdfPageFormat.a4,margin:const pw.EdgeInsets.all(36),maxPages:8,build:(_)=>contents,footer:(context)=>pw.Text('$title · ${context.pageNumber} / ${context.pagesCount}',style:const pw.TextStyle(fontSize:9))));
      if(document.document.pdfPageList.pages.length>80)throw const FormatException('Book layout exceeds 80 pages. Choose fewer bakes or photos; no PDF was shared.');
    }
    final bytes=await document.save(enableEventLoopBalancing:true);final pages=document.document.pdfPageList.pages.length;
    if(pages>80||bytes.length>32*1024*1024){ throw const FormatException('This book exceeds 80 pages or 32 MB. Choose fewer bakes or photos.'); }
    return RecipeBookResult(bytes,pages,includedPhotos,List.unmodifiable(warnings));
  }
  static String _time(dynamic value){final parsed=DateTime.tryParse('$value');return parsed==null?'Not recorded':parsed.toUtc().toIso8601String();}
  Future<bool> printBook(RecipeBookResult result) => Printing.layoutPdf(name:'Crispy Crust selected recipe book',format:PdfPageFormat.a4,dynamicLayout:false,onLayout:(_)=>result.bytes);
  Future<bool> shareBook(RecipeBookResult result)=>Printing.sharePdf(bytes:result.bytes,filename:'crispy-crust-selected-recipe-book.pdf',subject:'My selected Crispy Crust recipe book');
}
