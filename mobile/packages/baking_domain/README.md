# Baking domain

Pure Dart, no Flutter/network/cloud dependency. All clocks and UTC inputs are supplied by the caller. No code here calls an LLM, declares a starter safe, infers that a timer completed a physical step, or publishes a recipe as tested.

```dart
final formula = const FormulaEngine().calculate(
  FormulaDefinition.fromNumbers(totalFlour: 1000, hydration: .75),
);
// Added flour 900, water 650, starter 200, salt 20; dough 1770g.
final weighOut = formula.roundForScale(incrementGrams: 1);
```

## Contracts

- `Rational` uses reduced BigInt fractions. Construct with decimal `parse`, `fromNum`, or numerator/denominator. JSON stores integer strings. Display conversion is explicit; engine math never rounds floats.
- `FormulaEngine.calculate` handles prefermented flour, starter hydration, inclusions and explicit inclusion water, loaf-count or total-dough scaling. `roundForScale` conserves the rounded mass by a documented water/flour residual. `buildStarter` includes retained mother/waste allowance and rejects insufficient seed.
- `RecipeGraph` is a DAG. Each `RecipeStep` has duration bounds, dependency IDs, maximum permitted wait after dependencies (default zero), active subintervals, full-stage resource demands and an optional start window. Every imported graph/profile must be labelled and reviewed by the content pipeline outside this package.
- `PlanningEngine.solve` returns typed feasible/infeasible/unsupported/searchIncomplete results. Forward anchors are exact starts; backward anchors are exact finishes/serving times, so cooling must be an explicit stage. Unavailable windows affect hands-on intervals; resource reservations affect entire declared occupancy. Exact times are UTC instants with a kitchen IANA-zone label; timezone/DST resolution belongs to the app adapter.
- The deterministic solver samples nominal/minimum/maximum durations and searches constraint boundaries under a node budget. It **does not** claim global optimisation or robust feasibility over continuous biology. Failed variable-duration search is incomplete, not proven infeasible. Explicit reviewed alternative graphs should be solved separately and compared. Variable/readiness schedules always require observation. An unfinished biological stage is never auto-completed.
- `validate` checks tasks/version, durations, dependencies, busy windows, resources and immutable completed history. `proposeRecovery` returns a revision-bound diff; applying it requires a separate repository transaction/CAS and reminder reconciliation.
- `BakeReducer` maintains immutable event history, explicit lifecycle, idempotent delivery, duplicate physical-action review and explicit timestamp corrections. It does not authorise user roles; the repository/server must validate actors and graph transitions. Server sequence is authoritative; backdated occurrence remains separate.
- `StarterEstimator` only uses same-jar, same flour/hydration/ratio/storage observations with known comparable temperatures and confirmed peaks. Five comparable records are a product threshold, **not scientific calibration**. Sparse history uses caller-supplied reviewed broad bounds. Full observed range plus margin is empirical guidance, no probability/confidence percentage. Missed peaks stay unknown.

Run `dart pub get`, `dart analyze`, and `dart test` from this package. Tests are synthetic engine fixtures, not kitchen validation of recipe methods. Content review, real bake trials, clock/timezone adapters, cloud policy tests and physical notification/device verification remain separate launch evidence.

`FormulaDefinition.preferments` supports multiple independently hydrated preferments. If the list is nonempty it replaces the single-starter fraction/hydration fields. Every preferment flour fraction uses total formula flour as its basis. Physical ingredient rows are named `preferment:<id>`; `FormulaResult.starterMass` is their summed physical mass. Fractions must not exceed total flour, and supplied water must not exceed formula water.

`BakeComparator` compares recorded canonical measurements and named conditions, keeps unknown fields explicit, identifies intended versus uncontrolled changes, and never makes a causal claim. `CostAndShoppingEngine` aggregates exact demand, computes costs using dated same-currency pack prices, leaves totals unknown if any ingredient price is missing, and keeps unknown stock distinct from zero. `safeCsv` is available for escaped, spreadsheet-safe text exports; preserve original text in structured JSON archives.

## Production planning

`ProductionMethod` binds a per-piece `PhysicalFormula`, recipe graph, named cooling/readiness sink, an explicit reviewed `maximumPiecesPerLoad` envelope, validation evidence ID, resource units that scale per piece, and authored oven-step temperatures. Evidence identifiers are provenance inputs, not proof of real kitchen testing; the content pipeline must verify them.

`ProductionPlanner.compose` splits counts into separately identified loads. A request for 100 pieces at one reviewed piece/load produces 100 distinct bake reservations, formulas and pack-list rows. Vessel/fridge/rack demands can scale per piece; an oven slot normally scales per load. Caller-supplied reload durations and documented cross-load temperature transitions occupy the oven. Recipe-internal temperature changes must already be represented in its reviewed method/profile. No time, temperature, waiting/retard or yield range is invented to make a production run fit.

Pass the `ProductionBlueprint` to `ProductionPlanner.solve` with capacities, a UTC horizon, existing reservations and unavailable windows. Each load's cooling sink must complete by pickup-window start. One displayed, conservatively serial oven order is solved (earliest pickup then ID, or an explicit order supplied by the caller), with no global optimum claim. A failed order is `searchIncomplete`; try another reviewed order/quantity/target, rather than treating it as proof that all production schedules are impossible. The configured generated-load limit bounds huge requests. Packing labels state planned pieces/dough mass; actual sellable yield, allergen/legal labelling and shelf-life assurance are not inferred.

Blueprints expose exact aggregated `shoppingDemand`, `packList`, and price-based `cost(...)` with unknown prices remaining unknown. Cost estimates are not accounting/tax compliance or real checkout integrations.
