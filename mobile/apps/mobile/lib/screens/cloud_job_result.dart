import 'package:flutter/material.dart';
import 'kitchen_design.dart';

/// Convert worker output to editable inputs. All weights and durations require
/// user confirmation in the private recipe editor.
Map<String, dynamic> importedRecipeDraft(Map<String, dynamic> result, String jobId) {
  final url = result['source_uri'];
  final raw = result['source_text'];
  final title = result['title'];
  final ingredientLines = (result['ingredients'] is List ? result['ingredients'] as List : const [])
      .whereType<String>().where((value) => value.trim().isNotEmpty).take(100);
  return {
    'importJobId': jobId,
    'title': title is String && title.trim().isNotEmpty ? _limit(title.trim(), 200) : 'Imported recipe',
    'source': url is String ? _limit(url, 4000) : 'Pasted recipe text',
    if (raw is String) 'notes': _limit(raw, 20000),
    'draftIngredients': [
      for (final line in ingredientLines) {'name': line.trim()},
    ],
    'draftSteps': [
      for (final (index, instruction) in _instructions(result['instructions']).take(100).indexed)
        {'title': 'Step ${index + 1}', 'instructions': instruction},
    ],
  };
}

String _limit(String text, int length) => text.length > length ? text.substring(0, length) : text;

Iterable<String> _instructions(Object? value, [int depth = 0]) sync* {
  if (depth > 8) return;
  if (value is String && value.trim().isNotEmpty) {
    yield value.trim();
  } else if (value is List) {
    for (final row in value) {
      yield* _instructions(row, depth + 1);
    }
  } else if (value is Map) {
    yield* _instructions(value['itemListElement'] ?? value['text'], depth + 1);
  }
}

class CloudJobResultScreen extends StatelessWidget {
  const CloudJobResultScreen({super.key, required this.job, this.reviewImport});

  final Map<String, dynamic> job;
  final Future<void> Function(BuildContext, Map<String, dynamic>)? reviewImport;

  @override
  Widget build(BuildContext context) {
    final kind = job['kind'];
    final status = job['status'];
    final result = job['result'];
    final title = switch (kind) {
      'import' => 'Recipe import',
      'coach' || 'image' => 'Coach response',
      'export' => 'Account export',
      'delete_account' => 'Account deletion',
      _ => 'Cloud request',
    };
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(child: KitchenPage(children: [
          Text(switch (status) {
            'queued' => 'Waiting to run',
            'running' => 'Processing',
            'complete' => 'Completed',
            'failed' => 'Request failed',
            'canceled' => 'Request cancelled',
            _ => 'Status unavailable',
          }, style: Theme.of(context).textTheme.titleLarge),
          if (job['error_code'] case final String error) SelectableText('Service code $error'),
          if (status == 'complete' && result is Map<String, dynamic>) ...[
            if (kind == 'import') ...[
              if (result['title'] case final String title) Text(title),
              if (result['source_uri'] case final String source) SelectableText(source),
              if (result['issues'] case final List issues)
                for (final issue in issues.whereType<String>()) Text('• $issue'),
              if (result['source_text'] case final String text)
                ExpansionTile(title: const Text('Read extracted text'), children: [SelectableText(text)]),
              if (reviewImport != null)
                FilledButton(
                  onPressed: () async {
                    await reviewImport!(context, importedRecipeDraft(result, job['id'] as String));
                  },
                  child: const Text('Review in private recipe editor'),
                ),
            ] else if (kind == 'coach' || kind == 'image') ...[
              const Text('AI suggestions for your next observation.'),
              ..._section(context, 'Observations', result['observations']),
              ..._section(context, 'Possible explanations', result['possibilities']),
              ..._section(context, 'Next check', result['next_check']),
              ..._section(context, 'Uncertainty', result['uncertainty']),
            ],
          ],
          const SizedBox(height: 16),
          SelectableText('Request ID ${job['id']}'),
        ],
      )),
    );
  }

  List<Widget> _section(BuildContext context, String label, Object? value) {
    final lines = value is List ? value.whereType<String>() : [if (value is String) value];
    if (lines.isEmpty) return const [];
    return [
      const SizedBox(height: 16),
      Text(label, style: Theme.of(context).textTheme.titleMedium),
      for (final line in lines) SelectableText(line),
    ];
  }
}
