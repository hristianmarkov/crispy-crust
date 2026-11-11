import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../platform/cloud_session.dart';
import 'local_database.dart';

class SyncIdentity {
  const SyncIdentity({required this.userId,required this.accessToken});
  final String userId,accessToken;
}
class SyncReport {
  const SyncReport({this.pushed=0,this.pulled=0,this.conflicts=0,this.skipped=0});
  final int pushed,pulled,conflicts,skipped;
}
class SyncFailure implements Exception {
  const SyncFailure(this.code,[this.retryable=false]);
  final String code;
  final bool retryable;
  @override String toString()=>code;
}

/// Explicit, one-shot opt-in sync. Creating an account never enables uploads.
/// A database namespace binds to exactly one cloud user/kitchen. No scheduler,
/// hidden anonymous account, telemetry or background network starts here.
class CloudSyncClient {
  CloudSyncClient({required LocalDatabase db,required CloudSessionService session,
    required Uri baseUri,http.Client? transport})
      : this.withIdentity(db:db,baseUri:baseUri,transport:transport,identity:(){
          final value=session.client?.auth.currentSession;
          return value==null?null:SyncIdentity(userId:value.user.id,accessToken:value.accessToken);
        });
  CloudSyncClient.withIdentity({required this.db,required this.baseUri,
    required SyncIdentity? Function() identity,http.Client? transport})
      : _identity=identity,_transport=transport??http.Client() {
    if(baseUri.userInfo.isNotEmpty||baseUri.hasQuery||baseUri.hasFragment||
      (baseUri.scheme!='https' && !(baseUri.scheme=='http' &&
        {'localhost','127.0.0.1','::1'}.contains(baseUri.host)))) {
      throw const SyncFailure('INVALID_SYNC_ENDPOINT');
    }
  }
  final LocalDatabase db;
  final Uri baseUri;
  final SyncIdentity? Function() _identity;
  final http.Client _transport;
  bool _running=false;
  String? _boundUserForRun;
  static const _uuid=Uuid();
  static const allowedKinds={'starter','recipe','bake','journal','pantry',
    'equipment','availability','production','lesson_progress','experiment',
    'shopping_list','discard','preference','sensor_binding','feed','completion',
    'correction','observation','timer','interruption','lesson','sensor','shopping'};
  static const _reserved={'kitchen_id','created_by','actor_id','entitlements',
    'moderator_role','approved','tested','reviewed_by'};

