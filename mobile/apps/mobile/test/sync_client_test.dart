import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:crispy_crust/data/local_database.dart';
import 'package:crispy_crust/data/sync_client.dart';

const kitchen='11111111-1111-4111-8111-111111111111';
const user='22222222-2222-4222-8222-222222222222';
const entity='33333333-3333-4333-8333-333333333333';
const op='44444444-4444-4444-8444-444444444444';
const otherEntity='55555555-5555-4555-8555-555555555555';
http.Response ok(dynamic data)=>http.Response(jsonEncode({'data':data}),200,headers:{'content-type':'application/json'});
http.Response kitchens()=>ok([{'id':kitchen,'membership_revision':1,'kind':'personal'}]);
http.Response pull({List<Map<String,dynamic>> changes=const [],int cursor=0,bool more=false})=>ok({'changes':changes,'next_cursor':cursor,'has_more':more,'membership_revision':1});
Future<void> localEvent(LocalDatabase db,{String id=op,String aggregate=entity,String kind='starter',Map<String,dynamic> fields=const {'name':'Mabel'}}) async {
  await db.customStatement('INSERT INTO records(id,kind,fields,revision,updated_at) VALUES(?,?,?,8,?) ON CONFLICT(id) DO NOTHING',[aggregate,kind,jsonEncode(fields),'2026-11-11T10:00:00Z']);
  await db.customStatement('INSERT INTO events(id,aggregate_id,kind,payload,occurred_at,recorded_at,base_revision) VALUES(?,?,?,?,?,?,7)',[id,aggregate,'RecordUpdated',jsonEncode({'entity_type':kind,'fields':fields,'deleted':false}),'2026-11-11T10:00:00Z','2026-11-11T10:00:00Z']);
  await db.customStatement('INSERT INTO outbox(operation_id,aggregate_id,state) VALUES(?,?,?)',[id,aggregate,'local']);
}
CloudSyncClient client(LocalDatabase db,Future<http.Response> Function(http.Request) handler,{SyncIdentity? Function()? identity})=>CloudSyncClient.withIdentity(db:db,baseUri:Uri.parse('https://example.supabase.co/functions/v1/app-api/v1'),identity:identity??()=>const SyncIdentity(userId:user,accessToken:'test-token'),transport:MockClient(handler));
void main() {
  late LocalDatabase db;
  setUp(() {db=LocalDatabase.memory();});
  tearDown(() async {await db.close();});
  test('does no IO without explicit opt-in; constructor/account is not consent',() async {
    var calls=0;final sync=client(db,(r) async {calls++;return kitchens();});
    expect(calls,0);
    await expectLater(sync.enable(kitchenId:kitchen,userOptIn:false),throwsA(isA<SyncFailure>()));
    await expectLater(sync.syncOnce(),throwsA(isA<SyncFailure>().having((e)=>e.code,'code','SYNC_NOT_ENABLED')));
    expect(calls,0);sync.close();
  });
  test('server revision starts at zero even when local revision is eight',() async {
    await localEvent(db);
    Map<String,dynamic>? operation;
    final sync=client(db,(r) async {
      if(r.url.path.endsWith('/kitchens'))return kitchens();
      if(r.url.path.endsWith('/sync/push')) {operation=Map<String,dynamic>.from((jsonDecode(r.body)['operations'] as List).single as Map);return ok({'accepted':[{'operation_id':op,'revision':1,'change_sequence':1}],'conflicts':[]});}
      return pull();
    });
    await sync.enable(kitchenId:kitchen,userOptIn:true,uploadExistingRecords:true);
    final result=await sync.syncOnce();
    expect(result.pushed,1);expect(operation!['base_revision'],0);expect(operation!['operation_id'],op);
    expect((await db.customSelect('SELECT state FROM outbox').getSingle()).read<String>('state'),'synced');sync.close();
  });
  test('unknown POST outcome retries byte-identical operation under same id',() async {
    await localEvent(db);var fail=true;final bodies=<String>[];
    final sync=client(db,(r) async {
      if(r.url.path.endsWith('/kitchens'))return kitchens();
      if(r.url.path.endsWith('/sync/push')) {
        bodies.add(r.body);if(fail){fail=false;throw http.ClientException('connection dropped after possible commit');}
        return ok({'accepted':[{'operation_id':op,'revision':1,'change_sequence':1}],'conflicts':[]});
      }return pull();
    });
    await sync.enable(kitchenId:kitchen,userOptIn:true,uploadExistingRecords:true);
    await expectLater(sync.syncOnce(),throwsA(isA<http.ClientException>()));
    expect((await sync.syncOnce()).pushed,1);expect(bodies.length,2);expect(bodies[0],bodies[1]);sync.close();
  });
  test('pull persists pagination cursor and private records atomically',() async {
    final cursors=<String?>[];
    final sync=client(db,(r) async {
      if(r.url.path.endsWith('/kitchens'))return kitchens();
      cursors.add(r.url.queryParameters['cursor']);
      if(cursors.length==1)return pull(cursor:1,more:true,changes:[{'sequence':1,'id':entity,'kind':'starter','revision':1,'operation':'upsert','payload':{'data':{'name':'Mabel'}}}]);
      return pull(cursor:2,changes:[{'sequence':2,'id':otherEntity,'kind':'starter','revision':1,'operation':'upsert','payload':{'data':{'name':'Second jar'}}}]);
    });
    await sync.enable(kitchenId:kitchen,userOptIn:true);
    expect((await sync.syncOnce()).pulled,2);expect(cursors,['0','1']);
    expect((await db.customSelect('SELECT cursor FROM sync_cursors').getSingle()).read<int>('cursor'),2);
    expect((await db.customSelect('SELECT * FROM records').get()).length,2);sync.close();
  });
  test('remote conflict never overwrites a pending local physical record',() async {
    await localEvent(db);
    final sync=client(db,(r) async {
      if(r.url.path.endsWith('/kitchens'))return kitchens();
      if(r.url.path.endsWith('/sync/push'))return ok({'accepted':[],'conflicts':[{'operation_id':op,'code':'REVISION_CONFLICT','current_revision':3}]});
      return pull(cursor:3,changes:[{'sequence':3,'id':entity,'kind':'starter','revision':3,'operation':'upsert','payload':{'data':{'name':'Remote'}}}]);
    });
    await sync.enable(kitchenId:kitchen,userOptIn:true,uploadExistingRecords:true);
    expect((await sync.syncOnce()).conflicts,greaterThan(0));
    final record=await db.customSelect('SELECT fields FROM records').getSingle();
    expect(jsonDecode(record.read<String>('fields'))['name'],'Mabel');sync.close();
  });
  test('namespace cannot upload an old library into a different account',() async {
    var current=const SyncIdentity(userId:user,accessToken:'first');
    final sync=client(db,(r) async=>kitchens(),identity:()=>current);
    await sync.enable(kitchenId:kitchen,userOptIn:true);
    current=const SyncIdentity(userId:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',accessToken:'second');
    await expectLater(sync.enable(kitchenId:kitchen,userOptIn:true),throwsA(isA<SyncFailure>().having((e)=>e.code,'code','LOCAL_LIBRARY_BOUND_TO_ANOTHER_ACCOUNT')));
    await expectLater(sync.syncOnce(),throwsA(isA<SyncFailure>()));sync.close();
  });
  test('revoked kitchen access disables future sync and retains local data',() async {
    await localEvent(db);
    final sync=client(db,(r) async {
      if(r.url.path.endsWith('/kitchens'))return kitchens();
      return http.Response(jsonEncode({'error':{'code':'KITCHEN_ACCESS_REVOKED'}}),403);
    });
    await sync.enable(kitchenId:kitchen,userOptIn:true,uploadExistingRecords:true);
    await expectLater(sync.syncOnce(),throwsA(isA<SyncFailure>()));
    expect(await sync.isEnabled(),isFalse);expect((await db.customSelect('SELECT * FROM records').get()).length,1);sync.close();
  });
  test('billing or staff records never enter the upload transport',() async {
    await localEvent(db,kind:'entitlement');var pushes=0;
    final sync=client(db,(r) async {
      if(r.url.path.endsWith('/kitchens'))return kitchens();
      if(r.method=='POST')pushes++;
      return pull();
    });
    await sync.enable(kitchenId:kitchen,userOptIn:true,uploadExistingRecords:true);
    expect((await sync.syncOnce()).skipped,1);expect(pushes,0);sync.close();
  });
  test('excluded old history does not conflict after a newer selected update',() async {
    await localEvent(db);var changesReady=false;
    final sync=client(db,(r) async {
      if(r.url.path.endsWith('/kitchens'))return kitchens();
      if(r.url.path.endsWith('/sync/push')) {
        final operation=(jsonDecode(r.body)['operations'] as List).single as Map;
        return ok({'accepted':[{'operation_id':operation['operation_id'],'revision':1,'change_sequence':1}],'conflicts':[]});
      }
      return changesReady?pull(cursor:2,changes:[{'sequence':2,'id':entity,'kind':'starter','revision':2,'operation':'upsert','payload':{'data':{'name':'Remote after synced update'}}}]):pull();
    });
    await sync.enable(kitchenId:kitchen,userOptIn:true,uploadExistingRecords:false);
    await localEvent(db,id:'66666666-6666-4666-8666-666666666666',fields:{'name':'New local update'});
    expect((await sync.syncOnce()).pushed,1);
    changesReady=true;
    final result=await sync.syncOnce();expect(result.conflicts,0);expect(result.pulled,1);
    final row=await db.customSelect('SELECT fields FROM records').getSingle();
    expect(jsonDecode(row.read<String>('fields'))['name'],'Remote after synced update');sync.close();
  });
  test('pull response after account changes cannot be applied to local records',() async {
    var identity=const SyncIdentity(userId:user,accessToken:'first');
    final sync=client(db,(r) async {
      if(r.url.path.endsWith('/kitchens'))return kitchens();
      identity=const SyncIdentity(userId:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',accessToken:'second');
      return pull(cursor:1,changes:[{'sequence':1,'id':entity,'kind':'starter','revision':1,'operation':'upsert','payload':{'data':{'name':'Wrong account'}}}]);
    },identity:()=>identity);
    await sync.enable(kitchenId:kitchen,userOptIn:true);
    await expectLater(sync.syncOnce(),throwsA(isA<SyncFailure>().having((e)=>e.code,'code','ACCOUNT_CHANGED_DURING_SYNC')));
    expect(await db.customSelect('SELECT * FROM records').get(),isEmpty);sync.close();
  });

  test('create followed by delete uploads in order with server CAS revisions',() async {
    await localEvent(db);
    const deleteOp='77777777-7777-4777-8777-777777777777';
    await db.customStatement('INSERT INTO events(id,aggregate_id,kind,payload,occurred_at,recorded_at,base_revision) VALUES(?,?,?,?,?,?,8)',[deleteOp,entity,'RecordDeleted',jsonEncode({'entity_type':'starter','fields':{'name':'Mabel'},'deleted':true}),'2026-11-11T11:00:00Z','2026-11-11T11:00:00Z']);
    await db.customStatement('INSERT INTO outbox(operation_id,aggregate_id,state) VALUES(?,?,?)',[deleteOp,entity,'local']);
    final sent=<Map>[];
    final sync=client(db,(r) async {
      if(r.url.path.endsWith('/kitchens'))return kitchens();
      if(r.url.path.endsWith('/sync/push')) {
        final operation=(jsonDecode(r.body)['operations'] as List).single as Map;sent.add(operation);
        return ok({'accepted':[{'operation_id':operation['operation_id'],'revision':sent.length,'change_sequence':sent.length}],'conflicts':[]});
      }return pull();
    });
    await sync.enable(kitchenId:kitchen,userOptIn:true,uploadExistingRecords:true);
    expect((await sync.syncOnce()).pushed,2);
    expect(sent.map((v)=>v['type']),['Upsert','Delete']);
    expect(sent.map((v)=>v['base_revision']),[0,1]);sync.close();
  });
  test('malformed later pull change rolls back records audit and cursor together',() async {
    final sync=client(db,(r) async {
      if(r.url.path.endsWith('/kitchens'))return kitchens();
      return pull(cursor:2,changes:[
        {'sequence':1,'id':entity,'kind':'starter','revision':1,'operation':'upsert','payload':{'data':{'name':'First'}}},
        {'sequence':2,'id':otherEntity,'kind':'starter','revision':1,'operation':'upsert','payload':{'data':'invalid'}},
      ]);
    });
    await sync.enable(kitchenId:kitchen,userOptIn:true);
    await expectLater(sync.syncOnce(),throwsA(isA<SyncFailure>()));
    expect(await db.customSelect('SELECT * FROM records').get(),isEmpty);
    expect(await db.customSelect('SELECT * FROM sync_cursors').get(),isEmpty);
    expect(await db.customSelect('SELECT * FROM sync_remote_audit').get(),isEmpty);sync.close();
  });

}
