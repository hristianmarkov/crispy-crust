import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:crispy_crust/data/local_database.dart';
import 'package:crispy_crust/data/local_store.dart';
import 'package:crispy_crust/platform/local_media.dart';

const idA='11111111-1111-4111-8111-111111111111';
const idB='22222222-2222-4222-8222-222222222222';
Uint8List rawPhoto() {
  final image=img.Image(width:64,height:32,numChannels:3);
  img.fill(image,color:img.ColorRgb8(160,90,30));
  image.exif.imageIfd[0x013b]='Private photographer';
  image.exif.imageIfd[0x0112]=6;
  image.exif.gpsIfd[0x0001]='N';
  return img.encodeJpg(image,quality:90);
}
class FailingDeleteMedia extends LocalMediaService {
  FailingDeleteMedia(Directory directory):super(directory:()async=>directory,picker:(_)async=>PickedPhotoBytes(rawPhoto()),clock:()=>DateTime.utc(2026,11,11),newId:()=>idA,runInIsolate:false);
  bool failDeletion=true;
  @override Future<void> delete(LocalPhoto photo) async {
    if(failDeletion)throw const LocalMediaFailure('TEST_PERMISSION_DENIED');
    await super.delete(photo);
  }
}
void main() {
  late Directory dirA,dirB;late LocalDatabase dbA,dbB;late LocalAppStore source,target;
  late LocalMediaService mediaA,mediaB;
  setUp(() async {
    dirA=await Directory.systemTemp.createTemp('crispy-archive-source-');dirB=await Directory.systemTemp.createTemp('crispy-archive-target-');
    var index=0;
    mediaA=LocalMediaService(directory:()async=>dirA,picker:(_)async=>PickedPhotoBytes(rawPhoto()),clock:()=>DateTime.utc(2026,11,11),newId:()=>index++==0?idA:idB,runInIsolate:false);
    mediaB=LocalMediaService(directory:()async=>dirB,picker:(_)async=>PickedPhotoBytes(rawPhoto()),clock:()=>DateTime.utc(2026,11,11),newId:()=>idA,runInIsolate:false);
    dbA=LocalDatabase.memory();dbB=LocalDatabase.memory();source=LocalAppStore(dbA,{},media:mediaA);target=LocalAppStore(dbB,{},media:mediaB);await source.load();await target.load();
  });
  tearDown(() async {await dbA.close();await dbB.close();await dirA.delete(recursive:true);await dirB.delete(recursive:true);});
  Future<LocalPhoto> addPhoto() async {
    final photo=(await mediaA.pickPhoto())!;
    await source.save('observation',{'objectId':'jar','note':'Keep this note','temperature':'23','occurredAt':'2026-11-10T17:00:00Z','photoId':photo.id,'photo':photo.toJson()});return photo;
  }
  test('two-database portable archive restores notes audit preferences and private pixels',() async {
    final original=await addPhoto();await source.setPreference('darkMode',true);await source.setPreference('syncDeviceId','source-installation');
    final archive=await source.exportArchive();final decoded=jsonDecode(archive) as Map;
    expect((decoded['media']['photos'] as List).length,1);expect((decoded['preferences'] as Map).containsKey('syncDeviceId'),isFalse);
    await target.importArchive(archive);
    final observation=target.records('observation').single;
    expect(observation.text('note'),'Keep this note');expect(observation.text('occurredAt'),'2026-11-10T17:00:00Z');
    final restored=LocalPhoto.fromJson(Map<String,dynamic>.from(observation.fields['photo'] as Map));
    expect(restored.id,original.id);expect(restored.width,32);expect(restored.height,64);expect(restored.capturedAt,original.capturedAt);
    final bytes=await(await mediaB.resolve(restored)).readAsBytes();expect(sha256.convert(bytes).toString(),restored.sha256);
    final image=img.decodeJpg(bytes)!;expect(image.width,32);expect(image.height,64);expect((image.getPixel(5,5).r-160).abs(),lessThan(5));
    final exif=img.decodeJpgExif(bytes);expect(exif==null||exif.gpsIfd.isEmpty,isTrue);expect(exif==null||exif.imageIfd[0x013b]==null,isTrue);
    expect(target.darkMode,isTrue);expect(target.preference('syncDeviceId'),isNull);
    expect((await dbB.customSelect('SELECT * FROM events').get()).length,greaterThanOrEqualTo(2));
    await target.importArchive(archive);expect(target.records('observation').length,1);expect(await(await mediaB.resolve(restored)).exists(),isTrue);
  });
  test('malformed media archive changes no records events or target files',() async {
    await addPhoto();final archive=jsonDecode(await source.exportArchive()) as Map<String,dynamic>;
    ((archive['media']['photos'] as List).single as Map)['bytesBase64']=base64Encode([1,2,3]);
    await target.save('starter',{'name':'Keep me'});
    await expectLater(target.importArchive(jsonEncode(archive)),throwsA(isA<LocalMediaFailure>()));
    expect(target.records('starter').single.text('name'),'Keep me');expect(target.records('observation'),isEmpty);
    expect((await dbB.customSelect('SELECT * FROM events').get()).length,1);expect(await dirB.list(recursive:true).toList(),isEmpty);
  });
  test('database failure removes only newly restored photos, preserving existing originals',() async {
    await addPhoto();await addPhoto();final archive=await source.exportArchive();
    final existing=(await mediaB.pickPhoto())!;
    await target.save('starter',{'name':'Original target record'});
    await dbB.customStatement("CREATE TRIGGER fail_import BEFORE INSERT ON records WHEN NEW.kind='observation' BEGIN SELECT RAISE(ABORT,'injected import failure'); END");
    await expectLater(target.importArchive(archive),throwsA(anything));
    expect(await(await mediaB.resolve(existing)).exists(),isTrue);
    final files=await dirB.list(recursive:true).where((v)=>v is File).toList();expect(files.length,1);
    expect(target.records('starter').length,1);expect(target.records('observation'),isEmpty);
    expect((await dbB.customSelect('SELECT * FROM events').get()).length,1);
  });
  test('malformed record and conflicting event fail before media writes',() async {
    await addPhoto();final data=jsonDecode(await source.exportArchive()) as Map<String,dynamic>;
    final malformed=jsonDecode(jsonEncode(data)) as Map<String,dynamic>;(malformed['records'] as List).add('not an object');
    await expectLater(target.importArchive(jsonEncode(malformed)),throwsFormatException);expect(await dirB.list(recursive:true).toList(),isEmpty);
    final event=(data['events'] as List).first as Map;
    await dbB.customStatement('INSERT INTO events(id,aggregate_id,kind,payload,occurred_at,recorded_at,base_revision) VALUES(?,?,?,?,?,?,?)',[event['id'],event['aggregate_id'],event['kind'],'{}',event['occurred_at'],event['recorded_at'],event['base_revision']]);
    await expectLater(target.importArchive(jsonEncode(data)),throwsStateError);expect(await dirB.list(recursive:true).toList(),isEmpty);
  });
  test('reset clears records then deletes only referenced owned photos',() async {
    final photo=await addPhoto();final file=await mediaA.resolve(photo);
    final unrelated=File('${dirA.path}/keep.txt');await unrelated.writeAsString('unrelated');
    await source.resetLocalData();expect(source.records('observation'),isEmpty);expect(await file.exists(),isFalse);expect(await unrelated.readAsString(),'unrelated');
    expect(await dbA.customSelect('SELECT * FROM events').get(),isEmpty);
  });
  test('partial file cleanup reports committed record deletion and retains retry metadata',() async {
    final failing=FailingDeleteMedia(dirA);final store=LocalAppStore(dbA,{},media:failing);await store.load();
    final photo=(await failing.pickPhoto())!;await store.save('observation',{'photoId':photo.id,'photo':photo.toJson(),'note':'Private note'});
    await expectLater(store.resetLocalData(),throwsA(isA<StateError>().having((e)=>e.message.toString(),'message',contains('Local records were deleted'))));
    expect(store.records('observation'),isEmpty);expect(store.preference('pendingMediaDeletion'),isA<List>());expect(await(await failing.resolve(photo)).exists(),isTrue);
    failing.failDeletion=false;await store.resetLocalData();expect(await dbA.customSelect("SELECT * FROM preferences WHERE key='pendingMediaDeletion'").get(),isEmpty);
    await expectLater(failing.resolve(photo),throwsA(isA<LocalMediaFailure>()));
  });
}
