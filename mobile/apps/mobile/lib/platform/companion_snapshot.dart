class CompanionTaskSnapshot {
  const CompanionTaskSnapshot({required this.bakeId, required this.stepId,
    required this.title, required this.action, required this.revision,
    required this.dueAt, required this.generatedAt});
  final String bakeId;
  final String stepId;
  final String title;
  final String action;
  final int revision;
  final DateTime dueAt;
  final DateTime generatedAt;
  bool isStaleAt(DateTime now) => now.difference(generatedAt) > const Duration(minutes: 15);
  Map<String, Object> toJson() => {'schemaVersion': 1, 'bakeId': bakeId,
    'stepId': stepId, 'title': title, 'action': action, 'revision': revision,
    'dueAt': dueAt.toUtc().toIso8601String(),
    'generatedAt': generatedAt.toUtc().toIso8601String()};
}

class CompanionAction {
  const CompanionAction({required this.operationId, required this.bakeId,
    required this.stepId, required this.expectedRevision, required this.type});
  final String operationId;
  final String bakeId;
  final String stepId;
  final int expectedRevision;
  final String type;
  factory CompanionAction.fromJson(Map<String, dynamic> json) {
    if (json['type'] != 'acknowledge' && json['type'] != 'open') {
      throw const FormatException('Unsupported companion action');
    }
    final operationId = json['operationId'] as String? ?? '';
    final bakeId = json['bakeId'] as String? ?? '';
    final stepId = json['stepId'] as String? ?? '';
    final revision = json['expectedRevision'];
    if (operationId.isEmpty || bakeId.isEmpty || stepId.isEmpty || revision is! int || revision < 1) {
      throw const FormatException('Invalid companion action');
    }
    return CompanionAction(operationId: operationId, bakeId: bakeId, stepId: stepId,
      expectedRevision: revision, type: json['type'] as String);
  }
}

/// The app repository must persist operationId with its mutation in one local
/// transaction; a watch acknowledgement alone never completes a physical task.
bool companionActionCanApply(CompanionAction action, CompanionTaskSnapshot task,
    Set<String> acceptedOperationIds) => !acceptedOperationIds.contains(action.operationId) &&
  action.bakeId == task.bakeId && action.stepId == task.stepId && action.expectedRevision == task.revision;
