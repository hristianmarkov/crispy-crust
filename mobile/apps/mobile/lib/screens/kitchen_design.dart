import 'package:flutter/material.dart';

class KitchenActions extends StatelessWidget {
  const KitchenActions({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Material(
    color: Theme.of(context).colorScheme.surface,
    child: SafeArea(top: false, minimum: const EdgeInsets.fromLTRB(20, 8, 20, 10),
      child: Center(heightFactor: 1, child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: SizedBox(width: double.infinity, child: Row(children: [
          for (final (index, child) in children.indexed) ...[
            if (index > 0) const SizedBox(width: 10),
            Expanded(child: child),
          ],
        ])),
      )),
    ),
    );
  }
}

class KitchenTimelineEntry extends StatelessWidget {
  const KitchenTimelineEntry({super.key, required this.at, required this.title,
    this.detail, this.starter = false, this.last = false, this.done = false, this.onTap});
  final DateTime at;
  final String title;
  final String? detail;
  final bool starter, last, done;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final local = at.toLocal();
    final now = DateTime.now();
    final l10n = MaterialLocalizations.of(context);
    final time = l10n.formatTimeOfDay(TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context));
    final color = starter
      ? (theme.brightness == Brightness.dark ? const Color(0xfff0bb91) : const Color(0xff92482a))
      : colors.primary;
    return Stack(children: [
      if (!last)
        Positioned(left: 9, top: 20, bottom: -1, width: 2,
          child: ColoredBox(color: colors.outlineVariant)),
      Positioned(left: 2, top: 13, child: Icon(
        done ? Icons.check_circle : starter ? Icons.water_drop : Icons.circle,
        size: 16, color: color,
      )),
      Padding(padding: const EdgeInsets.only(left: 29, bottom: 10), child: ListTile(
        dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 5),
        title: Text(title), trailing: onTap == null ? null : const Icon(Icons.chevron_right),
        subtitle: Text([
          if (now.year != local.year || now.month != local.month || now.day != local.day)
            l10n.formatShortMonthDay(local),
          time, if (detail != null && detail!.isNotEmpty) detail!,
        ].join(' · ')),
        onTap: onTap,
      )),
    ]);
  }
}

class KitchenInfo extends StatelessWidget {
  const KitchenInfo({super.key, required this.title, required this.text});
  final String title, text;

  @override
  Widget build(BuildContext context) => IconButton(
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    icon: const Icon(Icons.info_outline),
    tooltip: title,
    onPressed: () => showModalBottomSheet<void>(context: context, showDragHandle: true,
      isScrollControlled: true, builder: (sheet) => SafeArea(
        child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(sheet).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(text),
            const SizedBox(height: 12),
            TextButton(onPressed: () => Navigator.pop(sheet), child: const Text('Done')),
          ])))),
  );
}

class CrumbArt extends StatelessWidget {
  const CrumbArt({super.key, this.size = 72});
  final double size;
  @override
  Widget build(BuildContext context) => Image.asset('assets/editorial/crumb.webp',
    width: size, height: size, fit: BoxFit.contain, excludeFromSemantics: true);
}

class KitchenPage extends StatelessWidget {
  const KitchenPage({super.key, required this.children, this.scrollKey});

  final List<Widget> children;
  final Key? scrollKey;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: ListView(
        key: scrollKey,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: children,
      ),
    ),
  );
}

enum KitchenArtwork {
  bread('country-loaf'),
  starter('starter-jar'),
  flatbread('flatbread'),
  pastry('enriched-dough');

  const KitchenArtwork(this.file);
  final String file;

  static KitchenArtwork forRecipe(String family) => switch (family) {
    'focaccia' || 'pizza' => flatbread,
    'enriched' || 'bagels' || 'discard' => pastry,
    _ => bread,
  };
}

/// Editorial images are decorative and depict a style of baking. User photos
/// and actual recipe results use their own accessible labels.
class KitchenPhoto extends StatelessWidget {
  const KitchenPhoto(this.artwork, {super.key, this.fit = BoxFit.cover});
  final KitchenArtwork artwork;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/editorial/${artwork.file}.webp',
    fit: fit,
    width: double.infinity,
    height: double.infinity,
    excludeFromSemantics: true,
  );
}

class KitchenHeading extends StatelessWidget {
  const KitchenHeading(this.title, {super.key, this.detail});
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: theme.textTheme.displaySmall),
          ),
          if (detail != null) ...[
            const SizedBox(height: 4),
            Text(
              detail!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class KitchenFeature extends StatelessWidget {
  const KitchenFeature({
    super.key,
    required this.artwork,
    required this.title,
    required this.detail,
    this.actions = const [],
  });

  final KitchenArtwork artwork;
  final String title;
  final String detail;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(aspectRatio: 2.1, child: KitchenPhoto(artwork)),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(title, style: theme.textTheme.headlineSmall),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Wrap(spacing: 8, runSpacing: 8, children: actions),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class KitchenBrandMark extends StatelessWidget {
  const KitchenBrandMark({super.key, this.size = 32});
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * .26),
    child: Image.asset(
      'assets/editorial/loaf-mark.png',
      width: size,
      height: size,
      excludeFromSemantics: true,
    ),
  );
}
