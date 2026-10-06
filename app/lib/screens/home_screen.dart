import "package:flutter/material.dart";
import "package:intl/intl.dart";

import "../models/trip.dart";
import "../services/auth_service.dart";
import "../services/trip_repository.dart";
import "create_trip_screen.dart";
import "packing_list_screen.dart";
import "profile_screen.dart";

/// Trips starting within this many days get a reminder banner.
const reminderDays = 3;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.auth});
  final AuthService auth;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final TripRepository repo;
  List<Trip> trips = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    repo = TripRepository(widget.auth);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await repo.listTrips();
      if (!mounted) return;
      setState(() {
        trips = data;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  Future<void> _open(Trip trip) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PackingListScreen(auth: widget.auth, repo: repo, trip: trip)),
    );
    _load();
  }

  Future<void> _edit(Trip trip) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CreateTripScreen(auth: widget.auth, repo: repo, existing: trip)),
    );
    _load();
  }

  Future<void> _delete(Trip trip) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete trip?"),
        content: Text("${trip.destination} and its packing list will be removed."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text("Delete")),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await repo.deleteTrip(trip);
      if (!mounted) return;
      setState(() => trips.remove(trip));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Deleted ${trip.destination}")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  List<Trip> get _upcoming => trips
      .where((t) => t.status != "completed" && t.daysUntilStart >= 0 && t.daysUntilStart <= reminderDays)
      .toList()
    ..sort((a, b) => a.startDate.compareTo(b.startDate));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Your trips"),
        actions: [
          IconButton(
            tooltip: "Profile",
            icon: const Icon(Icons.person_outline),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ProfileScreen(auth: widget.auth, repo: repo)),
              );
            },
          ),
        ],
      ),
      body: _body(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => CreateTripScreen(auth: widget.auth, repo: repo)),
          );
          _load();
        },
        label: const Text("New trip"),
        icon: const Icon(Icons.add),
      ),
    );
  }

  Widget _body() {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text("Retry")),
            ],
          ),
        ),
      );
    }
    if (trips.isEmpty) {
      return const Center(child: Text("No trips yet. Tap New trip to start."));
    }
    final upcoming = _upcoming;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          for (final trip in upcoming) _ReminderCard(trip: trip, onTap: () => _open(trip)),
          for (final trip in trips)
            Card(
              child: ListTile(
                title: Text(trip.destination),
                subtitle: Text(
                  "${DateFormat.MMMd().format(trip.startDate)} · ${trip.duration} days · ${trip.people} people",
                ),
                onTap: () => _open(trip),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(trip.status),
                    PopupMenuButton<String>(
                      tooltip: "Trip options",
                      onSelected: (v) => v == "edit" ? _edit(trip) : _delete(trip),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: "edit", child: Text("Edit trip")),
                        PopupMenuItem(value: "delete", child: Text("Delete trip")),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({required this.trip, required this.onTap});
  final Trip trip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final days = trip.daysUntilStart;
    final when = days == 0 ? "today" : days == 1 ? "tomorrow" : "in $days days";
    final pending = trip.pendingCount;
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.tertiaryContainer,
      child: ListTile(
        leading: Icon(Icons.notifications_active_outlined, color: colors.onTertiaryContainer),
        title: Text("${trip.destination} trip starts $when"),
        subtitle: Text(
          pending == 0 ? "Everything is checked off." : "$pending item${pending == 1 ? "" : "s"} still to pack.",
        ),
        onTap: onTap,
      ),
    );
  }
}
