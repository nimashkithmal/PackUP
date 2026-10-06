import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:share_plus/share_plus.dart";

import "../models/trip.dart";
import "../services/auth_service.dart";
import "../services/trip_repository.dart";
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
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text("Share (WhatsApp, email, …)"),
              onTap: () => Navigator.pop(context, "share"),
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text("Copy as text"),
              onTap: () => Navigator.pop(context, "copy"),
            ),
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

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<PackingItem>>{};
    for (final item in trip.items) {
      grouped.putIfAbsent(item.category, () => []).add(item);
    }
    final weather = trip.weather;
    return Scaffold(
      appBar: AppBar(
        title: Text(trip.destination, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(tooltip: "Share list", icon: const Icon(Icons.ios_share), onPressed: _share),
          IconButton(
            tooltip: "Trip summary",
            icon: const Icon(Icons.fact_check_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TripSummaryScreen(auth: widget.auth, repo: widget.repo, trip: trip),
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text("Add item"),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          if (weather != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(weather.placeName, style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      "${weather.avgTempC.toStringAsFixed(0)}°C · rain ${weather.precipProbability.toStringAsFixed(0)}% · ${weather.tags.join(", ")}",
                    ),
                    Text("${trip.duration} days · ${trip.people} people · ${trip.preference}"),
                    if (weather.source == "climate")
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          "Too far ahead for a forecast — estimated from the same dates in past years.",
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          for (final category in categoryLabels.keys)
            if (grouped[category] != null) ...[
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 8),
                child: Text(categoryLabels[category]!, style: Theme.of(context).textTheme.titleMedium),
              ),
              ...grouped[category]!.map(
                (item) => _ItemTile(
                  key: ValueKey(item.slug),
                  item: item,
                  onStatus: _setStatus,
                  onDelete: _delete,
                ),
              ),
            ],
        ],
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({super.key, required this.item, required this.onStatus, required this.onDelete});
  final PackingItem item;
  final Future<void> Function(PackingItem, String) onStatus;
  final Future<void> Function(PackingItem) onDelete;

  @override
  Widget build(BuildContext context) {
    final pct = (item.confidence * 100).round();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text("${item.name}  ×${item.quantity}")),
                if (!item.custom)
                  Tooltip(
                    message: "How likely travellers like you pack this",
                    child: Text("$pct%"),
                  ),
                IconButton(
                  tooltip: "Remove item",
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => onDelete(item),
                ),
              ],
            ),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                ...item.sources.map((s) => Chip(label: Text(s), visualDensity: VisualDensity.compact)),
                if (item.suggested) const Chip(label: Text("suggested")),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: statuses
                  .map(
                    (s) => ChoiceChip(
                      label: Text(s.replaceAll("_", " ")),
                      selected: item.status == s,
                      onSelected: (_) => onStatus(item, s),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
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
      title: const Text("Add item"),
      content: Column(
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
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) => setState(() => category = v ?? category),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text("Quantity"),
              const Spacer(),
              IconButton(
                tooltip: "Fewer",
                onPressed: quantity > 1 ? () => setState(() => quantity--) : null,
                icon: const Icon(Icons.remove),
              ),
              Text("$quantity"),
              IconButton(
                tooltip: "More",
                onPressed: quantity < 99 ? () => setState(() => quantity++) : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
        FilledButton(onPressed: _submit, child: const Text("Add")),
      ],
    );
  }
}
