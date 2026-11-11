import 'dart:convert';

typedef JsonObject = Map<String, dynamic>;

JsonObject _object(Object? value, String path) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('$path must be an object');
  }
  return value;
}

String _string(JsonObject json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string');
  }
  return value;
}

double _number(JsonObject json, String key) {
  final value = json[key];
  if (value is! num || !value.isFinite) {
    throw FormatException('$key must be a finite number');
  }
  return value.toDouble();
}

int _integer(JsonObject json, String key) {
  final value = _number(json, key);
  if (value != value.truncateToDouble()) {
    throw FormatException('$key must be an integer');
  }
  return value.toInt();
}

bool _boolean(JsonObject json, String key) {
  if (json[key] is! bool) throw FormatException('$key must be a boolean');
  return json[key] as bool;
}

List<dynamic> _list(JsonObject json, String key) {
  if (json[key] is! List) throw FormatException('$key must be an array');
  return json[key] as List<dynamic>;
}

List<String> _strings(JsonObject json, String key) => List.unmodifiable(
  _list(json, key).map((v) {
    if (v is! String || v.trim().isEmpty) {
      throw FormatException('$key must contain non-empty strings');
    }
    return v;
  }),
);

/// A catalogue is loaded by the app from its bundled JSON, without network IO.
/// Parsing enforces shape; ContentValidator enforces cross-record invariants.
final class ContentCatalogue {
  ContentCatalogue._(this.schemaVersion, this.contentVersion, this.warning,
      this.recipes, this.lessons, this.guidance, this.courses, this.publishedOn);

  factory ContentCatalogue.decode(String json) =>
      ContentCatalogue.fromJson(_object(jsonDecode(json), 'catalogue'));

  factory ContentCatalogue.fromJson(JsonObject json) => ContentCatalogue._(
    _integer(json, 'schemaVersion'),
    _string(json, 'contentVersion'),
    _string(json, 'warning'),
    List.unmodifiable(_list(json, 'recipes')
        .map((v) => RecipeContent.fromJson(_object(v, 'recipe')))),
    List.unmodifiable(_list(json, 'lessons')
        .map((v) => TechniqueLesson.fromJson(_object(v, 'lesson')))),
    List.unmodifiable(_list(json, 'guidance')
        .map((v) => ReviewedGuidance.fromJson(_object(v, 'guidance')))),
    List.unmodifiable(_list(json, 'courses')
        .map((v) => LearningCourse.fromJson(_object(v, 'course')))),
    json['publishedOn'] == null ? null : _string(json,'publishedOn'),
  );

  final int schemaVersion;
  final String contentVersion;
  final String warning;
  final String? publishedOn;
  final List<RecipeContent> recipes;
  final List<TechniqueLesson> lessons;
  final List<ReviewedGuidance> guidance;
  final List<LearningCourse> courses;

  RecipeContent? recipeById(String id) {
    for (final recipe in recipes) {
      if (recipe.id == id) return recipe;
    }
    return null;
  }

  JsonObject toJson() => {
    'schemaVersion': schemaVersion, 'contentVersion': contentVersion,
    'publishedOn': publishedOn,
    'warning': warning, 'recipes': recipes.map((v) => v.toJson()).toList(),
    'lessons': lessons.map((v) => v.toJson()).toList(),
    'guidance': guidance.map((v) => v.toJson()).toList(),
    'courses': courses.map((v) => v.toJson()).toList(),
  };
}

final class RecipeContent {
  RecipeContent._(this._json);
  factory RecipeContent.fromJson(JsonObject json) {
    for (final key in ['id','title','family','description','status','author',
      'rights','hydrationBasis','yieldUnit']) { _string(json,key); }
    for (final key in ['totalFlourGrams','totalWaterGrams','hydrationPercent',
      'doughMassGrams']) { _number(json,key); }
    for (final key in ['experimental','kitchenValidated',
      'requiresExplicitAcceptance']) { _boolean(json,key); }
    _integer(json,'version'); _integer(json,'yieldCount');
    for (final key in ['allergens','equipment','sourceUrls','mediaIds',
      'warnings','guidanceIds']) { _strings(json,key); }
    _list(json,'approvedBranches'); _object(json['validation'],'validation');
    final result=RecipeContent._(jsonDecode(jsonEncode(json)) as JsonObject);
    result.ingredients; result.steps;
    return result;
  }
  final JsonObject _json;
  String get id => _json['id'] as String;
  int get version => _integer(_json,'version');
  String get title => _json['title'] as String;
  String get family => _json['family'] as String;
  String get description => _json['description'] as String;
  String get status => _json['status'] as String;
  bool get experimental => _json['experimental'] as bool;
  bool get kitchenValidated => _json['kitchenValidated'] as bool;
  bool get requiresExplicitAcceptance => _json['requiresExplicitAcceptance'] as bool;
  double get totalFlourGrams => _number(_json,'totalFlourGrams');
  double get totalWaterGrams => _number(_json,'totalWaterGrams');
  double get hydrationPercent => _number(_json,'hydrationPercent');
  double get doughMassGrams => _number(_json,'doughMassGrams');
  int get yieldCount => _integer(_json,'yieldCount');
  String get yieldUnit => _json['yieldUnit'] as String;
  List<String> get allergens => _strings(_json,'allergens');
  List<String> get equipment => _strings(_json,'equipment');
  List<String> get mediaIds => _strings(_json,'mediaIds');
  List<String> get guidanceIds => _strings(_json,'guidanceIds');
  List<String> get warnings => _strings(_json,'warnings');
  List<RecipeIngredient> get ingredients => List.unmodifiable(
    _list(_json,'ingredients').map((v)=>RecipeIngredient.fromJson(_object(v,'ingredient'))));
  List<RecipeStep> get steps => List.unmodifiable(
    _list(_json,'steps').map((v)=>RecipeStep.fromJson(_object(v,'step'))));
  /// Explicit acceptance only enables experimental manual use; it cannot
  /// promote unvalidated content into an approved adaptive recipe.
  bool get canRunAutomatically => status=='published' && kitchenValidated && !experimental;
  JsonObject toJson() => jsonDecode(jsonEncode(_json)) as JsonObject;
}

