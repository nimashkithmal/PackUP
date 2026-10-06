import "package:flutter/material.dart";

import "../models/trip.dart";
import "../services/auth_service.dart";
import "../services/trip_repository.dart";
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
    return Scaffold(
      body: Center(
        child: error == null
            ? const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text("Checking weather and building your list…"),
                ],
              )
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text("Back")),
                        const SizedBox(width: 12),
                        FilledButton(onPressed: _run, child: const Text("Try again")),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
