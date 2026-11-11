# Crispy Crust content source

`catalogue.json` is the offline bundle: 24 original recipe drafts matching the
commission, 18 text lessons across three course paths, and two primary-source
linked safety guidance drafts. `schema/catalogue-v1.schema.json` is the strict
JSON shape contract; the pure-Dart `content_models` validator adds cross-record
and arithmetic constraints. Recipe snapshots retain explicit author/rights,
method, ingredients, allergens, stage graph, resource needs and evidence status.

## Current authority

**None of these recipes has been independently reviewed or kitchen-tested.**
All are experimental, require explicit acceptance, contain draft timing rather
than validated ranges, and have no approved adaptive branches. User acceptance
does not supply kitchen evidence. No trials, process photos, captions, videos,
device tests or reviewer identities have been fabricated. Content must not be
marketed as ready for the launch described in the plan.

The different bread families have different execution graphs: rye has tin-paste
handling without wheat folds; focaccia has tray proof and dimpling; pizza has
balling and a separately flagged experimental cold route; bagels boil; enriched
dough separates filling and perishable-ingredient handling; discard methods use
no fermentation guarantee. The seeded recipe accounts for soaker water once.
Milk/egg water is explicitly excluded from the displayed conventional hydration,
instead of hiding an invented water-content assumption.

## User experience

- Show an Experimental draft badge on every recipe and a full warning before
  starting. Preserve acceptance and pinned recipe version in the bake record.
- Use written lessons/transcripts offline. Say demonstration unavailable for
  every pending video; do not show a play control that pretends to work.
- Draft minute values may support manual reminder creation; do not use them as
  automatic biological readiness or a recipe-supported interruption rescue.
- Ingredients, timing, rise and review fields retain unknown/pending states.
- Store actual kitchen observations separately from content. They do not become
  published validation records without a human review and publication process.

## Required publication evidence

For each recipe, commission independent author/reviewer approval and baseline,
warm/cool, yield/equipment and every advertised branch trial. Store actual
measurements, formula/content version, reviewer identity and outcome evidence.
Produce real photographs, process demonstrations, captions and useful
left-handed views. Clear rights and validate allergens before publication.

The sources below support the short guidance summaries only, not our formulas
or timing values. All recipe/lesson prose here is newly authored rather than
copied from the source articles. References were inspected 11 November 2026:

- [King Arthur Baking: create a sourdough starter](https://www.kingarthurbaking.com/learn/guides/sourdough/create)
- [FDA: handling raw flour safely](https://www.fda.gov/food/buy-store-serve-safe-food/handling-flour-safely-what-you-need-know)
- [FDA: safe food handling](https://www.fda.gov/food/buy-store-serve-safe-food/safe-food-handling)
- [King Arthur Baking: hydration definitions](https://www.kingarthurbaking.com/blog/2023/01/11/bread-hydration)

These public URLs are references, not fetched during an offline bake.
