import "package:flutter/material.dart";

import "../config.dart";
import "../services/auth_service.dart";
import "../services/trip_repository.dart";
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

  @override
  Widget build(BuildContext context) {
    final user = widget.auth.current!;
    return Scaffold(
      appBar: AppBar(title: const Text("Profile")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(title: const Text("Email"), subtitle: Text(user.email)),
          ListTile(title: const Text("User id"), subtitle: Text(user.uid)),
          ListTile(
            title: const Text("Mode"),
            subtitle: Text(kUseFirebase ? "Firebase Auth + Firestore" : "PackUP account (MySQL server)"),
          ),
          const SizedBox(height: 12),
          const Text("Default packing preference"),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: "minimal", label: Text("Minimal")),
              ButtonSegment(value: "normal", label: Text("Normal")),
              ButtonSegment(value: "prepared", label: Text("Prepared")),
            ],
            selected: {preference},
            onSelectionChanged: (s) async {
              final previous = preference;
              setState(() => preference = s.first);
              try {
                await widget.repo.savePreference(preference);
              } catch (e) {
                if (!context.mounted) return;
                setState(() => preference = previous);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
              }
            },
          ),
          const SizedBox(height: 32),
          OutlinedButton(
            onPressed: () async {
              await widget.auth.signOut();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => LoginScreen(auth: widget.auth)),
                (_) => false,
              );
            },
            child: const Text("Log out"),
          ),
        ],
      ),
    );
  }
}
