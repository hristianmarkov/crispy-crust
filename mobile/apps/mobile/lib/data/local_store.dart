import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:baking_domain/baking_domain.dart';
import 'app_store.dart';
import 'local_database.dart';
import 'planning_adapter.dart';

class LocalAppStore extends AppStore {
  LocalAppStore(this.db, Map<String, dynamic> catalogue)
      : recipes = _maps(catalogue['recipes']),
        lessons = _maps(catalogue['lessons']),
        guidance = _maps(catalogue['guidance']);
  final LocalDatabase db;
  final _uuid = const Uuid();
  final Map<String, AppRecord> _records = {};
  final Map<String, dynamic> _preferences = {};
  final Set<String> _stepLocks = {};
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
      _records[r.read<String>('id')] = AppRecord(id: r.read<String>('id'), kind: r.read<String>('kind'), fields: Map<String,dynamic>.from(jsonDecode(r.read<String>('fields')) as Map), updatedAt: DateTime.parse(r.read<String>('updated_at')));
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
  }
  @override Future<AppRecord> createBake(Map<String,dynamic> recipe,{double scale=1,DateTime? serveAt}) async {
    if(!scale.isFinite||scale<=0||scale>1)throw const FormatException('A larger batch needs explicit oven-load and pan validation. For now, plan separate named batches at the original yield or smaller.');
    final steps=_maps(recipe['steps']);
    if(steps.isEmpty)throw const FormatException('This recipe needs an execution method before baking.');
    final actualCandidate=planRecipe(recipe,records('availability'),records('bake'),{'oven':(preference('ovenCapacity',1) as num).toInt()},serveAt:serveAt);
    final scheduledSteps=steps.map((s){final task=actualCandidate.task(s['id'] as String);return {...s,'plannedStart':task.start.toIso8601String(),'plannedEnd':task.end.toIso8601String()};}).toList();
    final ingredients=_maps(recipe['ingredients']).map((i)=>{...i,'grams':((i['grams']??i['massG']??0) as num)*scale}).toList();
    return save('bake',{'name':recipe['title']??recipe['name']??'My bake','recipeId':recipe['id'],'recipeVersion':recipe['version']??1,'recipeSnapshot':recipe,'steps':scheduledSteps,'schedule':actualCandidate.toJson(),'ingredients':ingredients,'scale':scale,'stepIndex':0,'status':'planned','state':'planned','startAt':actualCandidate.startsAt.toIso8601String(),'startedAt':null,'serveAt':serveAt?.toUtc().toIso8601String(),'validationStatus':recipe['status']??'experimental','completedSteps':<Map<String,dynamic>>[]});
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
  @override Future<String> exportArchive() async {
    final events=await db.customSelect('SELECT * FROM events ORDER BY recorded_at,id').get();
    return const JsonEncoder.withIndent('  ').convert({'format':'crispy-crust-archive','version':1,'exportedAt':DateTime.now().toUtc().toIso8601String(),'records':_records.values.map((r)=>{'id':r.id,'kind':r.kind,'fields':r.fields,'updatedAt':r.updatedAt.toIso8601String()}).toList(),'preferences':_preferences,'events':events.map((r)=>r.data).toList()});
  }
  @override Future<void> importArchive(String source) async {
    if(source.length>20*1024*1024)throw const FormatException('Archive exceeds the 20 MB text limit.');
    final data=jsonDecode(source);
    if(data is! Map || data['format']!='crispy-crust-archive'||data['version']!=1||data['records'] is! List)throw const FormatException('Unsupported archive.');
    final imported=_maps(data['records']);
    if(imported.length>50000)throw const FormatException('Archive contains too many records.');
    final ids=<String>{};
    for(final row in imported) {
      if(row['id'] is! String || row['kind'] is! String || row['fields'] is! Map || !ids.add(row['id'] as String))throw const FormatException('Invalid or duplicate archive record.');
      _validate(row['kind'] as String,Map<String,dynamic>.from(row['fields'] as Map));
      final existing=find(row['id'] as String);
      if(existing!=null && jsonEncode(existing.fields)!=jsonEncode(row['fields']))throw StateError('Archive conflicts with existing records. Import into an empty local library or resolve the source first.');
    }
    final sourceEvents=_maps(data['events']);
    for(final event in sourceEvents) {
      for(final key in ['id','aggregate_id','kind','payload','occurred_at','recorded_at']) {if(event[key] is! String)throw const FormatException('Invalid archive event.');}
      if(event['base_revision'] is! int)throw const FormatException('Invalid event revision.');
      jsonDecode(event['payload'] as String);
    }
    await db.transaction(() async {
      for(final event in sourceEvents) {
        await db.customStatement('INSERT OR IGNORE INTO events (id,aggregate_id,kind,payload,occurred_at,recorded_at,base_revision,corrects_id) VALUES (?,?,?,?,?,?,?,?)',[event['id'],event['aggregate_id'],event['kind'],event['payload'],event['occurred_at'],event['recorded_at'],event['base_revision'],event['corrects_id']]);
      }
      if(_records.isEmpty && data['preferences'] is Map) {
        for(final entry in (data['preferences'] as Map).entries)await db.customStatement('INSERT OR REPLACE INTO preferences (key,value) VALUES (?,?)',[entry.key.toString(),jsonEncode(entry.value)]);
      }
      for(final row in imported) {
        if(find(row['id'] as String)!=null)continue;
        await _write(row['kind'] as String,Map<String,dynamic>.from(row['fields'] as Map),row['id'] as String,eventType:'ArchiveImported');
      }
    });await load();
  }
  @override Future<void> resetLocalData() async {
    await db.transaction(() async {
      for(final table in ['outbox','events','records','preferences','sync_cursors'])await db.customStatement('DELETE FROM $table');
    });await load();
  }
  @override void dispose(){ db.close();super.dispose(); }
}
