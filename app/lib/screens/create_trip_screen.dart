import "package:flutter/material.dart";
import "package:uuid/uuid.dart";

import "../models/trip.dart";
import "../services/api_service.dart";
import "../services/auth_service.dart";
import "../services/trip_repository.dart";
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

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? start : end;
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: initial.isBefore(today) ? initial : today,
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        start = picked;
        if (end.isBefore(start)) end = start;
      } else {
        end = picked.isBefore(start) ? start : picked;
      }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(editing ? "Edit trip" : "New trip")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: destination,
            decoration: const InputDecoration(labelText: "Destination"),
          ),
          const SizedBox(height: 16),
          ListTile(
            title: const Text("Start date"),
            subtitle: Text(start.toIso8601String().split("T").first),
            onTap: () => _pickDate(isStart: true),
          ),
          ListTile(
            title: const Text("End date"),
            subtitle: Text(end.toIso8601String().split("T").first),
            onTap: () => _pickDate(isStart: false),
          ),
          const SizedBox(height: 8),
          Text("People: $people"),
          Slider(
            min: 1,
            max: 8,
            divisions: 7,
            value: people.toDouble(),
            label: "$people",
            onChanged: (v) => setState(() => people = v.round()),
          ),
          const Text("Activities"),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: options
                .map(
                  (a) => FilterChip(
                    label: Text(a),
                    selected: activities.contains(a),
                    onSelected: (on) {
                      setState(() {
                        if (on) {
                          activities.add(a);
                        } else {
                          activities.remove(a);
                        }
                      });
                    },
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          const Text("Packing preference"),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: "minimal", label: Text("Minimal")),
              ButtonSegment(value: "normal", label: Text("Normal")),
              ButtonSegment(value: "prepared", label: Text("Prepared")),
            ],
            selected: {preference},
            onSelectionChanged: (s) => setState(() => preference = s.first),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: saving ? null : _continue,
            child: Text(editing ? "Save changes" : "Generate packing list"),
          ),
        ],
      ),
    );
  }
}
