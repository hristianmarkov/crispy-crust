import 'app_store.dart';

class StarterRoutine {
  const StarterRoutine(this.hours, this.anchor, {this.paused = false, this.configuredAt});
  final int hours;
  final DateTime anchor;
  final bool paused;
  final DateTime? configuredAt;

  static bool isAway(String storage) => storage == 'paused' || storage == 'travel';
  static int suggestedHours(String storage) => storage == 'fridge' ? 168 : 24;

  static StarterRoutine? read(AppRecord starter) {
    final data = starter.fields['feedRoutine'];
    if (data is! Map) return null;
    final hours = data['hours'];
    final anchor = DateTime.tryParse(data['anchor']?.toString() ?? '');
    if (hours is! int || hours < 1 || hours > 720 || anchor == null) return null;
    return StarterRoutine(hours, anchor, paused: data['paused'] == true,
      configuredAt: DateTime.tryParse(data['configuredAt']?.toString() ?? ''));
  }

  Map<String, Object> toJson() => {
    'hours': hours, 'anchor': anchor.toUtc().toIso8601String(), 'paused': paused,
    if (configuredAt != null) 'configuredAt': configuredAt!.toUtc().toIso8601String(),
  };

  DateTime? dueAt(AppRecord starter) {
    if (paused || isAway(starter.text('storage')) || starter.flag('archived')) return null;
    final lastFeed = starter.date('lastFeedAt');
    final baseline = lastFeed != null && lastFeed.isAfter(configuredAt ?? anchor) ? lastFeed : anchor;
    return baseline.add(Duration(hours: hours));
  }
}
