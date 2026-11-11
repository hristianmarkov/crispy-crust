import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:baking_domain/baking_domain.dart';
import 'app_store.dart';
import 'local_database.dart';
import 'planning_adapter.dart';
import '../platform/local_media.dart';

class LocalAppStore extends AppStore {
  LocalAppStore(this.db, Map<String, dynamic> catalogue,{LocalMediaService? media})
      : media=media??LocalMediaService(), recipes = _maps(catalogue['recipes']),
        lessons = _maps(catalogue['lessons']),
        guidance = _maps(catalogue['guidance']);
  final LocalDatabase db;
  final LocalMediaService media;
  bool _archiveBusy=false;
  final _uuid = const Uuid();
  final Map<String, AppRecord> _records = {};
  final Map<String, dynamic> _preferences = {};
  final Set<String> _stepLocks = {};
  final Set<String> _feedLocks = {};
  bool _creatingBake=false;
  @override final List<Map<String, dynamic>> recipes;
  @override final List<Map<String, dynamic>> lessons;
  @override final List<Map<String, dynamic>> guidance;
  static List<Map<String,dynamic>> _maps(dynamic value) => value is List
      ? value.whereType<Map>().map((v) => freezeJson(v) as Map<String,dynamic>).toList() : [];
  @override bool get darkMode => preference('darkMode', false) == true;
  @override bool get beginnerMode => preference('beginnerMode', true) == true;
  @override String get storageDescription => 'Stored on this device · cloud backup off';
  @override dynamic preference(String key, [dynamic fallback]) => _preferences[key] ?? fallback;
  Future<void> load() async {
    final rows = await db.customSelect('SELECT * FROM records WHERE deleted_at IS NULL ORDER BY updated_at DESC').get();
    _records.clear();
    for (final r in rows) {
      _records[r.read<String>('id')] = AppRecord(id: r.read<String>('id'), kind: r.read<String>('kind'), fields: Map<String,dynamic>.from(jsonDecode(r.read<String>('fields')) as Map), updatedAt: DateTime.parse(r.read<String>('updated_at')),revision:r.read<int>('revision'));
    }
    _preferences.clear();
    for (final r in await db.customSelect('SELECT * FROM preferences').get()) {
      _preferences[r.read<String>('key')] = jsonDecode(r.read<String>('value'));
    }
    notifyListeners();
  }
  @override List<AppRecord> records(String kind) => List.unmodifiable(_records.values.where((r) => r.kind == kind).toList()..sort((a,b)=> b.updatedAt.compareTo(a.updatedAt)));
  @override AppRecord? find(String id) => _records[id];
  void _validate(String kind, Map<String,dynamic> fields) {
    if (kind.isEmpty || kind.length > 80) throw const FormatException('Invalid record type.');
    jsonEncode(fields); // Reject non-serialisable values before touching the database.
    for (final key in ['seed','flour','water','quantity','mass','durationMinutes']) {
      final value = fields[key];
      if (value is num && (!value.isFinite || value < 0)) throw FormatException('$key must be a finite nonnegative amount.');
    }
  }
  Future<void> _write(String kind, Map<String,dynamic> fields, String id, {String eventType = 'RecordUpdated', DateTime? occurredAt, bool deleted = false}) async {
    _validate(kind, fields);
    final old = await db.customSelect('SELECT kind,revision FROM records WHERE id = ?',variables:[Variable.withString(id)]).getSingleOrNull();
    if (old != null && old.read<String>('kind') != kind) throw StateError('An existing record cannot change type.');
    final revision = old?.read<int>('revision') ?? 0;
    final now = DateTime.now().toUtc().toIso8601String();
    final operation = _uuid.v4();
    await db.customStatement('INSERT INTO events (id,aggregate_id,kind,payload,occurred_at,recorded_at,base_revision) VALUES (?,?,?,?,?,?,?)', [operation,id,eventType,jsonEncode({'entity_type':kind,'fields':fields,'deleted':deleted}), (occurredAt??DateTime.now()).toUtc().toIso8601String(),now,revision]);
    await db.customStatement('INSERT INTO records (id,kind,fields,revision,updated_at,deleted_at) VALUES (?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET fields=excluded.fields,revision=excluded.revision,updated_at=excluded.updated_at,deleted_at=excluded.deleted_at',[id,kind,jsonEncode(fields),revision+1,now,deleted?now:null]);
    await db.customStatement('INSERT INTO outbox (operation_id,aggregate_id,state) VALUES (?,?,?)',[operation,id,'local']);
  }
  @override Future<AppRecord> save(String kind, Map<String,dynamic> fields,{String? id}) async {
    final actualId = id ?? _uuid.v4();
    await db.transaction(() => _write(kind,fields,actualId));
    await load();
    return _records[actualId]!;
  }
  @override Future<void> remove(String id) async {
    final row=find(id); if(row==null)return;
    if(row.kind=='starter' && records('bake').any((b)=>b.text('starterId')==id)) {
      await save('starter',{...row.fields,'archived':true},id:id);return;
    }
    await db.transaction(()=>_write(row.kind,row.fields,id,eventType:'RecordDeleted',deleted:true));
    await load();
  }
  @override Future<void> setPreference(String key,dynamic value) async {
    await db.customStatement('INSERT INTO preferences (key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',[key,jsonEncode(value)]);
    _preferences[key]=value;notifyListeners();
  }
  @override Future<void> logFeed(String starterId,{required double seed,required double flour,required double water,DateTime? occurredAt}) async {
    if(!_feedLocks.add(starterId))throw StateError('A feed for this jar is already being recorded.');
    try {
    if(!seed.isFinite||!flour.isFinite||!water.isFinite||seed<0||flour<=0||water<0)throw const FormatException('Enter valid seed, flour and water weights.');
    final starter=find(starterId);if(starter==null||starter.kind!='starter')throw StateError('Starter not found.');
    final at=occurredAt??DateTime.now();
    if(at.isAfter(DateTime.now().add(const Duration(minutes:5))))throw const FormatException('A feed cannot be recorded in the future.');
    final laterFeed=records('feed').any((f)=>f.text('starterId')==starterId && (f.date('occurredAt')?.isAfter(at)??false));
    if(laterFeed)throw StateError('This backdated feed precedes another actual feed. Review the feed history before changing the jar mass.');
    final oldMass=starter.fields['mass'];
    if(oldMass is num && seed>oldMass)throw const FormatException('Seed exceeds the recorded jar amount. Correct the jar amount first.');
    final h=Rational.fromNum(starter.number('hydration',100))/Rational.fromNum(100);
    final exactSeed=Rational.fromNum(seed);
    final seedFlour=exactSeed/(Rational.one+h), seedWater=exactSeed-seedFlour;
    final total=seed+flour+water;
    await db.transaction(() async {
      final feedId=_uuid.v4();
      await _write('feed',{'starterId':starterId,'name':starter.text('name'),'seed':seed,'flour':flour,'water':water,'occurredAt':at.toUtc().toIso8601String(),'total':total},feedId,eventType:'StarterFed',occurredAt:at);
      await _write('starter',{...starter.fields,'mass':total,'hydration':(Rational.fromNum(100)*(seedWater+Rational.fromNum(water))/(seedFlour+Rational.fromNum(flour))).toDouble(),'lastFeedAt':at.toUtc().toIso8601String(),'lastSeed':seed,'lastFlour':flour,'lastWater':water},starterId,eventType:'StarterProjectionUpdated',occurredAt:at);
      if(oldMass is num && oldMass>seed)await _write('discard',{'starterId':starterId,'quantity':oldMass-seed,'createdAt':at.toUtc().toIso8601String(),'storage':'unknown','safetyStatus':'not_assessed'},_uuid.v4(),eventType:'DiscardRecorded',occurredAt:at);
    });
    await load();
    } finally { _feedLocks.remove(starterId); }
  }
  @override Future<AppRecord> createBake(Map<String,dynamic> recipe,{double scale=1,DateTime? serveAt}) async {
    if(_creatingBake)throw StateError('Another plan is being saved. Review its reservations and try again.');
    _creatingBake=true;
    try {
    if(!scale.isFinite||scale<=0||scale>1)throw const FormatException('A larger batch needs explicit oven-load and pan validation. For now, plan separate named batches at the original yield or smaller.');
    final steps=_maps(recipe['steps']);
    if(steps.isEmpty)throw const FormatException('This recipe needs an execution method before baking.');
    final actualCandidate=planRecipe(recipe,records('availability'),records('bake'),{'oven':(preference('ovenCapacity',1) as num).toInt()},serveAt:serveAt);
    final scheduledSteps=steps.map((s){final task=actualCandidate.task(s['id'] as String);return {...s,'plannedStart':task.start.toIso8601String(),'plannedEnd':task.end.toIso8601String()};}).toList();
    final ingredients=_maps(recipe['ingredients']).map((i)=>{...i,'grams':((i['grams']??i['massG']??0) as num)*scale}).toList();
    return await save('bake',{'name':recipe['title']??recipe['name']??'My bake','recipeId':recipe['id'],'recipeVersion':recipe['version']??1,'recipeSnapshot':recipe,'steps':scheduledSteps,'schedule':actualCandidate.toJson(),'ingredients':ingredients,'scale':scale,'stepIndex':0,'status':'planned','state':'planned','startAt':actualCandidate.startsAt.toIso8601String(),'startedAt':null,'serveAt':serveAt?.toUtc().toIso8601String(),'validationStatus':recipe['status']??'experimental','completedSteps':<Map<String,dynamic>>[]});
    } finally { _creatingBake=false; }
  }
  @override Future<void> completeStep(String bakeId,{DateTime? occurredAt,int? expectedIndex}) async {
    if(!_stepLocks.add(bakeId))return;
    try {
      final bake=find(bakeId);if(bake==null||bake.kind!='bake')throw StateError('Bake not found.');
      if(bake.text('status')=='complete')return;
      final steps=_maps(bake.fields['steps']);final index=bake.number('stepIndex').toInt();
      if(expectedIndex!=null&&expectedIndex!=index)throw StateError('This step was already changed. Review the current step.');
      if(index>=steps.length)return;
      final at=occurredAt??DateTime.now();
      if(at.isAfter(DateTime.now().add(const Duration(minutes:5))))throw const FormatException('Completion time cannot be in the future.');
      final completed=_maps(bake.fields['completedSteps']);
      if(completed.isNotEmpty && DateTime.parse(completed.last['occurredAt'] as String).isAfter(at))throw const FormatException('This step cannot finish before the previous recorded step.');
      final finalStep=index+1==steps.length;
      final history=[...completed,{'stepId':steps[index]['id'],'occurredAt':at.toUtc().toIso8601String()}];
      await db.transaction(() async {
        await _write('completion',{'bakeId':bakeId,'stepId':steps[index]['id'],'index':index,'occurredAt':at.toUtc().toIso8601String()},_uuid.v4(),eventType:'StepCompleted',occurredAt:at);
        await _write('bake',{...bake.fields,'startedAt':bake.fields['startedAt']??at.toUtc().toIso8601String(),'completedSteps':history,'stepIndex':index+1,'status':finalStep?'complete':'active','state':finalStep?'complete':'active','completedAt':finalStep?at.toUtc().toIso8601String():null},bakeId,eventType:'BakeProgressed',occurredAt:at);
        if(finalStep)await _write('journal',{'bakeId':bakeId,'name':bake.text('name'),'recipeSnapshot':bake.fields['recipeSnapshot'],'ingredients':bake.fields['ingredients'],'completedSteps':history,'completedAt':at.toUtc().toIso8601String()},_uuid.v4(),eventType:'BakeJournalled',occurredAt:at);
      });await load();
    } finally { _stepLocks.remove(bakeId); }
  }
  Map<String,LocalPhoto> _referencedPhotos(Iterable<Map<String,dynamic>> records) {
    final photos=<String,LocalPhoto>{};
    for(final row in records) {
      final fields=row['fields'];if(fields is! Map)continue;
      final value=fields['photo'];
      if(value==null) {
        if(fields['photoId']!=null)throw const FormatException('Photo identifier has no metadata.');
        continue;
      }
      if(value is! Map)throw const FormatException('Photo metadata must be an object.');
      final photo=LocalPhoto.fromJson(Map<String,dynamic>.from(value));
      if(fields['photoId']!=null&&fields['photoId']!=photo.id)throw const FormatException('Photo identifier does not match its metadata.');
      if(photos.containsKey(photo.id)&&canonicalJson(photos[photo.id]!.toJson())!=canonicalJson(photo.toJson()))throw const FormatException('Conflicting metadata for one photo.');
      photos[photo.id]=photo;
    }
    return photos;
  }
  Map<String,dynamic> _withoutPhotoDigest(Map<String,dynamic> fields) {
    final result=Map<String,dynamic>.from(fields);
    if(result['photo'] is Map) {
      final photo=LocalPhoto.fromJson(Map<String,dynamic>.from(result['photo'] as Map));
      result['photo']=photo.toJson()..remove('sha256');result['photoId']=photo.id;
    }
    return result;
  }
  @override Future<String> exportArchive() async {
    if(_archiveBusy)throw StateError('Another archive operation is running.');
    _archiveBusy=true;
    try {
      final snapshot=await db.transaction(() async {
        final rows=await db.customSelect('SELECT * FROM records WHERE deleted_at IS NULL ORDER BY updated_at,id').get();
        final records=rows.map((r)=>{'id':r.read<String>('id'),'kind':r.read<String>('kind'),'fields':jsonDecode(r.read<String>('fields')),'updatedAt':r.read<String>('updated_at')}).toList();
        final events=await db.customSelect('SELECT * FROM events ORDER BY recorded_at,id').get();
        final preferences=<String,dynamic>{};
        for(final row in await db.customSelect('SELECT * FROM preferences').get()) {
          final key=row.read<String>('key');
          // Installation identity and deletion retry metadata never migrate devices.
          if(key=='syncDeviceId'||key=='pendingMediaDeletion')continue;
          preferences[key]=jsonDecode(row.read<String>('value'));
        }
        return (records:records,events:events.map((r)=>r.data).toList(),preferences:preferences);
      });
      final photos=_referencedPhotos(snapshot.records);
      final mediaArchive=await media.exportSelected(photos.values.toList());
      final archive=const JsonEncoder.withIndent('  ').convert({'format':'crispy-crust-archive','version':1,'exportedAt':DateTime.now().toUtc().toIso8601String(),'records':snapshot.records,'preferences':snapshot.preferences,'events':snapshot.events,'media':mediaArchive});
      if(utf8.encode(archive).length>32*1024*1024)throw const FormatException('Archive exceeds the 32 MB portable archive limit. Reduce selected media or export separately.');
      return archive;
    }finally{_archiveBusy=false;}
  }
  @override Future<void> importArchive(String source) async {
    if(_archiveBusy)throw StateError('Another archive operation is running.');
    _archiveBusy=true;
    final newlyCreated=<LocalPhoto>[];
    var committed=false;
    try {
      if(source.length>32*1024*1024||utf8.encode(source).length>32*1024*1024)throw const FormatException('Archive exceeds the 32 MB text limit.');
      final data=jsonDecode(source);
      if(data is! Map||data['format']!='crispy-crust-archive'||data['version']!=1||data['records'] is! List)throw const FormatException('Unsupported archive.');
      if((data['records'] as List).any((r)=>r is! Map))throw const FormatException('Every archive record must be an object.');
      if(data['events'] is! List||(data['events'] as List).any((r)=>r is! Map))throw const FormatException('Every archive event must be an object.');
      if(data['preferences']!=null&&data['preferences'] is! Map)throw const FormatException('Archive preferences must be an object.');
      final imported=(data['records'] as List).map((r)=>Map<String,dynamic>.from(r as Map)).toList();
      if(imported.length>50000||(data['events'] as List).length>100000)throw const FormatException('Archive contains too many records or events.');
      final ids=<String>{};
      for(final row in imported) {
        if(row['id'] is! String||row['kind'] is! String||row['fields'] is! Map||!ids.add(row['id'] as String))throw const FormatException('Invalid or duplicate archive record.');
        final fields=Map<String,dynamic>.from(row['fields'] as Map);
        _validate(row['kind'] as String,fields);
        final existing=await db.customSelect('SELECT kind,fields FROM records WHERE id=?',variables:[Variable.withString(row['id'] as String)]).getSingleOrNull();
        if(existing!=null&&(existing.read<String>('kind')!=row['kind']||canonicalJson(_withoutPhotoDigest(Map<String,dynamic>.from(jsonDecode(existing.read<String>('fields')) as Map)))!=canonicalJson(_withoutPhotoDigest(fields))))throw StateError('Archive conflicts with existing records. Import into an empty local library or resolve the source first.');
      }
      final sourceEvents=(data['events'] as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
      final eventIds=<String>{};
      for(final event in sourceEvents) {
        for(final key in ['id','aggregate_id','kind','payload','occurred_at','recorded_at']) {if(event[key] is! String)throw const FormatException('Invalid archive event.');}
        if(!eventIds.add(event['id'] as String)||event['base_revision'] is! int||event['base_revision']<0)throw const FormatException('Duplicate event or invalid event revision.');
        if(DateTime.tryParse(event['occurred_at'] as String)==null||DateTime.tryParse(event['recorded_at'] as String)==null)throw const FormatException('Invalid event timestamp.');
        if(event['corrects_id']!=null&&event['corrects_id'] is! String)throw const FormatException('Invalid correction reference.');
        jsonDecode(event['payload'] as String);
        final existing=await db.customSelect('SELECT * FROM events WHERE id=?',variables:[Variable.withString(event['id'] as String)]).getSingleOrNull();
        if(existing!=null) {
          for(final key in ['aggregate_id','kind','occurred_at','recorded_at','base_revision','corrects_id']) {if(existing.data[key]!=event[key])throw StateError('Archive event conflicts with existing audit history.');}
          if(canonicalJson(jsonDecode(existing.read<String>('payload')))!=canonicalJson(jsonDecode(event['payload'] as String)))throw StateError('Archive event conflicts with existing audit history.');
        }
      }
      final referenced=_referencedPhotos(imported);
      final mediaValue=data['media'];
      if(mediaValue!=null&&mediaValue is! Map)throw const FormatException('Archive media must be an object.');
      final mediaManifest=mediaValue==null?<String,dynamic>{'format':'crispy-crust-local-media','version':1,'photos':<dynamic>[]}:Map<String,dynamic>.from(mediaValue as Map);
      if(mediaManifest['photos'] is! List)throw const FormatException('Archive media list is missing.');
      final mediaEntries=mediaManifest['photos'] as List;
      final manifestIds=<String>{};
      for(final entry in mediaEntries) {
        if(entry is! Map||entry['photo'] is! Map)throw const FormatException('Invalid media manifest entry.');
        final photo=LocalPhoto.fromJson(Map<String,dynamic>.from(entry['photo'] as Map));
        if(!manifestIds.add(photo.id)||!referenced.containsKey(photo.id)||canonicalJson(referenced[photo.id]!.toJson())!=canonicalJson(photo.toJson()))throw const FormatException('Archive media does not match selected record photos.');
      }
      if(manifestIds.length!=referenced.length)throw const FormatException('The archive is missing a referenced private photo.');
      final restored=await media.restoreArchive(mediaManifest,onCreated:newlyCreated.add);
      final restoredById={for(final photo in restored)photo.id:photo};
      for(final row in imported) {
        final fields=Map<String,dynamic>.from(row['fields'] as Map);
        if(fields['photo'] is Map) {
          final id=(fields['photo'] as Map)['id'] as String;
          fields['photo']=restoredById[id]!.toJson();fields['photoId']=id;
        }
        row['fields']=fields;
      }
      await db.transaction(() async {
        for(final event in sourceEvents) {
          final existing=await db.customSelect('SELECT * FROM events WHERE id=?',variables:[Variable.withString(event['id'] as String)]).getSingleOrNull();
          if(existing!=null) {
            for(final key in ['aggregate_id','kind','occurred_at','recorded_at','base_revision','corrects_id']) {if(existing.data[key]!=event[key])throw StateError('Audit history changed during import.');}
            if(canonicalJson(jsonDecode(existing.read<String>('payload')))!=canonicalJson(jsonDecode(event['payload'] as String)))throw StateError('Audit history changed during import.');
          } else {
            await db.customStatement('INSERT INTO events (id,aggregate_id,kind,payload,occurred_at,recorded_at,base_revision,corrects_id) VALUES (?,?,?,?,?,?,?,?)',[event['id'],event['aggregate_id'],event['kind'],event['payload'],event['occurred_at'],event['recorded_at'],event['base_revision'],event['corrects_id']]);
          }
        }
        final count=(await db.customSelect('SELECT COUNT(*) AS n FROM records').getSingle()).read<int>('n');
        if(count==0&&data['preferences'] is Map) {
          for(final entry in (data['preferences'] as Map).entries) {
            if(entry.key is! String)throw const FormatException('Invalid preference key.');
            if(entry.key=='syncDeviceId'||entry.key=='pendingMediaDeletion')continue;
            await db.customStatement('INSERT OR REPLACE INTO preferences (key,value) VALUES (?,?)',[entry.key,jsonEncode(entry.value)]);
          }
        }
        for(final row in imported) {
          final existing=await db.customSelect('SELECT kind,fields FROM records WHERE id=?',variables:[Variable.withString(row['id'] as String)]).getSingleOrNull();
          if(existing!=null) {
            if(existing.read<String>('kind')!=row['kind']||canonicalJson(jsonDecode(existing.read<String>('fields')))!=canonicalJson(row['fields']))throw StateError('Records changed during archive import.');
            continue;
          }
          await _write(row['kind'] as String,Map<String,dynamic>.from(row['fields'] as Map),row['id'] as String,eventType:'ArchiveImported');
        }
      });committed=true;await load();
    }on Object catch(error) {
      if(!committed) {
        final cleanupFailures=<String>[];
        for(final photo in newlyCreated) {try{await media.delete(photo);}on Object{cleanupFailures.add(photo.id);}}
        if(cleanupFailures.isNotEmpty)throw StateError('Archive import failed and database changes rolled back. ${cleanupFailures.length} newly restored private photo files could not be cleaned up; original photos were kept. Original error: $error');
      }
      rethrow;
    }finally{_archiveBusy=false;}
  }
  Future<bool> acknowledgeCompanion({required String operationId,required String bakeId,required String stepId,required int expectedRevision}) async {
    final accepted=await db.transaction(()async{
      final prior=await db.customSelect('SELECT id FROM records WHERE id=?',variables:[Variable.withString(operationId)]).getSingleOrNull();
      if(prior!=null)return true;
      final row=await db.customSelect("SELECT * FROM records WHERE id=? AND kind='bake' AND deleted_at IS NULL",variables:[Variable.withString(bakeId)]).getSingleOrNull();
      if(row==null || row.read<int>('revision')!=expectedRevision)return false;
      final fields=jsonDecode(row.read<String>('fields')) as Map;
      final steps=fields['steps'] as List;final index=(fields['stepIndex'] as num).toInt();
      if(index>=steps.length || (steps[index] as Map)['id']!=stepId)return false;
      await _write('acknowledgement',{'bakeId':bakeId,'stepId':stepId,'occurredAt':DateTime.now().toUtc().toIso8601String(),'source':'companion'},operationId,eventType:'CompanionAcknowledged');
      return true;
    });
    if(accepted)await load();return accepted;
  }
  @override Future<void> resetLocalData() async {
    if(_archiveBusy)throw StateError('Another archive operation is running.');
    _archiveBusy=true;
    try {
      final photos=<String,LocalPhoto>{};var malformedPhotos=0;
      final raw=await db.customSelect('SELECT fields FROM records').get();
      for(final row in raw) {
        try{final value=_referencedPhotos([{'fields':jsonDecode(row.read<String>('fields'))}]);for(final entry in value.entries)photos.putIfAbsent(entry.key,()=>entry.value);}
        on Object{malformedPhotos++;}
      }
      for(final row in await db.customSelect('SELECT payload FROM events ORDER BY rowid DESC').get()) {
        try{final payload=jsonDecode(row.read<String>('payload'));if(payload is Map){final value=_referencedPhotos([Map<String,dynamic>.from(payload)]);for(final entry in value.entries)photos.putIfAbsent(entry.key,()=>entry.value);}}
        on Object{malformedPhotos++;}
      }
      final pending=await db.customSelect("SELECT value FROM preferences WHERE key='pendingMediaDeletion'").getSingleOrNull();
      if(pending!=null) {
        try{for(final value in jsonDecode(pending.read<String>('value')) as List){final photo=LocalPhoto.fromJson(Map<String,dynamic>.from(value as Map));photos.putIfAbsent(photo.id,()=>photo);}}
        on Object{malformedPhotos++;}
      }
      await db.transaction(() async {
        for(final table in ['outbox','events','records','preferences','sync_cursors'])await db.customStatement('DELETE FROM $table');
        for(final table in ['sync_conflicts','sync_requests','sync_bindings','sync_remote_audit','sync_namespace']) {
          final exists=await db.customSelect('SELECT name FROM sqlite_master WHERE type=\'table\' AND name=?',variables:[Variable.withString(table)]).getSingleOrNull();
          if(exists!=null)await db.customStatement('DELETE FROM $table');
        }
      });
      final failures=<LocalPhoto>[];
      for(final photo in photos.values) {try{await media.delete(photo);}on Object{failures.add(photo);}}
      if(failures.isNotEmpty)await db.customStatement("INSERT OR REPLACE INTO preferences(key,value) VALUES('pendingMediaDeletion',?)",[jsonEncode(failures.map((p)=>p.toJson()).toList())]);
      await load();
      if(failures.isNotEmpty||malformedPhotos>0)throw StateError('Local records were deleted. ${failures.length} private photo deletions need retry and $malformedPhotos invalid photo references could not be followed. No unverified file paths were deleted.');
    }finally{_archiveBusy=false;}
  }
  @override void dispose(){ db.close();super.dispose(); }
}
