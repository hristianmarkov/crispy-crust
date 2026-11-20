# Content models

Pure Dart, IO-free parsing and validation of the versioned app content catalogue.

```dart
final catalogue = ContentCatalogue.decode(jsonText);
final recipe = catalogue.recipeById('R01');
final issues = const ContentValidator().validate(catalogue);
```

All recipe snapshots are isolated from caller mutations. Lists are unmodifiable.
Parsing rejects malformed numeric/boolean/array input; validation checks formula
mass, starter contribution, allergen union, graph dependencies/cycles, references,
unsafe certainty copy and publication evidence. It never substitutes for kitchen
testing. Engine arithmetic belongs to `baking_domain`, not this display/content
package.

From this package directory:

```sh
dart pub get
dart test
dart run bin/validate.dart ../../content/catalogue.json
dart run bin/validate.dart ../../content/catalogue.json --publication
```

The last command **must fail** for the bundled editorial drafts: independent
recipe review, kitchen trials, real instructional media and editorial guidance
review have not happened. Structural validation can pass while publication is
blocked. UI may offer explicitly accepted experimental manual bakes, but must not
render draft timing as a validated adaptive method or a readiness guarantee.
