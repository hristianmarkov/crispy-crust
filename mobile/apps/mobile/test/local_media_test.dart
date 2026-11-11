import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:crispy_crust/platform/local_media.dart';

const photoId='11111111-1111-4111-8111-111111111111';
Uint8List pixels({int width=64,int height=32,bool metadata=false}) {
  final image=img.Image(width:width,height:height,numChannels:3);
  img.fill(image,color:img.ColorRgb8(160,90,30));
  if(metadata) {
    image.exif.imageIfd[0x013b]='Private photographer';
    image.exif.gpsIfd[0x0001]='N';
    image.exif.gpsIfd[0x001D]='2026:11:11';
  }
  return img.encodeJpg(image,quality:90);
}
void main() {
  late Directory root;
  setUp(() async{root=await Directory.systemTemp.createTemp('crispy-media-test-');});
  tearDown(() async{if(await root.exists())await root.delete(recursive:true);});
  LocalMediaService service(Uint8List bytes,{String id=photoId})=>LocalMediaService(directory:()async=>root,picker:(camera)async=>PickedPhotoBytes(bytes,sourceModifiedAt:DateTime.utc(2026,10,1)),clock:()=>DateTime.utc(2026,11,11,12),newId:()=>id,runInIsolate:false);
  test('cancel does not create media files or infer an observation',() async {
    var called=false;
    final media=LocalMediaService(directory:()async{called=true;return root;},picker:(camera)async=>null,runInIsolate:false);
    expect(await media.pickPhoto(),isNull);expect(called,isFalse);expect(await root.list().toList(),isEmpty);
  });
  test('selected pixels saved privately with separate import/source times',() async {
    final media=service(pixels());final photo=(await media.pickPhoto())!;
    expect(photo.relativePath,'photos/$photoId.jpg');expect(photo.capturedAt,DateTime.utc(2026,11,11,12));expect(photo.sourceModifiedAt,DateTime.utc(2026,10,1));
    final file=await media.resolve(photo);expect(file.path.startsWith(root.path),isTrue);
    expect(sha256.convert(await file.readAsBytes()).toString(),photo.sha256);
    expect(LocalPhoto.fromJson(photo.toJson()).id,photo.id);
  });
  test('long side capped at1600 preserving aspect ratio',() async {
    final media=service(pixels(width:2000,height:1000));final photo=(await media.pickPhoto())!;
    expect(photo.width,1600);expect(photo.height,800);
    final decoded=img.decodeJpg(await(await media.resolve(photo)).readAsBytes())!;expect(decoded.width,1600);
  });
  test('new RGB JPEG removes photographer and GPS EXIF',() async {
    final bytes=pixels(metadata:true);expect(img.decodeJpgExif(bytes)!.imageIfd[0x013b],isNotNull);
    final media=service(bytes);final photo=(await media.pickPhoto())!;
    final exif=img.decodeJpgExif(await(await media.resolve(photo)).readAsBytes());
    expect(exif==null||exif.imageIfd[0x013b]==null,isTrue);
    expect(exif==null||exif.gpsIfd.isEmpty,isTrue);
  });
  test('corrupt input and forged metadata cannot become app file paths',() async {
    await expectLater(service(Uint8List.fromList([1,2,3])).pickPhoto(),throwsA(isA<LocalMediaFailure>()));
    expect(()=>LocalPhoto.fromJson({'id':photoId,'relativePath':'../secret.jpg','width':1,'height':1,'sha256':List.filled(64,'0').join(),'capturedAt':'2026-11-11T12:00:00Z'}),throwsA(isA<LocalMediaFailure>()));
    expect(await root.list().toList(),isEmpty);
  });
  test('changed file fails hash check and cannot be deleted under stale metadata',() async {
    final media=service(pixels());final photo=(await media.pickPhoto())!;final file=await media.resolve(photo);
    await file.writeAsBytes([1,2,3]);
    await expectLater(media.resolve(photo),throwsA(isA<LocalMediaFailure>().having((e)=>e.code,'code','PHOTO_HASH_MISMATCH')));
    await expectLater(media.delete(photo),throwsA(isA<LocalMediaFailure>()));expect(await file.exists(),isTrue);
  });
  test('portable archive restores to fresh directory and repeats safely',() async {
    final media=service(pixels(metadata:true));final photo=(await media.pickPhoto())!;
    final archive=await media.exportSelected([photo]);
    final other=await Directory.systemTemp.createTemp('crispy-media-restore-');
    try {
      final restoredService=LocalMediaService(directory:()async=>other,runInIsolate:false);
      final restored=await restoredService.restoreArchive(archive);expect(restored.single.id,photo.id);
      expect(await(await restoredService.resolve(restored.single)).exists(),isTrue);
      final again=await restoredService.restoreArchive(archive);expect(again.single.sha256,restored.single.sha256);
    }finally{await other.delete(recursive:true);}
  });
  test('entire archive validated before any entry is written',() async {
    final media=service(pixels());final photo=(await media.pickPhoto())!;
    final archive=await media.exportSelected([photo]);final entry=(archive['photos'] as List).single as Map;
    final bad=jsonDecode(jsonEncode(entry)) as Map<String,dynamic>;bad['photo']['id']='22222222-2222-4222-8222-222222222222';bad['photo']['relativePath']='photos/22222222-2222-4222-8222-222222222222.jpg';bad['bytesBase64']=base64Encode([1,2,3]);
    final other=await Directory.systemTemp.createTemp('crispy-media-bad-');
    try {
      final restore=LocalMediaService(directory:()async=>other,runInIsolate:false);
      await expectLater(restore.restoreArchive({...archive,'photos':[entry,bad]}),throwsA(isA<LocalMediaFailure>()));
      expect(await other.list(recursive:true).toList(),isEmpty);
    }finally{await other.delete(recursive:true);}
  });
  test('duplicate IDs and oversized input fail before writing',() async {
    await expectLater(service(Uint8List(20*1024*1024+1)).pickPhoto(),throwsA(isA<LocalMediaFailure>()));
    final media=service(pixels());final photo=(await media.pickPhoto())!;
    await expectLater(media.exportSelected([photo,photo]),throwsA(isA<LocalMediaFailure>()));
    await media.delete(photo);await media.delete(photo);
    await expectLater(media.resolve(photo),throwsA(isA<LocalMediaFailure>().having((e)=>e.code,'code','PHOTO_NOT_FOUND')));
  });
}
