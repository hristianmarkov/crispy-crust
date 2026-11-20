import 'models.dart';

enum IssueSeverity { error, warning }

final class ContentIssue {
  const ContentIssue(this.code,this.path,this.message,
      [this.severity=IssueSeverity.error]);
  final String code,path,message;
  final IssueSeverity severity;
  @override
  String toString()=>'${severity.name}: $code at $path: $message';
}

/// Validates stored weights and graph semantics without turning editorial
/// drafts into kitchen evidence. No IO, current clock or model inference.
final class ContentValidator {
  const ContentValidator();
  List<ContentIssue> validate(ContentCatalogue catalogue,
      {Set<String> availableMediaIds=const {},bool forPublication=false}) {
    final issues=<ContentIssue>[];
    void add(String code,String path,String message,
        [IssueSeverity severity=IssueSeverity.error])=>
        issues.add(ContentIssue(code,path,message,severity));
    void unique(Iterable<String> ids,String path) {
      final seen=<String>{};
      for(final id in ids) {
        if(!seen.add(id)) add('DUPLICATE_ID',path,'Duplicate id $id');
      }
    }
    if(catalogue.schemaVersion!=1) {
      add('SCHEMA_UNSUPPORTED','catalogue','Only schemaVersion 1 is supported');
    }
    unique(catalogue.recipes.map((v)=>v.id),'recipes');
    unique(catalogue.lessons.map((v)=>v.id),'lessons');
    unique(catalogue.guidance.map((v)=>v.id),'guidance');
    unique(catalogue.courses.map((v)=>v.id),'courses');
    final lessonIds=catalogue.lessons.map((v)=>v.id).toSet();
    final guidanceIds=catalogue.guidance.map((v)=>v.id).toSet();
    const families={'country','wholegrain','tin','rye','focaccia','pizza',
      'bagels','enriched','discard'};
    for(final recipe in catalogue.recipes) {
      final path='recipes/${recipe.id}';
      final json=recipe.toJson();
      if(!families.contains(recipe.family)) add('FAMILY_UNKNOWN',path,'Unsupported recipe family');
      if(recipe.version<1 || recipe.yieldCount<1) add('QUANTITY_INVALID',path,'Version and yield must be positive');
      if(recipe.ingredients.isEmpty || recipe.steps.isEmpty) add('RECIPE_EMPTY',path,'Recipe needs ingredients and steps');
      unique(recipe.ingredients.map((v)=>v.id),'$path/ingredients');
      unique(recipe.steps.map((v)=>v.id),'$path/steps');
      double mass=0,flour=0,water=0;
      final allergens=<String>{};
      for(final ingredient in recipe.ingredients) {
        mass+=ingredient.grams;flour+=ingredient.flourGrams;water+=ingredient.waterGrams;
        allergens.addAll(ingredient.allergens);
        if(ingredient.grams<0 || ingredient.flourGrams<0 || ingredient.waterGrams<0 ||
            ingredient.flourGrams+ingredient.waterGrams>ingredient.grams+1e-6) {
          add('MASS_INVALID','$path/ingredients/${ingredient.id}','Contributions must be nonnegative and cannot exceed physical mass');
        }
        if(!{'flour','water','starter','salt','inclusion'}.contains(ingredient.role)) {
          add('INGREDIENT_ROLE_UNKNOWN',path,'Unknown ingredient role ${ingredient.role}');
        }
        if(ingredient.role=='flour' && (ingredient.flourGrams-ingredient.grams).abs()>1e-6) {
          add('FLOUR_COMPONENT_INVALID',path,'Flour ingredient mass must count as flour');
        }
        if(ingredient.role=='water' && (ingredient.waterGrams-ingredient.grams).abs()>1e-6) {
          add('WATER_COMPONENT_INVALID',path,'Water ingredient mass must count as water');
        }
        if(ingredient.role=='starter' && (ingredient.waterGrams+ingredient.flourGrams-ingredient.grams).abs()>1e-6) {
          add('STARTER_COMPONENT_INVALID',path,'Starter flour and water must account for its mass exactly once');
        }
      }
      if((mass-recipe.doughMassGrams).abs()>1e-6) add('MASS_TOTAL_MISMATCH',path,'Ingredient mass $mass differs from declared ${recipe.doughMassGrams}');
      if((flour-recipe.totalFlourGrams).abs()>1e-6 || flour<=0) add('FLOUR_TOTAL_MISMATCH',path,'Total flour must include starter flour exactly once');
      if((water-recipe.totalWaterGrams).abs()>1e-6) add('WATER_TOTAL_MISMATCH',path,'Total water must include declared starter water');
      if(flour>0 && (water/flour*100-recipe.hydrationPercent).abs()>1e-5) add('HYDRATION_MISMATCH',path,'Hydration does not match water/flour basis');
      if(allergens.length!=recipe.allergens.toSet().length || !allergens.containsAll(recipe.allergens)) add('ALLERGEN_MISMATCH',path,'Declared allergens must equal the ingredient union; unknown does not mean free from');
      final ids=recipe.steps.map((v)=>v.id).toSet();
      final ingredients=recipe.ingredients.map((v)=>v.id).toSet();
      final seenIngredients=<String>{};
      final stepMap={for(final s in recipe.steps)s.id:s};
      for(final s in recipe.steps) {
        if(s.durationMinutes<0 || s.durationMinutes>10080) add('DURATION_INVALID','$path/steps/${s.id}','Duration is invalid or exceeds the one-week draft bound');
        if(!{'handsOn','wait','check'}.contains(s.kind)) add('STEP_KIND_UNKNOWN',path,'Unknown step kind');
        if(s.kind=='check' && s.readinessCue.trim().isEmpty) add('READINESS_CUE_MISSING',path,'Check steps need observation cues');
        if(!ids.containsAll(s.after)) add('GRAPH_DEPENDENCY_MISSING',path,'${s.id} names a missing dependency');
        if(s.lessonId!=null && !lessonIds.contains(s.lessonId)) add('LESSON_MISSING',path,'${s.id} names an absent lesson');
        if(!ingredients.containsAll(s.ingredientIds)) add('INGREDIENT_REFERENCE_MISSING',path,'${s.id} names an absent ingredient');
        seenIngredients.addAll(s.ingredientIds);
        if(RegExp(r'guaranteed safe|certified safe|100% accurate',caseSensitive:false).hasMatch(s.instructions)) {
          add('PROHIBITED_CERTAINTY',path,'Instruction contains a prohibited safety/accuracy claim');
        }
      }
      final active=<String>{},done=<String>{};
      bool visit(String id) {
        if(active.contains(id)) return false;
        if(done.contains(id)) return true;
        active.add(id);
        for(final parent in stepMap[id]?.after??<String>[]) {
          if(ids.contains(parent) && !visit(parent)) return false;
        }
        active.remove(id);done.add(id);return true;
      }
      if(ids.any((id)=>!visit(id))) add('GRAPH_CYCLE',path,'Execution graph must be acyclic');
      if(!seenIngredients.containsAll(ingredients)) add('INGREDIENT_UNUSED',path,'Each physical ingredient needs an explicit use stage');
      if(!guidanceIds.containsAll(recipe.guidanceIds)) add('GUIDANCE_MISSING',path,'Recipe references missing guidance');
      for(final id in recipe.mediaIds) {
        if(!availableMediaIds.contains(id)) add('MEDIA_MISSING',path,'Missing media $id');
      }
      final validation=json['validation'] as Map<String,dynamic>;
      final trialIds=validation['trialIds'];
      final hasEvidence=validation['reviewer'] is String && (validation['reviewer'] as String).trim().isNotEmpty && trialIds is List && trialIds.isNotEmpty && trialIds.every((v)=>v is String && v.trim().isNotEmpty);
      if(recipe.kitchenValidated && !hasEvidence) add('VALIDATION_EVIDENCE_MISSING',path,'Kitchen validation needs reviewer and trial records');
      if(!recipe.kitchenValidated && (!recipe.experimental || !recipe.requiresExplicitAcceptance)) add('DRAFT_NOT_GATED',path,'Unvalidated recipes must be experimental with explicit acceptance');
      if(!recipe.kitchenValidated && (json['approvedBranches'] as List).isNotEmpty) add('UNVALIDATED_BRANCH',path,'Unvalidated content may not declare approved adaptive branches');
      if(recipe.status=='published' && (!recipe.kitchenValidated || recipe.experimental || !hasEvidence)) add('PUBLICATION_UNSUPPORTED',path,'Publishing needs kitchen evidence and cleared experimental status');
      if(!recipe.kitchenValidated) add('KITCHEN_TRIALS_PENDING',path,'Draft is structurally valid, not kitchen-tested',IssueSeverity.warning);
      if(forPublication && !recipe.canRunAutomatically) add('NOT_PUBLICATION_READY',path,'Recipe has not passed the publication gate');
      for(final source in (json['sourceUrls'] as List).cast<String>()) {
        if(!_https(source)) add('SOURCE_URL_INVALID',path,'Sources must be public HTTPS URLs');
      }
    }
    for(final course in catalogue.courses) {
      if(!lessonIds.containsAll(course.lessonIds)) add('COURSE_LESSON_MISSING',course.id,'Course names a missing lesson');
    }
    for(final lesson in catalogue.lessons) {
      if(lesson.instructions.isEmpty) add('LESSON_EMPTY',lesson.id,'Lesson needs written instructions');
      if(!lesson.hasDemonstration) add('DEMONSTRATION_PENDING',lesson.id,'Written content exists; real media production remains pending',forPublication?IssueSeverity.error:IssueSeverity.warning);
      if(lesson.hasDemonstration) {
        final demo=lesson.toJson()['demonstration'] as Map<String,dynamic>;
        for(final field in ['videoAssetId','captionAssetId']) {
          if(demo[field] is! String || !availableMediaIds.contains(demo[field])) {
            add('DEMONSTRATION_MEDIA_MISSING',lesson.id,'Produced demonstration needs an available $field');
          }
        }
      }
    }
    for(final guide in catalogue.guidance) {
      if(guide.sources.isEmpty || guide.sources.any((s)=>!_https(s['url'] as String? ?? ''))) add('GUIDANCE_SOURCE_INVALID',guide.id,'Guidance requires HTTPS primary source references');
      if(forPublication && guide.toJson()['reviewer']==null) add('GUIDANCE_REVIEW_PENDING',guide.id,'Human editorial review is required');
    }
    return List.unmodifiable(issues);
  }
  bool _https(String value) {
    final uri=Uri.tryParse(value);
    return uri!=null && uri.scheme=='https' && uri.host.isNotEmpty && uri.userInfo.isEmpty;
  }
}
