import 'dart:io';
import 'package:content_models/content_models.dart';

void main(List<String> args) {
  final publication=args.contains('--publication');
  final files=args.where((v)=>!v.startsWith('--')).toList();
  final path=files.isEmpty?'../../content/catalogue.json':files.single;
  try {
    final catalogue=ContentCatalogue.decode(File(path).readAsStringSync());
    final issues=const ContentValidator().validate(catalogue,forPublication:publication);
    for(final issue in issues) { stdout.writeln(issue); }
    final errors=issues.where((v)=>v.severity==IssueSeverity.error).length;
    stdout.writeln('${catalogue.recipes.length} recipes, ${catalogue.lessons.length} lessons, $errors errors. Kitchen approval is not implied.');
    if(errors>0) exitCode=1;
  } on Object catch(error) {
    stderr.writeln('Content validation failed: $error');exitCode=1;
  }
}
