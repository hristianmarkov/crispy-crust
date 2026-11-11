import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:crispy_crust/platform/local_media.dart';
import 'package:crispy_crust/platform/recipe_book_export.dart';

void main(){
  Future<ByteData> font(String path)async=>ByteData.sublistView(await File(path).readAsBytes());
  RecipeBookEntry entry({List<LocalPhoto> photos=const []})=>RecipeBookEntry.fromBake(id:'bake-1',bake:{'name':'My actual 70% loaf','recipeId':'R02','recipeVersion':2,'recipeSnapshot':{'id':'R02','version':2,'source':'My own formula'},'ingredients':[{'name':'Added flour','grams':450.0},{'name':'Water','grams':300},{'name':'Levain','grams':100},{'name':'Salt','grams':10}],'steps':[{'id':'mix','title':'Mix','instructions':'Weigh and mix the saved formula.','plannedStart':'2026-11-11T08:00:00Z','plannedEnd':'2026-11-11T08:15:00Z','readinessCue':'Record the actual condition.'}],'completedSteps':[{'stepId':'mix','occurredAt':'2026-11-11T08:18:00Z'}],'notes':'PRIVATE-NOTE-SENTINEL','accountEmail':'DO-NOT-EXPORT@example.com','coachMessages':['PRIVATE-COACH'],'calendarBlocks':['PRIVATE-CALENDAR']},photos:photos);
  final photo=LocalPhoto(id:'11111111-1111-4111-8111-111111111111',relativePath:'photos/11111111-1111-4111-8111-111111111111.jpg',width:200,height:100,sha256:'0'*64,capturedAt:DateTime.utc(2026,11,11));
  test('book preview allowlists formula and chosen data; default excludes notes/photos/private metadata',(){
    final p=entry(photos:[photo]).preview(includeNotes:false,includeTimes:true,includePhotos:false);final text=jsonEncode(p);
    expect(text,contains('450.0'));expect(text,contains('2026-11-11T08:18:00Z'));
    for(final secret in ['PRIVATE-NOTE','DO-NOT-EXPORT','PRIVATE-COACH','PRIVATE-CALENDAR','relativePath','sha256'])expect(text,isNot(contains(secret)));
    expect(p.containsKey('notes'),isFalse);expect(p.containsKey('selectedPhotoCount'),isFalse);
  });
  test('real PDF builds with bundled DM fonts and exact saved formula, without invoking photo reader',()async{
    var reads=0;final result=await RecipeBookExporter(fontLoader:font,photoReader:(_)async{reads++;throw StateError('Photo reading was not allowed');}).build([entry(photos:[photo])]);
    expect(reads,0);expect(ascii.decode(result.bytes.take(5).toList()),'%PDF-');expect(result.bytes.length,greaterThan(1000));expect(result.pages,inInclusiveRange(1,8));expect(result.includedPhotos,0);expect(result.warnings,isEmpty);
  });
  test('selected valid photo is included only after explicit photo opt-in',()async{
    final bytes=Uint8List.fromList(image.encodeJpg(image.Image(width:200,height:100)));var reads=0;
    final result=await RecipeBookExporter(fontLoader:font,photoReader:(_)async{reads++;return bytes;}).build([entry(photos:[photo])],includePhotos:true);
    expect(reads,1);expect(result.includedPhotos,1);expect(result.warnings,isEmpty);expect(result.pages,greaterThan(0));
  });
  test('missing selected photo yields visible warning while retaining usable text PDF',()async{
    final result=await RecipeBookExporter(fontLoader:font,photoReader:(_)async{throw const FileSystemException('Unavailable');}).build([entry(photos:[photo])],includePhotos:true);
    expect(result.includedPhotos,0);expect(result.warnings,hasLength(1));expect(result.warnings.single,contains('not included'));expect(ascii.decode(result.bytes.take(5).toList()),'%PDF-');
  });
  test('selection and formula limits fail before reading fonts/photos or silently truncating records',()async{
    var reads=0;final exporter=RecipeBookExporter(fontLoader:(_)async{reads++;throw StateError('Not reached');});
    await expectLater(exporter.build([]),throwsFormatException);
    await expectLater(exporter.build([entry(),entry()]),throwsFormatException);
    await expectLater(exporter.build([RecipeBookEntry(id:'x',title:'X',recipeVersion:'1',ingredients:[{'name':'Unknown','grams':null}],steps:[],actualSteps:[])]),throwsFormatException);
    expect(reads,0);
  });
  test('planned times can be excluded without inventing actual times',(){
    final p=entry().preview(includeNotes:false,includeTimes:false,includePhotos:false);
    expect(p.containsKey('actualCompletions'),isFalse);expect(jsonEncode(p),isNot(contains('2026-11-11T08')));
  });
  test('cumulative selected text is rejected before font or photo I/O without truncation',()async{
    var fontReads=0,photoReads=0;
    final exporter=RecipeBookExporter(fontLoader:(_)async{fontReads++;throw StateError('Not reached');},photoReader:(_)async{photoReads++;throw StateError('Not reached');});
    final large=[for(var n=0;n<2;n++)RecipeBookEntry(id:'large-$n',title:'Large $n',recipeVersion:'1',ingredients:[{'name':'Flour','grams':500}],steps:[for(var i=0;i<50;i++){'id':'step-$i','title':'Method','instructions':'x'*1000}],actualSteps:[])];
    await expectLater(exporter.build(large),throwsA(isA<FormatException>().having((e)=>e.message,'message',contains('80,000'))));
    expect(fontReads,0);expect(photoReads,0);
    expect(large.first.steps.first['instructions'],hasLength(1000));
  });

  test('newline-heavy selected content is rejected before layout and font I/O',()async{
    var reads=0;final exporter=RecipeBookExporter(fontLoader:(_)async{reads++;throw StateError('Not reached');});
    final e=RecipeBookEntry(id:'lines',title:'Line budget',recipeVersion:'1',ingredients:[{'name':'Flour','grams':500}],steps:[{'id':'a','instructions':'\n'*600},{'id':'b','instructions':'\n'*600}],actualSteps:[]);
    await expectLater(exporter.build([e]),throwsFormatException);expect(reads,0);
  });

}
