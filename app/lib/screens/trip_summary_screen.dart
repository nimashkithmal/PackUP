import "package:flutter/material.dart";

import "../models/trip.dart";
import "../services/auth_service.dart";
import "../services/trip_repository.dart";
import "../theme.dart";

class TripSummaryScreen extends StatefulWidget {
  const TripSummaryScreen({super.key, required this.auth, required this.repo, required this.trip});
  final AuthService auth;
  final TripRepository repo;
  final Trip trip;

  @override
  State<TripSummaryScreen> createState() => _TripSummaryScreenState();
}

class _TripSummaryScreenState extends State<TripSummaryScreen> {
  int rating = 4;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    rating = widget.trip.rating ?? rating;
  }

  Future<void> _save() async {
    setState(() => saving = true);
    widget.trip.rating = rating;
    widget.trip.status = "completed";
    try {
      await widget.repo.saveTrip(widget.trip);
      await widget.auth.api.sendFeedback(widget.trip);
    } catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Could not save feedback: $e")));
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Thanks! Feedback saved.")));
    Navigator.of(context).pop();
  }

  static const _labels = ["", "Not useful", "Could be better", "Okay", "Good", "Spot on!"];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final items = widget.trip.items;
    final packed = items.where((e) => e.status == "packed").length;
    final buy = items.where((e) => e.status == "need_to_buy").length;
    final skip = items.where((e) => e.status == "not_required").length;
    final pending = items.where((e) => e.status == "pending").length;
    return Scaffold(
      appBar: AppBar(title: const Text("Trip summary")),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.trip.destination, style: theme.textTheme.headlineSmall),
                Text(
                  "${widget.trip.duration} days · ${items.length} items",
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.9,
                  children: [
                    _Stat(icon: Icons.check_circle_outline, label: "Packed", value: packed, color: scheme.primary),
                    _Stat(icon: Icons.shopping_cart_outlined, label: "Need to buy", value: buy, color: scheme.tertiary),
                    _Stat(icon: Icons.do_not_disturb_on_outlined, label: "Not needed", value: skip, color: scheme.outline),
                    _Stat(icon: Icons.radio_button_unchecked, label: "Still to pack", value: pending, color: scheme.secondary),
                  ],
                ),
                const SizedBox(height: 28),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Text("How useful was this list?", style: theme.textTheme.titleMedium),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var star = 1; star <= 5; star++)
                              IconButton(
                                tooltip: "$star star${star == 1 ? "" : "s"}",
                                iconSize: 36,
                                onPressed: () => setState(() => rating = star),
                                icon: Icon(
                                  star <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
                                  color: star <= rating ? Colors.amber.shade600 : scheme.outline,
                                ),
                              ),
                          ],
                        ),
                        Text(_labels[rating], style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "Your ratings and what you packed help PackUP make better lists for everyone.",
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: saving ? null : _save,
                  icon: const Icon(Icons.send_outlined),
                  label: const Text("Save feedback"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value, required this.color});
  final IconData icon;
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: color),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text("$value", style: theme.textTheme.headlineSmall),
                const SizedBox(width: 6),
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
