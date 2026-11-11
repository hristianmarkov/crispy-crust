import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:crispy_crust/data/local_database.dart';
import 'package:crispy_crust/data/local_store.dart';

Map<String,dynamic> recipe()=>{'id':'test','version':1,'title':'Synthetic fixture, not a recipe','status':'experimental','ingredients':[{'id':'flour','name':'flour','grams':450},{'id':'water','name':'water','grams':300},{'id':'starter','name':'starter','grams':100},{'id':'salt','name':'salt','grams':10}], 'steps':[{'id':'mix','title':'Mix','durationMinutes':2,'kind':'handsOn','after':[],'resources':[]},{'id':'cool','title':'Cool','durationMinutes':2,'kind':'wait','after':['mix'],'resources':[]}]};
void main(){
  late LocalDatabase db;late LocalAppStore store;
  setUp(()async{db=LocalDatabase.memory();store=LocalAppStore(db,{'recipes':[recipe()]});await store.load();});
  tearDown(()async{await db.close();});
  test('feed and starter mass commit together and preserve exact hydration',()async{
    final starter=await store.save('starter',{'name':'Test','hydration':100,'mass':30});
    await store.logFeed(starter.id,seed:20,flour:40,water:40);
    expect(store.find(starter.id)!.number('mass'),100);
    expect(store.find(starter.id)!.number('hydration'),100);
    expect(store.records('feed'),hasLength(1));expect(store.records('discard').single.number('quantity'),10);
    await expectLater(store.logFeed(starter.id,seed:200,flour:40,water:40),throwsFormatException);
    expect(store.records('feed'),hasLength(1));
  });
  test('simultaneous stale completion never advances twice',()async{
    final bake=await store.createBake(recipe());
    await Future.wait([store.completeStep(bake.id,expectedIndex:0),store.completeStep(bake.id,expectedIndex:0)]);
    expect(store.find(bake.id)!.number('stepIndex'),1);expect(store.records('completion'),hasLength(1));
    await expectLater(store.completeStep(bake.id,expectedIndex:0),throwsStateError);
    await store.completeStep(bake.id,expectedIndex:1);
    await store.completeStep(bake.id,expectedIndex:1);
    expect(store.records('journal'),hasLength(1));expect(store.records('completion'),hasLength(2));
  });
  test('archive restores records, audit history and preferences',()async{
    await store.setPreference('darkMode',true);
    await store.save('starter',{'name':'Original','hydration':100});
    final archive=await store.exportArchive();
    await store.resetLocalData();await store.importArchive(archive);
    expect(store.darkMode,isTrue);expect(store.records('starter').single.text('name'),'Original');
    final result=jsonDecode(await store.exportArchive()) as Map;
    expect((result['events'] as List).length,greaterThanOrEqualTo(2));
  });
  test('archive conflict fails without replacing existing data',()async{
    final row=await store.save('starter',{'name':'Keep me'});final archive=jsonDecode(await store.exportArchive()) as Map;
    ((archive['records'] as List).first as Map)['fields']={'name':'Overwritten'};
    await expectLater(store.importArchive(jsonEncode(archive)),throwsStateError);
    expect(store.find(row.id)!.text('name'),'Keep me');
  });
  test('active records and deadlines survive actual database reopen',()async{
    final dir=await Directory.systemTemp.createTemp('crispy-store-');
    final file=File('${dir.path}/library.sqlite');final fileDb=LocalDatabase.file(file);
    final first=LocalAppStore(fileDb,{});await first.load();
    final due=DateTime.now().toUtc().add(const Duration(minutes:15)).toIso8601String();
    await first.save('timer',{'name':'Fold','dueAt':due,'state':'running'});await fileDb.close();
    final secondDb=LocalDatabase.file(file);final second=LocalAppStore(secondDb,{});await second.load();
    expect(second.records('timer').single.text('dueAt'),due);await secondDb.close();await dir.delete(recursive:true);
  });
  test('larger unmodelled oven load rejected rather than double booked',()async{
    await expectLater(store.createBake(recipe(),scale:2),throwsFormatException);
    expect(store.records('bake'),isEmpty);
  });
}
