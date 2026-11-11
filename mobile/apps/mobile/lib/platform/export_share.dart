import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'platform_result.dart';

class ExportShareService {
  Future<CapabilityResult<String>> shareTextFile({required String fileName,
      required String content, required String mimeType}) async {
    if (!RegExp(r'^[a-zA-Z0-9_.-]{1,120}$').hasMatch(fileName) || fileName == '.' || fileName == '..') {
      throw ArgumentError('File name must be a plain basename');
    }
    if (kIsWeb) { return const CapabilityResult(CapabilityStatus.unsupported,
      'The consumer app does not provide a web export flow.'); }
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(content, encoding: utf8, flush: true);
    final result = await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: mimeType)],
      title: 'Crispy Crust export', text: 'Your selected Crispy Crust data'));
    return CapabilityResult.available(file.path,
      result.status == ShareResultStatus.dismissed ? 'Export prepared. Sharing was canceled.' : 'Export prepared.');
  }
}