  Future<void> _init() async {
    // Additive adapter-owned tables; existing app schema and events are preserved.
    await db.customStatement('CREATE TABLE IF NOT EXISTS sync_namespace (singleton INTEGER PRIMARY KEY CHECK(singleton=1), user_id TEXT NOT NULL, kitchen_id TEXT NOT NULL, enabled INTEGER NOT NULL DEFAULT 0, minimum_event_rowid INTEGER NOT NULL DEFAULT 0, membership_revision INTEGER NOT NULL DEFAULT 1)');
    await db.customStatement('CREATE TABLE IF NOT EXISTS sync_bindings (id TEXT NOT NULL, kitchen_id TEXT NOT NULL, remote_revision INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(id,kitchen_id))');
    await db.customStatement('CREATE TABLE IF NOT EXISTS sync_requests (operation_id TEXT PRIMARY KEY, kitchen_id TEXT NOT NULL, body TEXT NOT NULL)');
    await db.customStatement('CREATE TABLE IF NOT EXISTS sync_remote_audit (kitchen_id TEXT NOT NULL, sequence INTEGER NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(kitchen_id,sequence))');
    await db.customStatement('CREATE TABLE IF NOT EXISTS sync_conflicts (kitchen_id TEXT NOT NULL, sequence INTEGER NOT NULL, aggregate_id TEXT NOT NULL, code TEXT NOT NULL, remote_payload TEXT NOT NULL, PRIMARY KEY(kitchen_id,sequence,aggregate_id))');
  }
  SyncIdentity _requireIdentity() {
    final result=_identity();
    if(result==null||result.userId.isEmpty||result.accessToken.isEmpty) throw const SyncFailure('AUTH_REQUIRED');
    return result;
  }
  Future<dynamic> _call(String method,String path,{Map<String,dynamic>? body,
      Map<String,String>? query,String? operationId}) async {
    final identity=_requireIdentity();
    if(_running && _boundUserForRun!=null) {
      if(identity.userId!=_boundUserForRun)throw const SyncFailure('ACCOUNT_CHANGED_DURING_SYNC');
      final binding=await db.customSelect('SELECT enabled FROM sync_namespace WHERE singleton=1').getSingleOrNull();
      if(binding==null||binding.read<int>('enabled')!=1)throw const SyncFailure('SYNC_CONSENT_WITHDRAWN');
    }
    final uri=baseUri.replace(path:'${baseUri.path.replaceAll(RegExp(r'/+$'),'')}/$path',queryParameters:query);
    final request=http.Request(method,uri)..followRedirects=false;
    request.headers.addAll({'authorization':'Bearer ${identity.accessToken}','content-type':'application/json'});
    if(operationId!=null)request.headers['idempotency-key']=operationId;
    if(body!=null)request.body=jsonEncode(body);
    final response=await http.Response.fromStream(await _transport.send(request).timeout(const Duration(seconds:20)));
    if(response.bodyBytes.length>2*1024*1024)throw const SyncFailure('SYNC_RESPONSE_TOO_LARGE');
    if(_identity()?.userId!=identity.userId)throw const SyncFailure('ACCOUNT_CHANGED_DURING_SYNC');
    if(response.statusCode>=300&&response.statusCode<400)throw const SyncFailure('SYNC_REDIRECT_REJECTED');
    dynamic result;
    try{result=jsonDecode(response.body);}on FormatException{throw const SyncFailure('INVALID_SYNC_RESPONSE');}
    if(response.statusCode<200||response.statusCode>=300) {
      final code=result is Map && result['error'] is Map?result['error']['code']?.toString():'SYNC_UNAVAILABLE';
      if(response.statusCode==403) {
        await _init();await db.customStatement('UPDATE sync_namespace SET enabled=0');
      }
      throw SyncFailure(code??'SYNC_UNAVAILABLE',response.statusCode>=500||response.statusCode==429);
    }
    if(result is! Map || !result.containsKey('data'))throw const SyncFailure('INVALID_SYNC_RESPONSE');
    return result['data'];
  }
  Future<Map<String,dynamic>> bootstrapAccount({String? displayName}) async =>
    Map<String,dynamic>.from(await _call('POST','account/bootstrap',body:{if(displayName!=null)'display_name':displayName},operationId:_uuid.v4()) as Map);
  Future<List<Map<String,dynamic>>> listKitchens() async {
    final value=await _call('GET','kitchens');
    if(value is! List)throw const SyncFailure('INVALID_KITCHEN_RESPONSE');
    return value.map((v)=>Map<String,dynamic>.from(v as Map)).toList();
  }
  Future<void> enable({required String kitchenId,required bool userOptIn,
      bool uploadExistingRecords=false}) async {
    if(!userOptIn)throw const SyncFailure('EXPLICIT_SYNC_CONSENT_REQUIRED');
    await _init();final identity=_requireIdentity();
    final kitchens=await listKitchens();
    final matches=kitchens.where((v)=>v['id']==kitchenId).toList();
    if(matches.length!=1)throw const SyncFailure('KITCHEN_ACCESS_REVOKED');
    final existing=await db.customSelect('SELECT * FROM sync_namespace WHERE singleton=1').getSingleOrNull();
    if(existing!=null&&(existing.read<String>('user_id')!=identity.userId||existing.read<String>('kitchen_id')!=kitchenId))throw const SyncFailure('LOCAL_LIBRARY_BOUND_TO_ANOTHER_ACCOUNT');
    final maxRow=await db.customSelect('SELECT COALESCE(MAX(rowid),0) AS last_id FROM events').getSingle();
    final cutoff=uploadExistingRecords?0:maxRow.read<int>('last_id');
    await db.customStatement('INSERT INTO sync_namespace(singleton,user_id,kitchen_id,enabled,minimum_event_rowid,membership_revision) VALUES(1,?,?,1,?,?) ON CONFLICT(singleton) DO UPDATE SET enabled=1,minimum_event_rowid=MIN(sync_namespace.minimum_event_rowid,excluded.minimum_event_rowid),membership_revision=excluded.membership_revision',[identity.userId,kitchenId,cutoff,matches.single['membership_revision']??1]);
  }
  Future<void> disable() async {await _init();await db.customStatement('UPDATE sync_namespace SET enabled=0');}
  Future<bool> isEnabled() async {
    await _init();final row=await db.customSelect('SELECT * FROM sync_namespace WHERE singleton=1').getSingleOrNull();
    return row!=null&&row.read<int>('enabled')==1&&row.read<String>('user_id')==_identity()?.userId;
  }
  Future<String> _device() async {
    final row=await db.customSelect("SELECT value FROM preferences WHERE key='syncDeviceId'").getSingleOrNull();
    if(row!=null)return jsonDecode(row.read<String>('value')) as String;
    final id=_uuid.v4();await db.customStatement("INSERT INTO preferences(key,value) VALUES('syncDeviceId',?)",[jsonEncode(id)]);return id;
  }
  Future<int> _revision(String id,String kitchen) async {
    final row=await db.customSelect('SELECT remote_revision FROM sync_bindings WHERE id=? AND kitchen_id=?',variables:[Variable.withString(id),Variable.withString(kitchen)]).getSingleOrNull();
    return row?.read<int>('remote_revision')??0;
  }
  Future<void> _bind(String id,String kitchen,int revision) async =>db.customStatement('INSERT INTO sync_bindings(id,kitchen_id,remote_revision) VALUES(?,?,?) ON CONFLICT(id,kitchen_id) DO UPDATE SET remote_revision=MAX(sync_bindings.remote_revision,excluded.remote_revision)',[id,kitchen,revision]);

