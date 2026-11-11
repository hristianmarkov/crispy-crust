import 'common.dart';
import 'planning.dart';

final class FeedContext {
 final String starterId,flourMixKey,storageMode;
 final Rational hydration,flourParts,waterParts;
 final double? temperatureC;
 FeedContext({required this.starterId,required this.flourMixKey,required this.hydration,required this.flourParts,required this.waterParts,this.storageMode='counter',this.temperatureC}) {
  if(starterId.isEmpty||flourMixKey.isEmpty||hydration.isNegative||flourParts<=Rational.zero||waterParts.isNegative||(temperatureC!=null&&!temperatureC!.isFinite))throw ArgumentError('Invalid comparable feed context');
 }
 bool comparableTo(FeedContext other,{double temperatureToleranceC=2})=>starterId==other.starterId&&flourMixKey==other.flourMixKey&&storageMode==other.storageMode&&hydration==other.hydration&&flourParts==other.flourParts&&waterParts==other.waterParts&&temperatureC!=null&&other.temperatureC!=null&&(temperatureC!-other.temperatureC!).abs()<=temperatureToleranceC;
}
enum PeakStatus { observed,notYet,missedUnknown,falling }
final class PeakRecord {
 final String id;
 final FeedContext context;
 final DateTime fedAt;
 final DateTime? peakAt;
 final PeakStatus status;
 PeakRecord({required this.id,required this.context,required this.fedAt,this.peakAt,required this.status}) {
  if(id.isEmpty||!fedAt.isUtc||(peakAt!=null&&(!peakAt!.isUtc||peakAt!.isBefore(fedAt))))throw ArgumentError('Peak record needs valid UTC times');
  if(status==PeakStatus.observed&&peakAt==null)throw ArgumentError('Observed peak requires its recorded time');
 }
}
final class PeakEstimate {
 final TimeWindow checkWindow;
 final DateTime nominal;
 final bool personalized;
 final int comparableCount;
 final List<String> sourceRecordIds;
 final String explanation,modelVersion;
 /// This empirical guidance carries no calibrated probability claim.
 final bool statisticallyCalibrated;
 PeakEstimate({required this.checkWindow,required this.nominal,required this.personalized,required this.comparableCount,required List<String> sourceRecordIds,required this.explanation,this.modelVersion='starter-empirical-1',this.statisticallyCalibrated=false}):sourceRecordIds=List.unmodifiable(sourceRecordIds);
 Map<String,dynamic> toJson()=>{'window':checkWindow.toJson(),'nominal':nominal.toIso8601String(),'personalized':personalized,'comparableCount':comparableCount,'sourceRecordIds':sourceRecordIds,'explanation':explanation,'modelVersion':modelVersion,'statisticallyCalibrated':statisticallyCalibrated};
}
final class StarterEstimator {
 final int minimumComparableRecords;
 final Duration maximumHistoryAge;
 final double temperatureToleranceC;
 const StarterEstimator({this.minimumComparableRecords=5,this.maximumHistoryAge=const Duration(days:180),this.temperatureToleranceC=2});
 PeakEstimate estimate({required FeedContext context,required DateTime fedAt,required DateTime now,required List<PeakRecord> history,required Duration reviewedEarliest,required Duration reviewedLatest}) {
  if(minimumComparableRecords<5||temperatureToleranceC<0||!fedAt.isUtc||!now.isUtc||reviewedEarliest.isNegative||reviewedLatest<reviewedEarliest)throw ArgumentError('Invalid estimate bounds or calibration threshold');
  final seen=<String>{};
  final comparable=history.where((r)=>seen.add(r.id)&&r.status==PeakStatus.observed&&r.peakAt!=null&&!r.fedAt.isAfter(fedAt)&&!r.peakAt!.isAfter(now)&&now.difference(r.fedAt)<=maximumHistoryAge&&context.comparableTo(r.context,temperatureToleranceC:temperatureToleranceC)).toList()..sort((a,b)=>a.peakAt!.difference(a.fedAt).compareTo(b.peakAt!.difference(b.fedAt)));
  final personalized=comparable.length>=minimumComparableRecords;
  var low=reviewedEarliest,high=reviewedLatest;
  var nominal=Duration(microseconds:(low.inMicroseconds+high.inMicroseconds)~/2);
  if(personalized){
   final values=comparable.map((r)=>r.peakAt!.difference(r.fedAt).inMicroseconds).toList();
   // Include full observed range and a 15% margin, never advertise a precise
   // 80% confidence interval from a handful of self-selected logs.
   final median=values.length.isOdd?values[values.length~/2]:(values[values.length~/2-1]+values[values.length~/2])~/2;
   final margin=(median*.15).round();
   low=Duration(microseconds:(values.first-margin).clamp(0,values.first).toInt());
   high=Duration(microseconds:values.last+margin);
   nominal=Duration(microseconds:median);
  }
  return PeakEstimate(checkWindow:TimeWindow(fedAt.add(low),fedAt.add(high)),nominal:fedAt.add(nominal),personalized:personalized,comparableCount:comparable.length,sourceRecordIds:comparable.map((r)=>r.id).toList(),explanation:personalized?'Empirical window from ${comparable.length} comparable observed feeds; check the jar. This is not a readiness or safety guarantee.':'Not enough comparable observed peaks. Using the supplied reviewed broad care window.');
 }
}
Rational risePercentage({required Rational baselineHeight,required Rational currentHeight,required bool straightSidedOrCalibrated}) {
 if(!straightSidedOrCalibrated)throw const DomainException('CONTAINER_UNCALIBRATED','Height does not measure volume rise in this container.');
 if(baselineHeight<=Rational.zero||currentHeight<Rational.zero)throw ArgumentError('Baseline must be positive and current height nonnegative');
 return (currentHeight-baselineHeight)/baselineHeight*Rational.fromNum(100);
}