final class RecipeIngredient {
  RecipeIngredient._(this.id,this.name,this.grams,this.role,this.flourGrams,
      this.waterGrams,this.allergens,this.stage);
  factory RecipeIngredient.fromJson(JsonObject json) => RecipeIngredient._(
    _string(json,'id'),_string(json,'name'),_number(json,'grams'),
    _string(json,'role'),_number(json,'flourGrams'),_number(json,'waterGrams'),
    _strings(json,'allergens'),_string(json,'stage'));
  final String id,name,role,stage;
  final double grams,flourGrams,waterGrams;
  final List<String> allergens;
  JsonObject toJson()=>{'id':id,'name':name,'grams':grams,'role':role,
    'flourGrams':flourGrams,'waterGrams':waterGrams,'allergens':allergens,'stage':stage};
}

final class RecipeStep {
  RecipeStep._(this.id,this.title,this.instructions,this.durationMinutes,
      this.kind,this.readinessCue,this.lessonId,this.resources,this.after,
      this.ingredientIds,this.timingStatus);
  factory RecipeStep.fromJson(JsonObject json) {
    final lesson=json['lessonId'];
    if (lesson!=null && lesson is! String) throw const FormatException('lessonId must be a string or null');
    return RecipeStep._(_string(json,'id'),_string(json,'title'),
      _string(json,'instructions'),_integer(json,'durationMinutes'),
      _string(json,'kind'),_string(json,'readinessCue'),lesson as String?,
      _strings(json,'resources'),_strings(json,'after'),
      _strings(json,'ingredientIds'),_string(json,'timingStatus'));
  }
  final String id,title,instructions,kind,readinessCue,timingStatus;
  final int durationMinutes;
  final String? lessonId;
  final List<String> resources,after,ingredientIds;
  JsonObject toJson()=>{'id':id,'title':title,'instructions':instructions,
    'durationMinutes':durationMinutes,'kind':kind,'readinessCue':readinessCue,
    'lessonId':lessonId,'resources':resources,'after':after,
    'ingredientIds':ingredientIds,'timingStatus':timingStatus};
}

final class TechniqueLesson {
  TechniqueLesson._(this._json);
  factory TechniqueLesson.fromJson(JsonObject json) {
    for(final key in ['id','title','courseId','status','summary','exercise','transcript']) { _string(json,key); }
    _strings(json,'instructions');_strings(json,'sourceUrls');
    _object(json['demonstration'],'demonstration');_object(json['review'],'review');
    return TechniqueLesson._(jsonDecode(jsonEncode(json)) as JsonObject);
  }
  final JsonObject _json;
  String get id=>_json['id'] as String;
  String get title=>_json['title'] as String;
  String get summary=>_json['summary'] as String;
  String get courseId=>_json['courseId'] as String;
  String get exercise=>_json['exercise'] as String;
  String get transcript=>_json['transcript'] as String;
  List<String> get instructions=>_strings(_json,'instructions');
  bool get hasDemonstration=>_json['demonstration']['status']=='produced';
  JsonObject toJson()=>jsonDecode(jsonEncode(_json)) as JsonObject;
}

/// The name expresses intended content type, not approval status: inspect
/// [status] and reviewer metadata before claiming human editorial review.
final class ReviewedGuidance {
  ReviewedGuidance._(this._json);
  factory ReviewedGuidance.fromJson(JsonObject json) {
    for(final key in ['id','title','status']) { _string(json,key); }
    _strings(json,'body');_list(json,'sources');
    return ReviewedGuidance._(jsonDecode(jsonEncode(json)) as JsonObject);
  }
  final JsonObject _json;
  String get id=>_json['id'] as String;
  String get title=>_json['title'] as String;
  String get status=>_json['status'] as String;
  List<String> get body=>_strings(_json,'body');
  List<JsonObject> get sources=>List.unmodifiable(_list(_json,'sources').map((v)=>Map<String,dynamic>.unmodifiable(_object(v,'source'))));
  JsonObject toJson()=>jsonDecode(jsonEncode(_json)) as JsonObject;
}

final class LearningCourse {
  LearningCourse._(this.id,this.title,this.lessonIds);
  factory LearningCourse.fromJson(JsonObject json)=>LearningCourse._(
    _string(json,'id'),_string(json,'title'),_strings(json,'lessonIds'));
  final String id,title;
  final List<String> lessonIds;
  JsonObject toJson()=>{'id':id,'title':title,'lessonIds':lessonIds};
}
