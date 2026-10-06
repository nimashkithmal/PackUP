import "package:flutter/material.dart";
import "package:intl/intl.dart";
import "package:uuid/uuid.dart";

import "../models/trip.dart";
import "../services/api_service.dart";
import "../services/auth_service.dart";
import "../services/trip_repository.dart";
import "../theme.dart";
import "generating_screen.dart";

class CreateTripScreen extends StatefulWidget {
  const CreateTripScreen({super.key, required this.auth, required this.repo, this.existing});
  final AuthService auth;
  final TripRepository repo;

  /// When set, the screen edits this trip instead of creating a new one.
  final Trip? existing;

  @override
  State<CreateTripScreen> createState() => _CreateTripScreenState();
}

class _CreateTripScreenState extends State<CreateTripScreen> {
  final destination = TextEditingController(text: "Ella");
  DateTime start = DateTime.now().add(const Duration(days: 1));
  DateTime end = DateTime.now().add(const Duration(days: 3));
  int people = 2;
  final activities = <String>{"hiking"};
  String preference = "normal";
  List<String> options = defaultActivities;
  bool saving = false;

  bool get editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final trip = widget.existing;
    if (trip != null) {
      destination.text = trip.destination;
      start = trip.startDate;
      end = trip.endDate;
      people = trip.people;
      activities
        ..clear()
        ..addAll(trip.activities);
      preference = trip.preference;
    } else {
      widget.repo.preference().then((value) {
        if (value != null && mounted) setState(() => preference = value);
      }).catchError((_) {});
    }
    widget.auth.api.activities().then((value) {
      if (value.isNotEmpty && mounted) setState(() => options = value);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    destination.dispose();
    super.dispose();
  }

  Future<void> _pickDates() async {
    final today = DateTime.now();
    final first = start.isBefore(today) ? start : today;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(first.year, first.month, first.day),
      lastDate: today.add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: start, end: end),
      helpText: "Trip dates",
    );
    if (picked == null) return;
    setState(() {
      start = picked.start;
      end = picked.end;
    });
  }

  Future<void> _continue() async {
    if (destination.text.trim().isEmpty || activities.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter a destination and at least one activity.")),
      );
      return;
    }
    final existing = widget.existing;
    if (existing != null) {
      await _saveEdit(existing);
      return;
    }
    final trip = Trip(
      id: const Uuid().v4(),
      destination: destination.text.trim(),
      startDate: start,
      endDate: end,
      people: people,
      activities: activities.toList(),
      preference: preference,
    );
    if (!await _save(trip)) return;
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => GeneratingScreen(auth: widget.auth, repo: widget.repo, trip: trip),
      ),
    );
  }

  Future<void> _saveEdit(Trip trip) async {
    final listChanged = trip.destination != destination.text.trim() ||
        !_sameDay(trip.startDate, start) ||
        !_sameDay(trip.endDate, end) ||
        trip.people != people ||
        trip.preference != preference ||
        !(trip.activities.toSet().containsAll(activities) && activities.containsAll(trip.activities));
    trip
      ..destination = destination.text.trim()
      ..startDate = start
      ..endDate = end
      ..people = people
      ..activities = activities.toList()
      ..preference = preference;
    if (!listChanged) {
      if (await _save(trip) && mounted) Navigator.of(context).pop();
      return;
    }
    // Rebuild the list for the new details; GeneratingScreen keeps statuses and custom items.
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => GeneratingScreen(
          auth: widget.auth,
          repo: widget.repo,
          trip: trip,
          previousItems: List.of(trip.items),
        ),
      ),
    );
  }

  Future<bool> _save(Trip trip) async {
    setState(() => saving = true);
    try {
      await widget.repo.saveTrip(trip);
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
      return false;
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  int get _days => DateTime(end.year, end.month, end.day).difference(DateTime(start.year, start.month, start.day)).inDays + 1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fmt = DateFormat("EEE, MMM d");
    return Scaffold(
      appBar: AppBar(title: Text(editing ? "Edit trip" : "Plan a trip")),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionLabel("Where"),
                TextField(
                  controller: destination,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: "Destination",
                    hintText: "e.g. Ella, Galle, Kandy",
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                ),
                const SizedBox(height: 24),
                const SectionLabel("When"),
                Card(
                  child: InkWell(
                    onTap: _pickDates,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(child: _DateBlock(label: "From", value: fmt.format(start))),
                          Icon(Icons.arrow_forward, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 16),
                          Expanded(child: _DateBlock(label: "To", value: fmt.format(end))),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              "$_days day${_days == 1 ? "" : "s"}",
                              style: theme.textTheme.labelLarge?.copyWith(color: scheme.onPrimaryContainer),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const SectionLabel("Who"),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.group_outlined, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 12),
                        Expanded(child: Text("Travellers", style: theme.textTheme.titleMedium)),
                        IconButton.filledTonal(
                          tooltip: "Fewer people",
                          onPressed: people > 1 ? () => setState(() => people--) : null,
                          icon: const Icon(Icons.remove),
                        ),
                        SizedBox(
                          width: 44,
                          child: Text("$people", textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
                        ),
                        IconButton.filledTonal(
                          tooltip: "More people",
                          onPressed: people < 20 ? () => setState(() => people++) : null,
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const SectionLabel("What you'll do"),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: options
                      .map(
                        (a) => FilterChip(
                          avatar: Icon(activityIcon(a), size: 18),
                          label: Text(titleCase(a)),
                          showCheckmark: false,
                          selected: activities.contains(a),
                          onSelected: (on) => setState(() => on ? activities.add(a) : activities.remove(a)),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 24),
                const SectionLabel("Packing style"),
                for (final (value, title, body, icon) in const [
                  ("minimal", "Minimal", "Travel light, re-wear and wash", Icons.backpack_outlined),
                  ("normal", "Normal", "One of each per day", Icons.luggage_outlined),
                  ("prepared", "Prepared", "Extra spares, just in case", Icons.inventory_2_outlined),
                ]) ...[
                  _ChoiceCard(
                    selected: preference == value,
                    icon: icon,
                    title: title,
                    body: body,
                    onTap: () => setState(() => preference = value),
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: saving ? null : _continue,
                  icon: Icon(editing ? Icons.check : Icons.auto_awesome),
                  label: Text(editing ? "Save changes" : "Build my packing list"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DateBlock extends StatelessWidget {
  const _DateBlock({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });
  final bool selected;
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.6), width: selected ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    Text(body, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: selected ? scheme.primary : scheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