  Future<SyncReport> syncOnce() async {
    if(_running)throw const SyncFailure('SYNC_ALREADY_RUNNING');
    _running=true;
    try {
      await _init();final identity=_requireIdentity();
      _boundUserForRun=identity.userId;
      final namespace=await db.customSelect('SELECT * FROM sync_namespace WHERE singleton=1').getSingleOrNull();
      if(namespace==null||namespace.read<int>('enabled')!=1)throw const SyncFailure('SYNC_NOT_ENABLED');
      if(namespace.read<String>('user_id')!=identity.userId)throw const SyncFailure('LOCAL_LIBRARY_BOUND_TO_ANOTHER_ACCOUNT');
      final kitchen=namespace.read<String>('kitchen_id');
      final device=await _device();int pushed=0,pulled=0,conflicts=0,skipped=0;
      final blocked=<String>{};
      for(final row in await db.customSelect("SELECT aggregate_id FROM outbox WHERE state='conflict'").get())blocked.add(row.read<String>('aggregate_id'));
      final operations=await db.customSelect("SELECT e.rowid AS event_rowid,e.*,o.state FROM events e JOIN outbox o ON o.operation_id=e.id WHERE o.state IN ('local','pending') AND e.rowid>? ORDER BY e.rowid LIMIT 500",variables:[Variable.withInt(namespace.read<int>('minimum_event_rowid'))]).get();
      for(final event in operations) {
        final oid=event.read<String>('id'),aid=event.read<String>('aggregate_id');
        if(blocked.contains(aid))continue;
        final payload=jsonDecode(event.read<String>('payload'));
        if(payload is! Map||payload['entity_type'] is! String||payload['fields'] is! Map) {skipped++;continue;}
        final kind=payload['entity_type'] as String;
        final fields=Map<String,dynamic>.from(payload['fields'] as Map);
        if(!allowedKinds.contains(kind)||fields.keys.any(_reserved.contains)) {skipped++;continue;}
        final cached=await db.customSelect('SELECT body FROM sync_requests WHERE operation_id=?',variables:[Variable.withString(oid)]).getSingleOrNull();
        Map<String,dynamic> operation;
        if(cached!=null) {operation=Map<String,dynamic>.from(jsonDecode(cached.read<String>('body')) as Map);} else {
          final base=await _revision(aid,kitchen);
          if(payload['deleted']==true&&base==0) {
            // Never uploaded: no cloud data exists to delete.
            await db.customStatement("UPDATE outbox SET state='synced' WHERE operation_id=?",[oid]);skipped++;continue;
          }
          operation={'operation_id':oid,'aggregate_id':aid,'base_revision':base,
            'type':payload['deleted']==true?'Delete':'Upsert','schema_version':1,
            if(payload['deleted']!=true)'kind':kind,if(payload['deleted']!=true)'data':fields};
          // Preserve the exact request before IO: retries after an unknown commit
          // outcome must not change base_revision under the same idempotency key.
          await db.customStatement('INSERT INTO sync_requests(operation_id,kitchen_id,body) VALUES(?,?,?)',[oid,kitchen,jsonEncode(operation)]);
        }
        await db.customStatement("UPDATE outbox SET state='pending',attempts=attempts+1 WHERE operation_id=?",[oid]);
        final response=await _call('POST','sync/push',operationId:oid,body:{'kitchen_id':kitchen,'device_id':device,'membership_revision':namespace.read<int>('membership_revision'),'operations':[operation]});
        if(response is! Map||response['accepted'] is! List||response['conflicts'] is! List)throw const SyncFailure('INVALID_SYNC_RESPONSE');
        final accepted=(response['accepted'] as List).where((v)=>v is Map&&v['operation_id']==oid).toList();
        final rejected=(response['conflicts'] as List).where((v)=>v is Map&&v['operation_id']==oid).toList();
        if(accepted.length==1) {
          final revision=accepted.single['revision'];if(revision is! int||revision<1)throw const SyncFailure('INVALID_SYNC_REVISION');
          await db.transaction(() async {await _bind(aid,kitchen,revision);await db.customStatement("UPDATE outbox SET state='synced' WHERE operation_id=?",[oid]);});pushed++;
        } else if(rejected.length==1) {
          await db.transaction(() async {
            await db.customStatement("UPDATE outbox SET state='conflict' WHERE operation_id=?",[oid]);
            await db.customStatement('INSERT OR IGNORE INTO sync_conflicts(kitchen_id,sequence,aggregate_id,code,remote_payload) VALUES(?,0,?,?,?)',[kitchen,aid,rejected.single['code']?.toString()??'REVISION_CONFLICT',jsonEncode(rejected.single)]);
          });blocked.add(aid);conflicts++;
        } else {throw const SyncFailure('SYNC_OPERATION_UNACKNOWLEDGED');}
      }
      final cursorRow=await db.customSelect('SELECT cursor FROM sync_cursors WHERE kitchen_id=?',variables:[Variable.withString(kitchen)]).getSingleOrNull();
      var cursor=cursorRow?.read<int>('cursor')??0;
      for(var page=0;page<100;page++) {
        final response=await _call('GET','sync/pull',query:{'kitchen_id':kitchen,'cursor':'$cursor','limit':'100'});
        if(response is! Map||response['changes'] is! List||response['next_cursor'] is! int||response['has_more'] is! bool)throw const SyncFailure('INVALID_SYNC_RESPONSE');
        final next=response['next_cursor'] as int;
        if(next<cursor||(response['has_more']==true&&next==cursor))throw const SyncFailure('SYNC_CURSOR_NOT_ADVANCING');
        await db.transaction(() async {
          if(_identity()?.userId!=_boundUserForRun)throw const SyncFailure('ACCOUNT_CHANGED_DURING_SYNC');
          for(final raw in response['changes'] as List) {
            if(raw is! Map)throw const SyncFailure('INVALID_SYNC_CHANGE');
            final change=Map<String,dynamic>.from(raw);final sequence=change['sequence'];
            final aid=change['id'],kind=change['kind'],rev=change['revision'];
            if(sequence is! int||sequence<=cursor||sequence>next||aid is! String||kind is! String||rev is! int)throw const SyncFailure('INVALID_SYNC_CHANGE');
            await db.customStatement('INSERT OR IGNORE INTO sync_remote_audit(kitchen_id,sequence,payload) VALUES(?,?,?)',[kitchen,sequence,jsonEncode(change)]);
            final known=await _revision(aid,kitchen);if(rev<=known)continue;
            final pending=await db.customSelect("SELECT o.operation_id FROM outbox o JOIN events e ON e.id=o.operation_id WHERE o.aggregate_id=? AND o.state IN ('local','pending','conflict') AND e.rowid>? LIMIT 1",variables:[Variable.withString(aid),Variable.withInt(namespace.read<int>('minimum_event_rowid'))]).getSingleOrNull();
            final operation=change['operation'];final payload=change['payload'];
            final localCollision=known==0 && await db.customSelect('SELECT id FROM records WHERE id=?',variables:[Variable.withString(aid)]).getSingleOrNull()!=null;
            if(localCollision && pending==null) {
              await db.customStatement('INSERT OR IGNORE INTO sync_conflicts(kitchen_id,sequence,aggregate_id,code,remote_payload) VALUES(?,?,?,?,?)',[kitchen,sequence,aid,'LOCAL_RECORD_NOT_SELECTED_FOR_SYNC',jsonEncode(change)]);conflicts++;continue;
            }
            if(pending!=null||!allowedKinds.contains(kind)||!{'upsert','tombstone'}.contains(operation)) {
              await db.customStatement('INSERT OR IGNORE INTO sync_conflicts(kitchen_id,sequence,aggregate_id,code,remote_payload) VALUES(?,?,?,?,?)',[kitchen,sequence,aid,pending!=null?'LOCAL_CHANGES_PENDING':'REMOTE_CHANGE_REQUIRES_REVIEW',jsonEncode(change)]);
              if(pending!=null)await db.customStatement("UPDATE outbox SET state='conflict' WHERE aggregate_id=? AND state IN ('local','pending')",[aid]);
              conflicts++;continue;
            }
            final now=DateTime.now().toUtc().toIso8601String();
            if(operation=='upsert') {
              if(payload is! Map||payload['data'] is! Map)throw const SyncFailure('INVALID_SYNC_CHANGE');
              final data=Map<String,dynamic>.from(payload['data'] as Map);
              if(data.keys.any(_reserved.contains))throw const SyncFailure('PRIVILEGED_REMOTE_FIELD');
              final old=await db.customSelect('SELECT kind FROM records WHERE id=?',variables:[Variable.withString(aid)]).getSingleOrNull();
              if(old!=null&&old.read<String>('kind')!=kind)throw const SyncFailure('REMOTE_KIND_CHANGED');
              await db.customStatement('INSERT INTO records(id,kind,fields,revision,updated_at,deleted_at) VALUES(?,?,?,?,?,NULL) ON CONFLICT(id) DO UPDATE SET fields=excluded.fields,revision=excluded.revision,updated_at=excluded.updated_at,deleted_at=NULL',[aid,kind,jsonEncode(data),rev,now]);
            } else {
              await db.customStatement('UPDATE records SET deleted_at=?,revision=?,updated_at=? WHERE id=?',[now,rev,now,aid]);
            }
            await _bind(aid,kitchen,rev);pulled++;
          }
          if(_identity()?.userId!=_boundUserForRun)throw const SyncFailure('ACCOUNT_CHANGED_DURING_SYNC');
          await db.customStatement('INSERT INTO sync_cursors(kitchen_id,cursor) VALUES(?,?) ON CONFLICT(kitchen_id) DO UPDATE SET cursor=excluded.cursor',[kitchen,next]);
          if(response['membership_revision'] is int)await db.customStatement('UPDATE sync_namespace SET membership_revision=? WHERE singleton=1',[response['membership_revision']]);
        });
        cursor=next;if(response['has_more']!=true)break;
        if(page==99)throw const SyncFailure('SYNC_PAGINATION_LIMIT',true);
      }
      return SyncReport(pushed:pushed,pulled:pulled,conflicts:conflicts,skipped:skipped);
    } finally {_running=false;_boundUserForRun=null;}
  }
  void close()=>_transport.close();
}
