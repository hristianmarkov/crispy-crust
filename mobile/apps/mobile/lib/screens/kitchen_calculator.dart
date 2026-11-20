import 'package:flutter/material.dart';

import '../data/fermentation.dart';
import 'kitchen_design.dart';

enum KitchenCalculator { feed, hydration, rise }

class KitchenCalculatorScreen extends StatefulWidget {
  const KitchenCalculatorScreen(this.mode, {super.key});
  final KitchenCalculator mode;

  @override
  State<KitchenCalculatorScreen> createState() => _KitchenCalculatorState();
}

class _KitchenCalculatorState extends State<KitchenCalculatorScreen> {
  final entries = <String, double>{};

  Widget number(String label, double initial) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        initialValue: initial.toStringAsFixed(0),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label),
        onChanged: (value) => setState(() => entries[label] = double.tryParse(value) ?? double.nan),
      ),
    );
  }

  double read(String name, double defaultValue) => entries[name] ?? defaultValue;
  String g(double grams) => '${grams.toStringAsFixed(1)} g';

  @override
  Widget build(BuildContext context) {
    final resultStyle = Theme.of(context).textTheme.titleLarge;
    final fields = <Widget>[];
    late String title;
    String? result, explanation;
    switch (widget.mode) {
      case KitchenCalculator.feed:
        title = 'Feed calculator';
        const seed = 'Starter you keep (g)', flour = 'Flour parts', water = 'Water parts';
        fields.addAll([number(seed, 20), number(flour, 2), number(water, 2)]);
        final s = read(seed, 20), f = read(flour, 2), w = read(water, 2);
        if ([s, f, w].every((n) => n.isFinite && n > 0) && (s * (1 + f + w)).isFinite) {
          result = 'Add ${g(s * f)} flour + ${g(s * w)} water';
          explanation = 'You’ll have ${g(s * (1 + f + w))} of starter with a 1:$f:$w feed.';
        }
      case KitchenCalculator.hydration:
        title = 'Hydration calculator';
        const f = 'Added flour (g)', w = 'Added water (g)', s = 'Starter (g)',
          h = 'Starter hydration (%)', t = 'Target hydration (%)';
        fields.addAll([number(f, 450), number(w, 325), number(s, 100), number(h, 100), number(t, 75)]);
        final input = [read(f, 450), read(w, 325), read(s, 100), read(h, 100), read(t, 75)];
        if (input.every((n) => n.isFinite && n >= 0) && input.last > 0) {
          final starterFlour = input[2] / (1 + input[3] / 100);
          final flour = input[0] + starterFlour, water = input[1] + input[2] - starterFlour;
          if (flour > 0 && flour.isFinite && water.isFinite) {
            final target = input.last / 100, current = water / flour;
            result = '${(current * 100).toStringAsFixed(1)}% hydration';
            final extraWater = flour * target - water, extraFlour = water / target - flour;
            explanation = (current - target).abs() < .0001 ? 'You’re at your target.'
              : extraWater > 0 ? 'Add ${g(extraWater)} water to reach your target.'
              : 'Add ${g(extraFlour)} flour to reach your target.';
          }
        }
      case KitchenCalculator.rise:
        title = 'Rise forecast';
        const temp = 'Dough temperature (°C)';
        fields.add(number(temp, 24));
        final forecast = leanDoughRise(read(temp, 24));
        if (forecast != null) {
          result = '${(forecast.minimumMinutes / 60).toStringAsFixed(1)}–${(forecast.maximumMinutes / 60).toStringAsFixed(1)} hours';
          explanation = 'Check around ${forecast.risePercent}% rise. Look for bubbles at the edges and a gently domed, aerated dough.';
        } else {
          explanation = 'Enter a measured dough temperature from 18 to 27°C.';
        }
        fields.add(const KitchenInfo(title: 'Forecast assumptions',
          text: 'Reference estimates for a lean country loaf with about 20% active starter, 75% hydration and a cold final proof. Count from adding the starter. Starter strength, the flour and the dough’s temperature change the timing. Use the dough’s signs before shaping.'));
    }
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: KitchenPage(children: [
        ...fields,
        if (result != null) Text(result, style: resultStyle),
        if (explanation != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(explanation))
        else const Padding(padding: EdgeInsets.only(top: 8), child: Text('Enter positive quantities for this calculation.')),
      ]),
    );
  }
}
