import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class LocalMediaFailure implements Exception {
  const LocalMediaFailure(this.code);
  final String code;
  @override String toString()=>code;
}
class PickedPhotoBytes {
  const PickedPhotoBytes(this.bytes,{this.sourceModifiedAt});
  final Uint8List bytes;
  /// File modification metadata, never represented as actual photo-taken time.
  final DateTime? sourceModifiedAt;
}
class LocalPhoto {
  const LocalPhoto({required this.id,required this.relativePath,required this.width,
    required this.height,required this.sha256,required this.capturedAt,this.sourceModifiedAt});
  factory LocalPhoto.fromJson(Map<String,dynamic> json) {
    final id=json['id'],path=json['relativePath'],width=json['width'],height=json['height'],hash=json['sha256'];
    final at=DateTime.tryParse(json['capturedAt']?.toString()??'');
    final source=json['sourceModifiedAt'];
    if(id is! String||!_validId(id)||path!='photos/$id.jpg'||width is! int||height is! int||width<1||height<1||width>1600||height>1600||hash is! String||!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)||at==null||(source!=null&&DateTime.tryParse(source.toString())==null)){ throw const LocalMediaFailure('INVALID_PHOTO_METADATA'); }
    return LocalPhoto(id:id,relativePath:path as String,width:width,height:height,sha256:hash,capturedAt:at.toUtc(),sourceModifiedAt:source==null?null:DateTime.parse(source.toString()).toUtc());
  }
  final String id,relativePath,sha256;
  final int width,height;
  /// Time this explicit capture/import operation was accepted by the app.
  /// It is not inferred from camera EXIF and is separate from an observation time.
  final DateTime capturedAt;
  final DateTime? sourceModifiedAt;
  Map<String,dynamic> toJson()=>{'id':id,'relativePath':relativePath,'width':width,'height':height,'sha256':sha256,'capturedAt':capturedAt.toUtc().toIso8601String(),'sourceModifiedAt':sourceModifiedAt?.toUtc().toIso8601String()};
}
bool _validId(String id)=>RegExp(r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$').hasMatch(id);
class _Sanitised {
  const _Sanitised(this.bytes,this.width,this.height);
  final Uint8List bytes;
  final int width,height;
}
_Sanitised _sanitise(Uint8List bytes) {
  if(bytes.isEmpty||bytes.length>20*1024*1024){ throw const LocalMediaFailure('PHOTO_INPUT_TOO_LARGE'); }
  final decoder=img.findDecoderForData(bytes);
  final info=decoder?.startDecode(bytes);
  if(info==null||info.width<1||info.height<1||info.width*info.height>24000000){ throw const LocalMediaFailure('PHOTO_FORMAT_OR_DIMENSIONS_UNSUPPORTED'); }
  final decoded=decoder!.decodeFrame(0);
  if(decoded==null){ throw const LocalMediaFailure('PHOTO_DECODE_FAILED'); }
  var pixels=img.bakeOrientation(decoded);
  if(pixels.width>1600||pixels.height>1600) {
    pixels=img.copyResize(pixels,width:pixels.width>=pixels.height?1600:null,height:pixels.height>pixels.width?1600:null,interpolation:img.Interpolation.average);
  }
  // Never copy source EXIF, GPS, comments, ICC profiles or named metadata.
  // A fresh RGB canvas receives only pixel values, after orientation is baked.
  final clean=img.Image(width:pixels.width,height:pixels.height,numChannels:3);
  final normal=pixels.convert(format:img.Format.uint8,numChannels:4);
  for(final pixel in normal) {
    final alpha=pixel.a/255;
    clean.setPixelRgb(pixel.x,pixel.y,(pixel.r*alpha+255*(1-alpha)).round(),(pixel.g*alpha+255*(1-alpha)).round(),(pixel.b*alpha+255*(1-alpha)).round());
  }
  var encoded=img.encodeJpg(clean,quality:82);
  if(encoded.length>4*1024*1024)encoded=img.encodeJpg(clean,quality:60);
  if(encoded.length>4*1024*1024){ throw const LocalMediaFailure('PHOTO_OUTPUT_TOO_LARGE'); }
  return _Sanitised(encoded,clean.width,clean.height);
}

/// Private device files only. No network, cloud-upload queue or photo analysis.
/// Construction does not prompt for permissions; only pickPhoto invokes picker.
class LocalMediaService {
  LocalMediaService({Future<Directory> Function()? directory,
    Future<PickedPhotoBytes?> Function(bool camera)? picker,
    DateTime Function()? clock,String Function()? newId,bool runInIsolate=true})
      : _directory=directory??_defaultDirectory,_picker=picker??_defaultPicker,
        _clock=clock??DateTime.now,_newId=newId??const Uuid().v4,
        _runInIsolate=runInIsolate;
  final Future<Directory> Function() _directory;
  final Future<PickedPhotoBytes?> Function(bool) _picker;
  final DateTime Function() _clock;
  final String Function() _newId;
  final bool _runInIsolate;
  static final Set<String> _writingPaths=<String>{};
  static Future<Directory> _defaultDirectory() async=>Directory(p.join((await getApplicationDocumentsDirectory()).path,'crispy_crust_media'));
  static Future<PickedPhotoBytes?> _defaultPicker(bool camera) async {
    final file=await ImagePicker().pickImage(source:camera?ImageSource.camera:ImageSource.gallery,requestFullMetadata:false,maxWidth:2000,maxHeight:2000);
    if(file==null){ return null; }
    if(await file.length()>20*1024*1024){ throw const LocalMediaFailure('PHOTO_INPUT_TOO_LARGE'); }
    return PickedPhotoBytes(await file.readAsBytes(),sourceModifiedAt:await file.lastModified());
  }
  Future<_Sanitised> _process(Uint8List bytes)=>_runInIsolate?compute(_sanitise,bytes):Future.value(_sanitise(bytes));
  Future<Directory> _root() async {
    final root=await _directory();await root.create(recursive:true);
    return Directory(await root.resolveSymbolicLinks());
  }
  Future<File> _file(LocalPhoto photo) async {
    LocalPhoto.fromJson(photo.toJson());
    final root=await _root();final file=File(p.join(root.path,photo.relativePath));
    if(!p.isWithin(root.path,file.path)){ throw const LocalMediaFailure('PHOTO_PATH_REJECTED'); }
    final parent=Directory(p.dirname(file.path));
    final type=await FileSystemEntity.type(parent.path,followLinks:false);
    if(type==FileSystemEntityType.link){ throw const LocalMediaFailure('PHOTO_PATH_REJECTED'); }
    await parent.create(recursive:true);
    if(await FileSystemEntity.type(file.path,followLinks:false)==FileSystemEntityType.link){ throw const LocalMediaFailure('PHOTO_PATH_REJECTED'); }
    return file;
  }
  Future<LocalPhoto?> pickPhoto({bool camera=false}) async {
    final picked=await _picker(camera);if(picked==null){ return null; }
    final safe=await _process(picked.bytes);final id=_newId();
    if(!_validId(id)){ throw const LocalMediaFailure('INVALID_GENERATED_PHOTO_ID'); }
    final photo=LocalPhoto(id:id,relativePath:'photos/$id.jpg',width:safe.width,height:safe.height,sha256:sha256.convert(safe.bytes).toString(),capturedAt:_clock().toUtc(),sourceModifiedAt:picked.sourceModifiedAt?.toUtc());
    final file=await _file(photo);
    if(await file.exists()){ throw const LocalMediaFailure('PHOTO_ID_COLLISION'); }
    await _atomicWrite(file,safe.bytes);return photo;
  }
  Future<void> _atomicWrite(File file,Uint8List bytes) async {
    if(!_writingPaths.add(file.path)){ throw const LocalMediaFailure('PHOTO_ID_COLLISION'); }
    final temp=File('${file.path}.${const Uuid().v4()}.part');
    try{
      if(await file.exists()){ throw const LocalMediaFailure('PHOTO_ID_COLLISION'); }
      await temp.writeAsBytes(bytes,flush:true);await temp.rename(file.path);
    }finally{_writingPaths.remove(file.path);if(await temp.exists()){ await temp.delete(); }}
  }
  Future<File> resolve(LocalPhoto photo) async {
    final file=await _file(photo);
    if(!await file.exists()){ throw const LocalMediaFailure('PHOTO_NOT_FOUND'); }
    final length=await file.length();if(length<1||length>4*1024*1024){ throw const LocalMediaFailure('PHOTO_SIZE_INVALID'); }
    final bytes=await file.readAsBytes();
    if(sha256.convert(bytes).toString()!=photo.sha256){ throw const LocalMediaFailure('PHOTO_HASH_MISMATCH'); }
    final info=img.findDecoderForData(bytes)?.startDecode(bytes);
    if(info==null||info.width!=photo.width||info.height!=photo.height){ throw const LocalMediaFailure('PHOTO_DIMENSIONS_MISMATCH'); }
    return file;
  }
  Future<void> delete(LocalPhoto photo) async {
    final file=await _file(photo);
    if(!await file.exists()){ return; }
    await resolve(photo);await file.delete();
  }
  Future<Map<String,dynamic>> exportSelected(List<LocalPhoto> photos) async {
    if(photos.length>50){ throw const LocalMediaFailure('MEDIA_ARCHIVE_TOO_LARGE'); }
    final ids=<String>{};final entries=<Map<String,dynamic>>[];var bytes=0;
    for(final photo in photos) {
      if(!ids.add(photo.id)){ throw const LocalMediaFailure('DUPLICATE_PHOTO_ID'); }
      final file=await resolve(photo);final data=await file.readAsBytes();bytes+=data.length;
      if(bytes>20*1024*1024){ throw const LocalMediaFailure('MEDIA_ARCHIVE_TOO_LARGE'); }
      entries.add({'photo':photo.toJson(),'bytesBase64':base64Encode(data)});
    }
    return {'format':'crispy-crust-local-media','version':1,'photos':entries};
  }
  /// Validate the entire archive before writing. Restored input is sanitised
  /// again, so returned hashes can change. Callers must replace record metadata
  /// using the returned id→photo mapping before exposing restored observations.
  /// Existing identical IDs are retained; conflicting IDs never overwrite files.
  Future<List<LocalPhoto>> restoreArchive(Map<String,dynamic> manifest,{void Function(LocalPhoto photo)? onCreated}) async {
    if(manifest['format']!='crispy-crust-local-media'||manifest['version']!=1||manifest['photos'] is! List){ throw const LocalMediaFailure('MEDIA_ARCHIVE_UNSUPPORTED'); }
    final raw=manifest['photos'] as List;if(raw.length>50){ throw const LocalMediaFailure('MEDIA_ARCHIVE_TOO_LARGE'); }
    final ids=<String>{};var bytes=0;
    final checked=<({LocalPhoto photo,_Sanitised safe,Uint8List original})>[];
    for(final entry in raw) {
      if(entry is! Map||entry['photo'] is! Map||entry['bytesBase64'] is! String){ throw const LocalMediaFailure('MEDIA_ARCHIVE_INVALID'); }
      final photo=LocalPhoto.fromJson(Map<String,dynamic>.from(entry['photo'] as Map));
      if(!ids.add(photo.id)){ throw const LocalMediaFailure('DUPLICATE_PHOTO_ID'); }
      final encoded=entry['bytesBase64'] as String;
      if(encoded.length>6*1024*1024){ throw const LocalMediaFailure('MEDIA_ARCHIVE_TOO_LARGE'); }
      Uint8List data;try{data=base64Decode(encoded);}on FormatException{throw const LocalMediaFailure('MEDIA_BASE64_INVALID');}
      bytes+=data.length;if(bytes>20*1024*1024||data.length>4*1024*1024){ throw const LocalMediaFailure('MEDIA_ARCHIVE_TOO_LARGE'); }
      if(sha256.convert(data).toString()!=photo.sha256){ throw const LocalMediaFailure('PHOTO_HASH_MISMATCH'); }
      final safe=await _process(data);
      if(safe.width!=photo.width||safe.height!=photo.height){ throw const LocalMediaFailure('PHOTO_DIMENSIONS_MISMATCH'); }
      checked.add((photo:photo,safe:safe,original:data));
    }
    final plans=<({LocalPhoto photo,File file,Uint8List bytes,bool exists})>[];
    for(final item in checked) {
      final file=await _file(item.photo);final exists=await file.exists();
      if(exists) {
        if(await file.length()>4*1024*1024){ throw const LocalMediaFailure('PHOTO_ID_COLLISION'); }
        final existingHash=sha256.convert(await file.readAsBytes()).toString();
        final normalisedHash=sha256.convert(item.safe.bytes).toString();
        if(existingHash!=item.photo.sha256&&existingHash!=normalisedHash){ throw const LocalMediaFailure('PHOTO_ID_COLLISION'); }
        final existing=LocalPhoto(id:item.photo.id,relativePath:item.photo.relativePath,width:item.photo.width,height:item.photo.height,sha256:existingHash,capturedAt:item.photo.capturedAt,sourceModifiedAt:item.photo.sourceModifiedAt);
        plans.add((photo:existing,file:file,bytes:item.original,exists:true));
      } else {
        final restored=LocalPhoto(id:item.photo.id,relativePath:item.photo.relativePath,width:item.safe.width,height:item.safe.height,sha256:sha256.convert(item.safe.bytes).toString(),capturedAt:item.photo.capturedAt,sourceModifiedAt:item.photo.sourceModifiedAt);
        plans.add((photo:restored,file:file,bytes:item.safe.bytes,exists:false));
      }
    }
    final created=<File>[];
    try {
      for(final plan in plans) {if(!plan.exists){await _atomicWrite(plan.file,plan.bytes);created.add(plan.file);onCreated?.call(plan.photo);}}
    }on Object {for(final file in created){if(await file.exists()){ await file.delete(); }}rethrow;}
    return plans.map((v)=>v.photo).toList(growable:false);
  }
}
