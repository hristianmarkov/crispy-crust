import 'package:flutter_test/flutter_test.dart';
import 'package:crispy_crust/data/fermentation.dart';

void main() {
  test('cold dough continues fermenting while cooling, with reduced activity', () {
    final short = equivalentWarmMinutes(60, 24);
    final long = equivalentWarmMinutes(360, 24);
    expect(short, greaterThan(0));
    expect(short, lessThan(60));
    expect(long, greaterThan(short));
    expect(long, lessThan(360));
  });
  test('a chilled centre takes longer to recover than dough already at room temperature', () {
    expect(counterRecoveryMinutes(0, 24, 100), 100);
    final shortHold = counterRecoveryMinutes(60, 24, 100);
    final longHold = counterRecoveryMinutes(360, 24, 100);
    expect(shortHold, greaterThan(100));
    expect(longHold, greaterThan(shortHold));
    expect(counterRecoveryMinutes(360, 24, 0), 0);
  });
  test('current recipe versions support temperature planning without changing the original', () {
    final original = <String, dynamic>{'id': 'R01', 'version': 2, 'steps': [
      {'id': 'mix', 'durationMinutes': 10},
      {'id': 'bulk', 'durationMinutes': 240},
    ]};
    final cool = recipeAtDoughTemperature(original, 18);
    final warm = recipeAtDoughTemperature(original, 27);
    expect((cool['steps'] as List).last['durationMinutes'], greaterThan(240));
    expect((warm['steps'] as List).last['durationMinutes'], lessThan(240));
    expect((original['steps'] as List).last['durationMinutes'], 240);
    expect(identical(recipeAtDoughTemperature(original, 4), original), isTrue);
  });
}
