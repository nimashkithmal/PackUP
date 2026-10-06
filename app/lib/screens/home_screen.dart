import "package:flutter/material.dart";
import "package:intl/intl.dart";

import "../main.dart" show routeObserver;
import "../models/trip.dart";
import "../services/auth_service.dart";
import "../services/trip_repository.dart";
import "../theme.dart";
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

class _HomeScreenState extends State<HomeScreen> with RouteAware {
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) routeObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  /// Back on this screen (after a trip was created, edited or packed): show fresh data.
  @override
  void didPopNext() => _load(silent: true);

  Future<void> _load({bool silent = false}) async {
    if (!silent || trips.isEmpty) {
      setState(() {
        loading = true;
        error = null;
      });
    }
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
  }

  Future<void> _create() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CreateTripScreen(auth: widget.auth, repo: repo)),
    );
  }

  Future<void> _edit(Trip trip) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CreateTripScreen(auth: widget.auth, repo: repo, existing: trip)),
    );
  }

  Future<void> _delete(Trip trip) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: const Text("Delete trip?"),
        content: Text("${trip.destination} and its packing list will be removed."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Delete")),
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

  String get _firstName {
    final name = widget.auth.current?.email.split("@").first ?? "";
    final word = name.split(RegExp(r"[._\-+0-9]")).firstWhere((w) => w.isNotEmpty, orElse: () => "");
    return word.isEmpty ? "traveller" : titleCase(word);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final email = widget.auth.current?.email ?? "";
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          children: [
            Icon(Icons.luggage_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Text("PackUP"),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton(
              tooltip: "Profile",
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ProfileScreen(auth: widget.auth, repo: repo)),
                );
              },
              icon: CircleAvatar(
                radius: 16,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  email.isEmpty ? "?" : email[0].toUpperCase(),
                  style: TextStyle(color: theme.colorScheme.onPrimaryContainer, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _body(theme),
      floatingActionButton: trips.isEmpty && !loading
          ? null
          : FloatingActionButton.extended(
              onPressed: _create,
              label: const Text("New trip"),
              icon: const Icon(Icons.add),
            ),
    );
  }

  Widget _body(ThemeData theme) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return _Message(
        icon: Icons.cloud_off_outlined,
        title: "Couldn't load your trips",
        body: error!,
        action: FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text("Retry")),
      );
    }
    if (trips.isEmpty) {
      return _Message(
        icon: Icons.travel_explore,
        title: "Where to next, $_firstName?",
        body: "Add a trip and PackUP builds a packing list from the weather and your plans.",
        action: FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add), label: const Text("Plan a trip")),
      );
    }
    final upcoming = _upcoming;
    final active = trips.where((t) => t.status != "completed").toList();
    final done = trips.where((t) => t.status == "completed").toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 112),
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text("Hi $_firstName 👋", style: theme.textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  "${trips.length} trip${trips.length == 1 ? "" : "s"} planned",
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                for (final trip in upcoming) ...[
                  _ReminderCard(trip: trip, onTap: () => _open(trip)),
                  const SizedBox(height: 12),
                ],
                if (active.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const SectionLabel("Your trips"),
                  for (final trip in active) ...[
                    _TripCard(trip: trip, onTap: () => _open(trip), onEdit: () => _edit(trip), onDelete: () => _delete(trip)),
                    const SizedBox(height: 14),
                  ],
                ],
                if (done.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const SectionLabel("Completed"),
                  for (final trip in done) ...[
                    _TripCard(trip: trip, onTap: () => _open(trip), onEdit: () => _edit(trip), onDelete: () => _delete(trip)),
                    const SizedBox(height: 14),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body, required this.action});
  final IconData icon;
  final String title;
  final String body;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, shape: BoxShape.circle),
                child: Icon(icon, size: 48, color: theme.colorScheme.onPrimaryContainer),
              ),
              const SizedBox(height: 24),
              Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              action,
            ],
          ),
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip, required this.onTap, required this.onEdit, required this.onDelete});
  final Trip trip;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  String get _dates {
    final start = DateFormat.MMMd().format(trip.startDate);
    final end = trip.duration == 1 ? "" : " – ${DateFormat.MMMd().format(trip.endDate)}";
    return "$start$end";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final counted = trip.items.where((i) => i.status != "not_required").toList();
    final packed = counted.where((i) => i.status == "packed").length;
    final progress = counted.isEmpty ? 0.0 : packed / counted.length;
    final weather = trip.weather;
    final days = trip.daysUntilStart;
    final badge = trip.status == "completed"
        ? "Completed"
        : days > 1
            ? "In $days days"
            : days == 1
                ? "Tomorrow"
                : days == 0
                    ? "Today"
                    : "Ongoing";

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 110,
              padding: const EdgeInsets.fromLTRB(18, 12, 6, 14),
              decoration: BoxDecoration(gradient: destinationGradient(trip.destination, scheme)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          badge,
                          style: theme.textTheme.labelMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const Spacer(),
                      if (weather != null) ...[
                        Icon(weatherIcon(weather.tags), color: Colors.white, size: 18),
                        const SizedBox(width: 4),
                        Text(
                          "${weather.avgTempC.toStringAsFixed(0)}°",
                          style: theme.textTheme.labelLarge?.copyWith(color: Colors.white),
                        ),
                      ],
                      PopupMenuButton<String>(
                        tooltip: "Trip options",
                        iconColor: Colors.white,
                        onSelected: (v) => v == "edit" ? onEdit() : onDelete(),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: "edit",
                            child: ListTile(leading: Icon(Icons.edit_outlined), title: Text("Edit trip")),
                          ),
                          PopupMenuItem(
                            value: "delete",
                            child: ListTile(leading: Icon(Icons.delete_outline), title: Text("Delete trip")),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    trip.destination,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    children: [
                      _Meta(icon: Icons.calendar_today_outlined, text: _dates),
                      _Meta(icon: Icons.schedule, text: "${trip.duration} day${trip.duration == 1 ? "" : "s"}"),
                      _Meta(icon: Icons.group_outlined, text: "${trip.people}"),
                      for (final a in trip.activities.take(3)) _Meta(icon: activityIcon(a), text: titleCase(a)),
                    ],
                  ),
                  if (counted.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 8,
                              backgroundColor: scheme.surfaceContainerHighest,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text("$packed/${counted.length} packed", style: theme.textTheme.labelMedium),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color)),
      ],
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(Icons.notifications_active_outlined, color: colors.onTertiaryContainer),
        title: Text(
          "${trip.destination} starts $when",
          style: TextStyle(color: colors.onTertiaryContainer, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          trip.items.isEmpty
              ? "Open it to build your packing list."
              : pending == 0
                  ? "Everything is checked off."
                  : "$pending item${pending == 1 ? "" : "s"} still to pack.",
          style: TextStyle(color: colors.onTertiaryContainer),
        ),
        trailing: Icon(Icons.chevron_right, color: colors.onTertiaryContainer),
        onTap: onTap,
      ),
    );
  }
}
