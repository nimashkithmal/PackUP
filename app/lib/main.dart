import "package:firebase_core/firebase_core.dart";
import "package:flutter/material.dart";

import "config.dart";
import "firebase_options.dart";
import "screens/home_screen.dart";
import "screens/login_screen.dart";
import "services/auth_service.dart";
import "theme.dart";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kUseFirebase) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }
  final auth = AuthService();
  await auth.restore();
  auth.onSessionExpired = () {
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen(auth: auth)),
      (_) => false,
    );
  };
  runApp(PackUpApp(auth: auth));
}

final navigatorKey = GlobalKey<NavigatorState>();

/// Lets screens refresh when the user comes back to them.
final routeObserver = RouteObserver<ModalRoute<void>>();

class PackUpApp extends StatelessWidget {
  const PackUpApp({super.key, required this.auth});
  final AuthService auth;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "PackUP",
      navigatorKey: navigatorKey,
      navigatorObservers: [routeObserver],
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: auth.current == null ? LoginScreen(auth: auth) : HomeScreen(auth: auth),
    );
  }
}
