import "package:flutter/material.dart";

import "../services/auth_service.dart";
import "home_screen.dart";

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth});
  final AuthService auth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool register = false;
  bool loading = false;
  String? error;

  Future<void> _submit() async {
    final problem =
        AuthService.validateEmail(email.text) ?? AuthService.validatePassword(password.text);
    if (problem != null) {
      setState(() => error = problem);
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (register) {
        await widget.auth.register(email.text, password.text);
      } else {
        await widget.auth.signIn(email.text, password.text);
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => HomeScreen(auth: widget.auth)),
      );
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Text("PackUP", style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 8),
              const Text("Personalized packing lists from destination, weather, and activities."),
              const SizedBox(height: 32),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: "Email"),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(labelText: "Password"),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: loading ? null : _submit,
                child: Text(register ? "Create account" : "Sign in"),
              ),
              TextButton(
                onPressed: () => setState(() => register = !register),
                child: Text(register ? "Have an account? Sign in" : "New here? Register"),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
