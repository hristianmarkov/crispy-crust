import 'dart:convert';

/// Exact reduced rational. JSON carries numerator/denominator strings so no
/// precision is lost on platforms whose JSON numbers use IEEE-754 doubles.
final class Rational implements Comparable<Rational> {
  final BigInt numerator;
  final BigInt denominator;
  factory Rational(BigInt numerator, [BigInt? denominator]) {
    var d = denominator ?? BigInt.one;
    if (d == BigInt.zero) throw ArgumentError('Denominator cannot be zero');
    if (d.isNegative) { numerator = -numerator; d = -d; }
    final gcd = numerator.gcd(d);
    return Rational._(numerator ~/ gcd, d ~/ gcd);
  }
  const Rational._(this.numerator, this.denominator);
  factory Rational.parse(String value) {
    final text = value.trim();
    if (text.contains('/')) {
      final bits = text.split('/');
      if (bits.length != 2) throw FormatException('Invalid rational', value);
      return Rational(BigInt.parse(bits[0]), BigInt.parse(bits[1]));
    }
    final match = RegExp(r'^([+-]?)(\d+)(?:\.(\d+))?(?:[eE]([+-]?\d+))?$').firstMatch(text);
    if (match == null) throw FormatException('Invalid decimal', value);
    final fraction = match[3] ?? '';
    var n = BigInt.parse('${match[2]}$fraction');
    if (match[1] == '-') n = -n;
    final power = fraction.length - int.parse(match[4] ?? '0');
    if (power.abs() > 10000) throw FormatException('Decimal exponent too large');
    return power >= 0
        ? Rational(n, BigInt.from(10).pow(power))
        : Rational(n * BigInt.from(10).pow(-power));
  }
  factory Rational.fromNum(num value) {
    if (!value.isFinite) throw ArgumentError('Quantity must be finite');
    return Rational.parse(value.toString());
  }
  factory Rational.fromJson(Map<String, dynamic> json) => Rational(
    BigInt.parse(json['n'] as String), BigInt.parse(json['d'] as String));
  static final zero = Rational(BigInt.zero);
  static final one = Rational(BigInt.one);
  Rational operator +(Rational other) => Rational(numerator * other.denominator + other.numerator * denominator, denominator * other.denominator);
  Rational operator -(Rational other) => Rational(numerator * other.denominator - other.numerator * denominator, denominator * other.denominator);
  Rational operator *(Rational other) => Rational(numerator * other.numerator, denominator * other.denominator);
  Rational operator /(Rational other) => Rational(numerator * other.denominator, denominator * other.numerator);
  bool operator <(Rational other) => compareTo(other) < 0;
  bool operator >(Rational other) => compareTo(other) > 0;
  bool operator <=(Rational other) => compareTo(other) <= 0;
  bool operator >=(Rational other) => compareTo(other) >= 0;
  bool get isNegative => numerator.isNegative;
  double toDouble() => numerator.toDouble() / denominator.toDouble();
  /// Half away from zero; weights normally have a nonnegative domain.
  BigInt round() {
    final rounded = (numerator.abs() * BigInt.two + denominator) ~/ (denominator * BigInt.two);
    return numerator.isNegative ? -rounded : rounded;
  }
  Rational roundTo(Rational increment) => Rational((this / increment).round()) * increment;
  Map<String, dynamic> toJson() => {'n': numerator.toString(), 'd': denominator.toString()};
  @override int compareTo(Rational other) => (numerator * other.denominator).compareTo(other.numerator * denominator);
  @override bool operator ==(Object other) => other is Rational && numerator == other.numerator && denominator == other.denominator;
  @override int get hashCode => Object.hash(numerator, denominator);
  @override String toString() => denominator == BigInt.one ? numerator.toString() : '$numerator/$denominator';
}

final class DomainException implements Exception {
  final String code;
  final String message;
  final Map<String, dynamic> details;
  const DomainException(this.code, this.message, [this.details = const {}]);
  Map<String, dynamic> toJson() => {'code': code, 'message': message, 'details': details};
  @override String toString() => '$code: $message';
}

/// Stable recursive key order supports idempotency hashes computed by callers.
String canonicalJson(Object? value) {
  Object? sort(Object? object) {
    if (object is Map) {
      final keys = object.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: sort(object[key])};
    }
    if (object is List) return object.map(sort).toList();
    return object;
  }
  return jsonEncode(sort(value));
}

/// Defensive JSON value copy for immutable event payloads. Rejects non-JSON
/// values and nonfinite numbers before they reach a durable event stream.
Map<String,dynamic> immutableJsonMap(Map<String,dynamic> source) {
 Object? freeze(Object? value) {
  if(value==null||value is String||value is bool)return value;
  if(value is num){if(!value.isFinite)throw ArgumentError('JSON numeric value must be finite');return value;}
  if(value is List)return List<Object?>.unmodifiable(value.map(freeze));
  if(value is Map){
   if(value.keys.any((key)=>key is! String))throw ArgumentError('JSON object keys must be strings');
   return Map<String,Object?>.unmodifiable(value.map((k,v)=>MapEntry(k as String,freeze(v))));
  }
  throw ArgumentError('Event payload contains a non-JSON value');
 }
 return Map<String,dynamic>.unmodifiable(source.map((k,v)=>MapEntry(k,freeze(v))));
}
