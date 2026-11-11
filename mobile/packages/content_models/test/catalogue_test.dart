import 'dart:convert';
import 'dart:io';
import 'package:content_models/content_models.dart';
import 'package:test/test.dart';

Map<String,dynamic> fixture()=>jsonDecode(File('../../content/catalogue.json').readAsStringSync()) as Map<String,dynamic>;
List<String> errors(Map<String,dynamic> json)=>const ContentValidator()
    .validate(ContentCatalogue.fromJson(json))
    .where((i)=>i.severity==IssueSeverity.error).map((i)=>i.code).toList();

void main() {
  test('all commissioned recipes and lessons parse and conserve physical mass',() {
    final catalogue=ContentCatalogue.fromJson(fixture());
    expect(catalogue.recipes.length,24);
    expect(catalogue.lessons.length,18);
    expect(errors(fixture()),isEmpty);
    expect(catalogue.recipeById('R01')!.hydrationPercent,65);
    expect(catalogue.recipeById('R02')!.doughMassGrams,860);
    expect(catalogue.recipeById('R06')!.totalWaterGrams,375);
  });
  test('none of the drafts can bypass kitchen-validation publication gate',() {
    final catalogue=ContentCatalogue.fromJson(fixture());
    expect(catalogue.recipes.every((r)=>r.experimental && !r.kitchenValidated && r.requiresExplicitAcceptance),isTrue);
    expect(catalogue.recipes.any((r)=>r.canRunAutomatically),isFalse);
    final issues=const ContentValidator().validate(catalogue,forPublication:true);
    expect(issues.where((i)=>i.code=='NOT_PUBLICATION_READY').length,24);
    expect(issues.where((i)=>i.code=='DEMONSTRATION_PENDING').length,18);
    expect(issues.where((i)=>i.code=='GUIDANCE_REVIEW_PENDING').length,2);
  });
  test('starter flour/water counted once; accidental double-count is rejected',() {
    final json=fixture();
    json['recipes'][0]['totalFlourGrams']=550;
    expect(errors(json),contains('FLOUR_TOTAL_MISMATCH'));
  });
  test('invalid physical mass and hidden allergens are rejected',() {
    final json=fixture();
    json['recipes'][0]['ingredients'][0]['grams']=-5;
    json['recipes'][0]['allergens']=<String>[];
    expect(errors(json),containsAll(['MASS_INVALID','MASS_TOTAL_MISMATCH','ALLERGEN_MISMATCH']));
  });
  test('cycle and missing stage/ingredient/lesson references are rejected',() {
    final json=fixture();
    json['recipes'][0]['steps'][0]['after']=['cool'];
    json['recipes'][0]['steps'][1]['ingredientIds']=['missing'];
    json['recipes'][0]['steps'][1]['lessonId']='missing';
    expect(errors(json),containsAll(['GRAPH_CYCLE','INGREDIENT_REFERENCE_MISSING','LESSON_MISSING']));
  });
  test('falsely approved content needs an actual reviewer and test records',() {
    final json=fixture();
    json['recipes'][0]['kitchenValidated']=true;
    json['recipes'][0]['status']='published';
    expect(errors(json),containsAll(['VALIDATION_EVIDENCE_MISSING','PUBLICATION_UNSUPPORTED']));
  });
  test('unvalidated cold branch cannot claim tested adaptive capability',() {
    final json=fixture();
    json['recipes'][16]['approvedBranches']=[{'id':'automatic-recovery'}];
    expect(errors(json),contains('UNVALIDATED_BRANCH'));
  });
  test('source content cannot smuggle safety-certification copy into a step',() {
    final json=fixture();
    json['recipes'][0]['steps'][0]['instructions']='This starter is guaranteed safe.';
    expect(errors(json),contains('PROHIBITED_CERTAINTY'));
  });
  test('invalid source and unknown media references fail closed',() {
    final json=fixture();
    json['recipes'][0]['mediaIds']=['nonexistent'];
    json['recipes'][0]['sourceUrls']=['javascript:alert(1)'];
    expect(errors(json),containsAll(['MEDIA_MISSING','SOURCE_URL_INVALID']));
  });
  test('malformed numeric values fail parsing rather than becoming defaults',() {
    final json=fixture();json['recipes'][0]['doughMassGrams']='lots';
    expect(()=>ContentCatalogue.fromJson(json),throwsFormatException);
  });
  test('caller mutation does not silently revise recipe snapshots',() {
    final json=fixture();final catalogue=ContentCatalogue.fromJson(json);
    json['recipes'][0]['title']='Mutated';
    expect(catalogue.recipeById('R01')!.title,'First white sourdough');
    final copy=catalogue.recipeById('R01')!.toJson();copy['title']='Again';
    expect(catalogue.recipeById('R01')!.title,'First white sourdough');
  });
}
