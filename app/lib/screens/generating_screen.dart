import "package:flutter/material.dart";

import "../models/trip.dart";
import "../services/auth_service.dart";
import "../services/trip_repository.dart";
import "../theme.dart";
import "packing_list_screen.dart";

class GeneratingScreen extends StatefulWidget {
  const GeneratingScreen({
    super.key,
    required this.auth,
    required this.repo,
    required this.trip,
    this.previousItems = const [],
  });
  final AuthService auth;
  final TripRepository repo;
  final Trip trip;

  /// Items from before an edit: their statuses carry over and custom items are kept.
  final List<PackingItem> previousItems;

  @override
  State<GeneratingScreen> createState() => _GeneratingScreenState();
}

class _GeneratingScreenState extends State<GeneratingScreen> {
  String? error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => error = null);
    try {
      final result = await widget.auth.api.recommend(widget.trip);
      final before = {for (final i in widget.previousItems) i.itemId: i.status};
      for (final item in result.items) {
        final status = before[item.itemId];
        if (status != null) item.status = status;
      }
      widget.trip.listId = result.listId;
      widget.trip.weather = result.weather;
      widget.trip.items = [
        ...result.items,
        ...widget.previousItems.where((i) => i.custom),
      ];
      if (widget.trip.status == "draft") widget.trip.status = "ready";
      await widget.repo.saveTrip(widget.trip);
      if (before.isNotEmpty) {
        // The edit made a new server-side list; copy the carried-over statuses to it.
        widget.auth.api.sendFeedback(widget.trip, includeRating: false).catchError((_) {});
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PackingListScreen(
            auth: widget.auth,
            repo: widget.repo,
            trip: widget.trip,
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: destinationGradient(widget.trip.destination, scheme)),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: error == null ? _loading(theme) : _error(theme),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _loading(ThemeData theme) {
    const white = Colors.white;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 72,
          height: 72,
          child: CircularProgressIndicator(color: white, strokeWidth: 4),
        ),
        const SizedBox(height: 32),
        Text(
          "Packing for ${widget.trip.destination}",
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(color: white),
        ),
        const SizedBox(height: 20),
        for (final (icon, text) in const [
          (Icons.cloud_outlined, "Checking the weather"),
          (Icons.rule, "Applying activity rules"),
          (Icons.auto_awesome, "Scoring items with the model"),
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: white.withValues(alpha: 0.9)),
                const SizedBox(width: 8),
                Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: white.withValues(alpha: 0.9))),
              ],
            ),
          ),
      ],
    );
  }

  Widget _error(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.cloud_off_outlined, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text("Couldn't build the list", textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(error!, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(onPressed: _run, child: const Text("Try again")),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text("Back")),
          ],
        ),
      ),
    );
  }
}
