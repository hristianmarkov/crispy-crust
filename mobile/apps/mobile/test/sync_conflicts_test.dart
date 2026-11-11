import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:crispy_crust/data/local_database.dart';
import 'package:crispy_crust/data/local_store.dart';
import 'package:crispy_crust/data/sync_client.dart';

const kitchen='11111111-1111-4111-8111-111111111111',user='22222222-2222-4222-8222-222222222222',record='33333333-3333-4333-8333-333333333333',operation='44444444-4444-4444-8444-444444444444';
http.Response response(dynamic data)=>http.Response(jsonEncode({'data':data}),200,headers:{'content-type':'application/json'});
void main(){
  late LocalDatabase db;
  late CloudSyncClient sync;
  var revision=3,pushes=0,calls=0;String remoteOperation='upsert',kind='recipe',localEventKind='RecordUpdated';
  setUp((){db=LocalDatabase.memory();revision=3;pushes=0;calls=0;remoteOperation='upsert';kind='recipe';localEventKind='RecordUpdated';});
  tearDown(()async{sync.close();await db.close();});
  Future<void> prepare()async{
    await db.customStatement('INSERT INTO records(id,kind,fields,revision,updated_at) VALUES(?,?,?,8,?)',[record,kind,jsonEncode({'title':'Local version'}),'2026-11-11T10:00:00Z']);
    await db.customStatement('INSERT INTO events(id,aggregate_id,kind,payload,occurred_at,recorded_at,base_revision) VALUES(?,?,?,?,?,?,7)',[operation,record,localEventKind,jsonEncode({'entity_type':kind,'fields':{'title':'Local version'},'deleted':false}),'2026-11-11T10:00:00Z','2026-11-11T10:00:00Z']);
    await db.customStatement("INSERT INTO outbox(operation_id,aggregate_id,state) VALUES(?,?,'local')",[operation,record]);
    sync=CloudSyncClient.withIdentity(db:db,baseUri:Uri.parse('https://example.supabase.co/functions/v1/app-api/v1'),identity:()=>const SyncIdentity(userId:user,accessToken:'test-token'),transport:MockClient((r)async{
      calls++;
      if(r.url.path.endsWith('/kitchens'))return response([{'id':kitchen,'membership_revision':1}]);
      if(r.url.path.endsWith('/sync/push')){pushes++;return response({'accepted':[],'conflicts':[{'operation_id':operation,'code':'REVISION_CONFLICT','current_revision':revision}]});}
      final cursor=int.parse(r.url.queryParameters['cursor']??'0');
      return response({'changes':cursor>=revision?[]:[{'sequence':revision,'id':record,'kind':kind,'revision':revision,'operation':remoteOperation,'payload':remoteOperation=='upsert'?{'data':{'title':'Server version'}}:<String,dynamic>{}}],'next_cursor':cursor>=revision?cursor:revision,'has_more':false,'membership_revision':1});
    }));
    await sync.enable(kitchenId:kitchen,userOptIn:true,uploadExistingRecords:true);
    await sync.syncOnce();
  }
  test('explicit reviewed server choice unblocks editable record and preserves all local event evidence',()async{
    await prepare();expect(await sync.listConflicts(),hasLength(1));
    final review=await sync.reviewConflict(record);expect(review.canUseServer,isTrue);expect(review.localFields!['title'],'Local version');expect(review.remoteRevision,3);
    final resolved=await sync.useReviewedServer(review,confirmed:true,keepLocalCopy:true);expect(resolved.privateCopyId,isNotNull);
    final rows=await db.customSelect('SELECT id,kind,fields FROM records WHERE deleted_at IS NULL').get();expect(rows,hasLength(2));
    final server=rows.singleWhere((r)=>r.read<String>('id')==record);expect(jsonDecode(server.read<String>('fields'))['title'],'Server version');
    final copy=rows.singleWhere((r)=>r.read<String>('kind')=='conflict_copy');expect(jsonDecode(copy.read<String>('fields'))['snapshot'],{'title':'Local version'});
    expect(await sync.listConflicts(),isEmpty);
    expect((await db.customSelect('SELECT state FROM outbox').getSingle()).read<String>('state'),'discarded_resolution');
    final events=await db.customSelect('SELECT kind,payload FROM events ORDER BY recorded_at').get();expect(events,hasLength(2));expect(events.any((r)=>r.read<String>('kind')=='SyncConflictResolved'),isTrue);expect(events.any((r)=>r.read<String>('payload').contains('Local version')),isTrue);
    final store=LocalAppStore(db,{'recipes':[],'lessons':[],'guidance':[]});await store.load();await store.save('conflict_copy',{'name':'Still private'},id:resolved.privateCopyId);store.dispose();
    final report=await sync.syncOnce();expect(report.skipped,1);expect(pushes,1); // No private archive upload.
  });
  test('a server edit after preview rejects stale review without overwriting or clearing pending evidence',()async{
    await prepare();final review=await sync.reviewConflict(record);revision=4;
    await expectLater(sync.useReviewedServer(review,confirmed:true),throwsA(isA<SyncFailure>().having((e)=>e.code,'code','CONFLICT_REVIEW_STALE')));
    expect(jsonDecode((await db.customSelect('SELECT fields FROM records').getSingle()).read<String>('fields'))['title'],'Local version');
    expect(await sync.listConflicts(),isNotEmpty);
  });
  test('a local edit after preview rejects stale consent',()async{
    await prepare();final review=await sync.reviewConflict(record);await db.customStatement("UPDATE records SET revision=9,fields=? WHERE id=?",[jsonEncode({'title':'New local edit'}),record]);
    await expectLater(sync.useReviewedServer(review,confirmed:true),throwsA(isA<SyncFailure>().having((e)=>e.code,'code','CONFLICT_REVIEW_STALE')));
    expect(jsonDecode((await db.customSelect('SELECT fields FROM records').getSingle()).read<String>('fields'))['title'],'New local edit');
  });
  test('physical actions cannot be resolved through snapshot overwrite',()async{
    kind='feed';localEventKind='StarterFed';await prepare();final review=await sync.reviewConflict(record);expect(review.canUseServer,isFalse);
    await expectLater(sync.useReviewedServer(review,confirmed:true),throwsA(isA<SyncFailure>().having((e)=>e.code,'code','PHYSICAL_RECONCILIATION_REQUIRED')));
    expect(await sync.listConflicts(),isNotEmpty);expect((await db.customSelect('SELECT * FROM events').get()).length,1);
  });
  test('accepted tombstone stays deleted while the local version is retained only as a private archive',()async{
    remoteOperation='tombstone';await prepare();final review=await sync.reviewConflict(record);expect(review.canUseServer,isTrue);
    await sync.useReviewedServer(review,confirmed:true,keepLocalCopy:true);
    expect((await db.customSelect("SELECT deleted_at FROM records WHERE id='$record'").getSingle()).readNullable<String>('deleted_at'),isNotNull);
    expect((await db.customSelect("SELECT id FROM records WHERE kind='conflict_copy' AND deleted_at IS NULL").get()),hasLength(1));
    expect((await db.customSelect('SELECT id FROM events').get()),hasLength(2));
  });
  test('unconfirmed resolution performs no new network action',()async{
    await prepare();final review=await sync.reviewConflict(record);final before=calls;
    await expectLater(sync.useReviewedServer(review,confirmed:false),throwsA(isA<SyncFailure>().having((e)=>e.code,'code','EXPLICIT_RESOLUTION_REQUIRED')));expect(calls,before);
  });
}
