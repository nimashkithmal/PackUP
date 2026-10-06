const bool kUseFirebase = bool.fromEnvironment("USE_FIREBASE", defaultValue: false);
const String kApiBase = String.fromEnvironment(
  "API_BASE",
  defaultValue: "http://127.0.0.1:8000",
);
