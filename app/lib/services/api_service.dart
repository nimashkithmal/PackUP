import "dart:convert";

import "package:http/http.dart" as http;

import "../config.dart";
import "../models/trip.dart";
import "auth_service.dart";

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class RecommendResult {
  RecommendResult({required this.listId, required this.weather, required this.items});
  final int listId;
  final WeatherInfo weather;
  final List<PackingItem> items;
}

class AuthSession {
  AuthSession({required this.token, required this.uid, required this.email, required this.preference});
  final String token;
  final String uid;
  final String email;
  final String preference;
}

const defaultActivities = ["hiking", "sightseeing", "beach"];

class ApiService {
  ApiService(this.auth);

  final AuthService auth;

  Future<Map<String, String>> _headers({bool authed = true}) async {
    final headers = {"Content-Type": "application/json"};
    if (authed) {
      final token = await auth.token();
      if (token != null) headers["Authorization"] = "Bearer $token";
    }
    return headers;
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    bool authed = true,
  }) async {
    final uri = Uri.parse("$kApiBase$path");
    final headers = await _headers(authed: authed);
    final encoded = body == null ? null : jsonEncode(body);
    http.Response res;
    try {
      switch (method) {
        case "GET":
          res = await http.get(uri, headers: headers);
        case "PUT":
          res = await http.put(uri, headers: headers, body: encoded);
        case "DELETE":
          res = await http.delete(uri, headers: headers);
        default:
          res = await http.post(uri, headers: headers, body: encoded);
      }
    } on http.ClientException {
      throw ApiException("Can't reach the PackUP server at $kApiBase. Is the API running?");
    }
    if (res.statusCode == 401 && authed) {
      await auth.sessionExpired();
      throw ApiException("Your session has expired. Please sign in again.", statusCode: 401);
    }
    if (res.statusCode >= 400) {
      throw ApiException(_extractError(res.body, res.statusCode), statusCode: res.statusCode);
    }
    if (res.body.isEmpty) return null;
    return jsonDecode(res.body);
  }

  AuthSession _session(Map<String, dynamic> data) {
    final user = data["user"] as Map<String, dynamic>;
    return AuthSession(
      token: data["token"] as String,
      uid: user["uid"] as String,
      email: user["email"] as String,
      preference: user["preference"] as String? ?? "normal",
    );
  }

  Future<AuthSession> register(String email, String password) async {
    final data = await _send("POST", "/v1/auth/register",
        body: {"email": email, "password": password}, authed: false);
    return _session(data as Map<String, dynamic>);
  }

  Future<AuthSession> login(String email, String password) async {
    final data = await _send("POST", "/v1/auth/login",
        body: {"email": email, "password": password}, authed: false);
    return _session(data as Map<String, dynamic>);
  }

  Future<String> preference() async {
    final data = await _send("GET", "/v1/me") as Map<String, dynamic>;
    return data["preference"] as String? ?? "normal";
  }

  Future<void> setPreference(String value) async {
    await _send("PUT", "/v1/me/preference", body: {"preference": value});
  }

  Future<List<String>> activities() async {
    final data = await _send("GET", "/v1/activities", authed: false) as List;
    return data.cast<String>();
  }

  Future<List<Trip>> listTrips() async {
    final data = await _send("GET", "/v1/trips") as List;
    return data.map((e) => Trip.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<void> saveTrip(Trip trip) async {
    await _send("PUT", "/v1/trips/${Uri.encodeComponent(trip.id)}", body: trip.toJson());
  }

  Future<void> deleteTrip(String id) async {
    await _send("DELETE", "/v1/trips/${Uri.encodeComponent(id)}");
  }

  Future<RecommendResult> recommend(Trip trip) async {
    final data = await _send("POST", "/v1/recommendations", body: {
      "trip_id": trip.id,
      "destination": trip.destination,
      "start_date": _date(trip.startDate),
      "end_date": _date(trip.endDate),
      "people": trip.people,
      "activities": trip.activities,
      "preference": trip.preference,
    }) as Map<String, dynamic>;
    final weather = WeatherInfo.fromJson(data["weather"] as Map<String, dynamic>);
    final items = (data["items"] as List)
        .map((e) => PackingItem.fromJson(e as Map<String, dynamic>))
        .toList();
    return RecommendResult(listId: data["list_id"] as int, weather: weather, items: items);
  }

  /// Sends item statuses (and the rating) back as training data. Custom items are skipped.
  Future<void> sendFeedback(Trip trip, {List<PackingItem>? items, bool includeRating = true}) async {
    final list = (items ?? trip.items).where((e) => !e.custom);
    await _send("POST", "/v1/trips/${Uri.encodeComponent(trip.id)}/feedback", body: {
      if (includeRating && trip.rating != null) "rating": trip.rating,
      "items": list.map((e) => {"item_id": e.itemId, "status": e.status}).toList(),
    });
  }

  static String _date(DateTime d) => d.toIso8601String().split("T").first;

  String _extractError(String body, int code) {
    try {
      final data = jsonDecode(body);
      if (data is Map && data["detail"] != null) {
        final detail = data["detail"];
        // FastAPI validation errors are a list of {msg, loc, ...}
        if (detail is List && detail.isNotEmpty && detail.first is Map) {
          return (detail.first as Map)["msg"].toString().replaceFirst("Value error, ", "");
        }
        return detail.toString();
      }
    } catch (_) {}
    return "Request failed ($code)";
  }
}
