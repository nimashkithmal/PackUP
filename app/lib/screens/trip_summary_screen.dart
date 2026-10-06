import "package:flutter/material.dart";

import "../models/trip.dart";
import "../services/auth_service.dart";
import "../services/trip_repository.dart";

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

  @override
  Widget build(BuildContext context) {
    final packed = widget.trip.items.where((e) => e.status == "packed").length;
    final buy = widget.trip.items.where((e) => e.status == "need_to_buy").length;
    final skip = widget.trip.items.where((e) => e.status == "not_required").length;
    return Scaffold(
      appBar: AppBar(title: const Text("Trip summary")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.trip.destination, style: Theme.of(context).textTheme.headlineSmall),
            Text("Packed $packed · Need to buy $buy · Not required $skip"),
            const SizedBox(height: 24),
            const Text("How useful was this list?"),
            Slider(
              min: 1,
              max: 5,
              divisions: 4,
              value: rating.toDouble(),
              label: "$rating",
              onChanged: (v) => setState(() => rating = v.round()),
            ),
            const Spacer(),
            FilledButton(
              onPressed: saving ? null : _save,
              child: const Text("Save feedback"),
            ),
          ],
        ),
      ),
    );
  }
}
