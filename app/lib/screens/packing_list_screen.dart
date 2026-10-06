import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:share_plus/share_plus.dart";

import "../models/trip.dart";
import "../services/auth_service.dart";
import "../services/trip_repository.dart";
import "../theme.dart";
import "trip_summary_screen.dart";

const categoryLabels = {
  "clothing": "Clothing",
  "footwear": "Footwear",
  "personal": "Personal items",
  "health": "Health / first aid",
  "electronics": "Electronics",
  "documents": "Documents",
  "food": "Food",
  "activity": "Activity-specific",
};

const statuses = ["pending", "packed", "need_to_buy", "not_required"];

enum _Filter { all, toPack, packed, toBuy }

class PackingListScreen extends StatefulWidget {
  const PackingListScreen({super.key, required this.auth, required this.repo, required this.trip});
  final AuthService auth;
  final TripRepository repo;
  final Trip trip;

  @override
  State<PackingListScreen> createState() => _PackingListScreenState();
}

class _PackingListScreenState extends State<PackingListScreen> {
  late Trip trip;
  _Filter filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    trip = widget.trip;
  }

  void _toast(String message, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }

  Future<void> _persist({List<PackingItem>? feedbackItems}) async {
    try {
      await widget.repo.saveTrip(trip);
    } catch (e) {
      if (mounted) _toast("Could not save: $e");
      return;
    }
    if (feedbackItems != null && feedbackItems.isEmpty) return;
    try {
      await widget.auth.api.sendFeedback(trip, items: feedbackItems, includeRating: false);
    } catch (_) {
      // Feedback is training data only; the trip itself is already saved.
    }
  }

  Future<void> _setStatus(PackingItem item, String status) async {
    setState(() => item.status = status);
    await _persist();
  }

  Future<void> _delete(PackingItem item) async {
    final index = trip.items.indexOf(item);
    final previousStatus = item.status;
    setState(() => trip.items = [...trip.items]..remove(item));
    // Removing a recommended item tells the model it was not needed.
    if (!item.custom) item.status = "not_required";
    await _persist(feedbackItems: item.custom ? const [] : [item]);
    if (!mounted) return;
    _toast(
      "Removed ${item.name}",
      action: SnackBarAction(
        label: "Undo",
        onPressed: () async {
          item.status = previousStatus;
          setState(() => trip.items = [...trip.items]..insert(index.clamp(0, trip.items.length), item));
          await _persist(feedbackItems: item.custom ? const [] : [item]);
        },
      ),
    );
  }

  Future<void> _add() async {
    final item = await showDialog<PackingItem>(context: context, builder: (_) => const _AddItemDialog());
    if (item == null) return;
    setState(() => trip.items = [...trip.items, item]);
    await _persist(feedbackItems: const []);
  }

  String _shareText() {
    final b = StringBuffer()
      ..writeln("PackUP list: ${trip.destination}")
      ..writeln("${trip.duration} days · ${trip.people} people");
    final w = trip.weather;
    if (w != null) {
      b.writeln("${w.avgTempC.toStringAsFixed(0)}°C · rain ${w.precipProbability.toStringAsFixed(0)}%");
    }
    for (final category in categoryLabels.keys) {
      final items = trip.items.where((i) => i.category == category && i.status != "not_required").toList();
      if (items.isEmpty) continue;
      b
        ..writeln()
        ..writeln(categoryLabels[category]);
      for (final i in items) {
        final mark = i.status == "packed" ? "✅" : i.status == "need_to_buy" ? "🛒" : "⬜";
        b.writeln("$mark ${i.name} ×${i.quantity}");
      }
    }
    return b.toString();
  }

  Future<void> _share() async {
    final text = _shareText();
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text("Share"),
              subtitle: const Text("WhatsApp, email, messages…"),
              onTap: () => Navigator.pop(context, "share"),
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text("Copy as text"),
              onTap: () => Navigator.pop(context, "copy"),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == "copy") {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) _toast("Packing list copied");
    } else if (choice == "share") {
      await SharePlus.instance.share(ShareParams(text: text, subject: "PackUP list: ${trip.destination}"));
    }
  }

  bool _matches(PackingItem i) => switch (filter) {
        _Filter.all => true,
        _Filter.toPack => i.status == "pending",
        _Filter.packed => i.status == "packed",
        _Filter.toBuy => i.status == "need_to_buy",
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counted = trip.items.where((i) => i.status != "not_required").toList();
    final packed = counted.where((i) => i.status == "packed").length;
    final toBuy = trip.items.where((i) => i.status == "need_to_buy").length;
    final pending = trip.items.where((i) => i.status == "pending").length;

    final grouped = <String, List<PackingItem>>{};
    for (final item in trip.items.where(_matches)) {
      grouped.putIfAbsent(item.category, () => []).add(item);
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 228,
            foregroundColor: Colors.white,
            backgroundColor: destinationGradient(trip.destination, theme.colorScheme).colors.last,
            titleTextStyle: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
            title: Text(trip.destination, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(tooltip: "Share list", icon: const Icon(Icons.ios_share), onPressed: _share),
              IconButton(
                tooltip: "Trip summary",
                icon: const Icon(Icons.fact_check_outlined),
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TripSummaryScreen(auth: widget.auth, repo: widget.repo, trip: trip),
                    ),
                  );
                  if (mounted) setState(() {});
                },
              ),
            ],
            flexibleSpace: LayoutBuilder(
              builder: (context, box) {
                // 1 when fully expanded, 0 when collapsed to the toolbar: fade the details out.
                final collapsed = MediaQuery.paddingOf(context).top + kToolbarHeight;
                final t = ((box.maxHeight - collapsed) / (228 - kToolbarHeight)).clamp(0.0, 1.0);
                return DecoratedBox(
                  decoration: BoxDecoration(gradient: destinationGradient(trip.destination, theme.colorScheme)),
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.bottomCenter,
                      minHeight: 0,
                      maxHeight: double.infinity,
                      child: Opacity(
                        opacity: Curves.easeIn.transform(t),
                        child: _Header(trip: trip, packed: packed, total: counted.length),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SliverToBoxAdapter(
            child: ContentWidth(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (trip.weather?.source == "climate") ...[
                      _Note(
                        icon: Icons.history,
                        text: "Too far ahead for a forecast — weather is estimated from the same dates in past years.",
                      ),
                      const SizedBox(height: 12),
                    ],
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final (f, label) in [
                            (_Filter.all, "All ${trip.items.length}"),
                            (_Filter.toPack, "To pack $pending"),
                            (_Filter.packed, "Packed $packed"),
                            (_Filter.toBuy, "To buy $toBuy"),
                          ]) ...[
                            ChoiceChip(
                              label: Text(label),
                              selected: filter == f,
                              showCheckmark: false,
                              onSelected: (_) => setState(() => filter = f),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (grouped.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    filter == _Filter.toPack ? "All packed — nice work! 🎉" : "Nothing here yet.",
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
            ),
          for (final category in categoryLabels.keys)
            if (grouped[category] != null)
              SliverToBoxAdapter(
                child: ContentWidth(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: _CategorySection(
                      category: category,
                      items: grouped[category]!,
                      onStatus: _setStatus,
                      onDelete: _delete,
                    ),
                  ),
                ),
              ),
          const SliverToBoxAdapter(child: SizedBox(height: 112)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text("Add item"),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.trip, required this.packed, required this.total});
  final Trip trip;
  final int packed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final w = trip.weather;
    const white = Colors.white;
    final dim = Colors.white.withValues(alpha: 0.85);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      child: ContentWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (w != null)
              Text(w.placeName, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(color: dim)),
            const SizedBox(height: 10),
            Row(
              children: [
                if (w != null) ...[
                  Icon(weatherIcon(w.tags), color: white, size: 34),
                  const SizedBox(width: 10),
                  Text("${w.avgTempC.toStringAsFixed(0)}°C", style: theme.textTheme.headlineMedium?.copyWith(color: white)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Rain ${w.precipProbability.toStringAsFixed(0)}%", style: theme.textTheme.labelLarge?.copyWith(color: white)),
                        Text(
                          "${w.minTempC.toStringAsFixed(0)}° – ${w.maxTempC.toStringAsFixed(0)}°",
                          style: theme.textTheme.bodySmall?.copyWith(color: dim),
                        ),
                      ],
                    ),
                  ),
                ] else
                  const Spacer(),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              "${trip.duration} days · ${trip.people} ${trip.people == 1 ? "person" : "people"} · ${titleCase(trip.preference)}",
              style: theme.textTheme.bodySmall?.copyWith(color: dim),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : packed / total,
                      minHeight: 8,
                      color: white,
                      backgroundColor: Colors.white.withValues(alpha: 0.25),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text("$packed/$total packed", style: theme.textTheme.labelLarge?.copyWith(color: white)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: scheme.onSecondaryContainer))),
        ],
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.category,
    required this.items,
    required this.onStatus,
    required this.onDelete,
  });
  final String category;
  final List<PackingItem> items;
  final Future<void> Function(PackingItem, String) onStatus;
  final Future<void> Function(PackingItem) onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = items.where((i) => i.status == "packed").length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4),
          child: Row(
            children: [
              Icon(categoryIcon(category), size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(categoryLabels[category]!, style: theme.textTheme.titleMedium)),
              Text("$done/${items.length}", style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
        Card(
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const Divider(indent: 56),
                _ItemRow(
                  key: ValueKey(items[i].slug),
                  item: items[i],
                  onStatus: onStatus,
                  onDelete: onDelete,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({super.key, required this.item, required this.onStatus, required this.onDelete});
  final PackingItem item;
  final Future<void> Function(PackingItem, String) onStatus;
  final Future<void> Function(PackingItem) onDelete;

  String _sourceLabel(String s) {
    final parts = s.split(":");
    return parts.length == 2 ? titleCase(parts[1]) : s;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final packed = item.status == "packed";
    final skipped = item.status == "not_required";
    final toBuy = item.status == "need_to_buy";
    final pct = (item.confidence * 100).round();
    final faded = packed || skipped;

    return Dismissible(
      key: ValueKey("dismiss-${item.slug}"),
      direction: DismissDirection.endToStart,
      background: Container(
        color: scheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      onDismissed: (_) => onDelete(item),
      child: InkWell(
        onTap: () => onStatus(item, packed ? "pending" : "packed"),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 0, 6),
          child: Row(
            children: [
              Checkbox(
                value: packed,
                onChanged: (v) => onStatus(item, v == true ? "packed" : "pending"),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.name,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              decoration: faded ? TextDecoration.lineThrough : null,
                              color: faded ? scheme.onSurfaceVariant : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text("×${item.quantity}", style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (toBuy) _Tag(text: "To buy", color: scheme.tertiaryContainer, onColor: scheme.onTertiaryContainer),
                        if (skipped) _Tag(text: "Not needed", color: scheme.surfaceContainerHighest, onColor: scheme.onSurfaceVariant),
                        if (item.isSafety) _Tag(text: "Essential", color: scheme.errorContainer, onColor: scheme.onErrorContainer),
                        if (item.suggested) _Tag(text: "Optional", color: scheme.secondaryContainer, onColor: scheme.onSecondaryContainer),
                        Text(
                          item.sources.map(_sourceLabel).join(" · "),
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!item.custom) _Confidence(pct: pct),
              PopupMenuButton<String>(
                tooltip: "More options",
                onSelected: (v) => v == "delete" ? onDelete(item) : onStatus(item, v),
                itemBuilder: (_) => [
                  for (final (value, label, icon) in const [
                    ("pending", "To pack", Icons.radio_button_unchecked),
                    ("packed", "Packed", Icons.check_circle_outline),
                    ("need_to_buy", "Need to buy", Icons.shopping_cart_outlined),
                    ("not_required", "Not needed", Icons.do_not_disturb_on_outlined),
                  ])
                    CheckedPopupMenuItem(value: value, checked: item.status == value, child: Row(
                      children: [Icon(icon, size: 20), const SizedBox(width: 12), Text(label)],
                    )),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: "delete",
                    child: Row(children: [Icon(Icons.delete_outline, size: 20), SizedBox(width: 12), Text("Remove")]),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Confidence extends StatelessWidget {
  const _Confidence({required this.pct});
  final int pct;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = pct >= 80 ? scheme.primary : pct >= 62 ? scheme.tertiary : scheme.outline;
    return Tooltip(
      message: "$pct% of similar travellers pack this",
      child: SizedBox(
        width: 40,
        height: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: pct / 100,
              strokeWidth: 3,
              color: color,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
            Text("$pct", style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color, required this.onColor});
  final String text;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: onColor, fontWeight: FontWeight.w600)),
    );
  }
}

class _AddItemDialog extends StatefulWidget {
  const _AddItemDialog();

  @override
  State<_AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<_AddItemDialog> {
  final name = TextEditingController();
  String category = "personal";
  int quantity = 1;
  String? error;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  void _submit() {
    final value = name.text.trim();
    if (value.isEmpty) {
      setState(() => error = "Enter an item name.");
      return;
    }
    Navigator.pop(context, PackingItem.custom(name: value, category: category, quantity: quantity));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.add_task),
      title: const Text("Add item"),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: "Item", errorText: error),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: const InputDecoration(labelText: "Category"),
              items: categoryLabels.entries
                  .map((e) => DropdownMenuItem(
                        value: e.key,
                        child: Row(children: [Icon(categoryIcon(e.key), size: 18), const SizedBox(width: 10), Text(e.value)]),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => category = v ?? category),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text("Quantity"),
                const Spacer(),
                IconButton.filledTonal(
                  tooltip: "Fewer",
                  onPressed: quantity > 1 ? () => setState(() => quantity--) : null,
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(width: 40, child: Text("$quantity", textAlign: TextAlign.center)),
                IconButton.filledTonal(
                  tooltip: "More",
                  onPressed: quantity < 99 ? () => setState(() => quantity++) : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
        TextButton(onPressed: _submit, child: const Text("Add")),
      ],
    );
  }
}
