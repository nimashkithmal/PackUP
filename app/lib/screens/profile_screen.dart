import "package:flutter/material.dart";

import "../config.dart";
import "../services/auth_service.dart";
import "../services/trip_repository.dart";
import "../theme.dart";
import "login_screen.dart";

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.auth, required this.repo});
  final AuthService auth;
  final TripRepository repo;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String preference = "normal";

  @override
  void initState() {
    super.initState();
    widget.repo.preference().then((value) {
      if (value != null && mounted) setState(() => preference = value);
    }).catchError((_) {});
  }

  Future<void> _setPreference(String value) async {
    final previous = preference;
    setState(() => preference = value);
    try {
      await widget.repo.savePreference(value);
    } catch (e) {
      if (!mounted) return;
      setState(() => preference = previous);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _logout() async {
    await widget.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen(auth: widget.auth)),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final user = widget.auth.current!;
    return Scaffold(
      appBar: AppBar(title: const Text("Profile")),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: scheme.primaryContainer,
                          child: Text(
                            user.email.isEmpty ? "?" : user.email[0].toUpperCase(),
                            style: theme.textTheme.headlineSmall?.copyWith(color: scheme.onPrimaryContainer),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(user.email, style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              Text(
                                kUseFirebase ? "Firebase account" : "PackUP account",
                                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                const SectionLabel("Default packing style"),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: "minimal", label: Text("Minimal"), icon: Icon(Icons.backpack_outlined)),
                    ButtonSegment(value: "normal", label: Text("Normal"), icon: Icon(Icons.luggage_outlined)),
                    ButtonSegment(value: "prepared", label: Text("Prepared"), icon: Icon(Icons.inventory_2_outlined)),
                  ],
                  selected: {preference},
                  onSelectionChanged: (s) => _setPreference(s.first),
                ),
                const SizedBox(height: 6),
                Text(
                  "Used for new trips. You can still change it per trip.",
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 28),
                const SectionLabel("Account"),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.fingerprint),
                        title: const Text("User ID"),
                        subtitle: Text(user.uid, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      const Divider(indent: 56),
                      ListTile(
                        leading: const Icon(Icons.dns_outlined),
                        title: const Text("Server"),
                        subtitle: Text(kUseFirebase ? "Firebase Auth + Firestore" : kApiBase),
                      ),
                      const Divider(indent: 56),
                      ListTile(
                        leading: Icon(Icons.logout, color: scheme.error),
                        title: Text("Log out", style: TextStyle(color: scheme.error)),
                        onTap: _logout,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
