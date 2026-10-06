class PackingItem {
  PackingItem({
    required this.itemId,
    required this.slug,
    required this.name,
    required this.category,
    required this.quantity,
    required this.sources,
    required this.confidence,
    required this.status,
    this.suggested = false,
    this.isSafety = false,
    this.custom = false,
  });

  /// An item the user typed in; it is not in the server catalog.
  factory PackingItem.custom({required String name, required String category, required int quantity}) {
    final id = DateTime.now().microsecondsSinceEpoch;
    return PackingItem(
      itemId: -id,
      slug: "custom-$id",
      name: name,
      category: category,
      quantity: quantity,
      sources: const ["added by you"],
      confidence: 1,
      status: "pending",
      custom: true,
    );
  }

  final int itemId;
  final String slug;
  final String name;
  final String category;
  final int quantity;
  final List<String> sources;
  final double confidence;
  final bool suggested;
  final bool isSafety;
  final bool custom;
  String status;

  factory PackingItem.fromJson(Map<String, dynamic> json) {
    return PackingItem(
      itemId: json["item_id"] as int,
      slug: json["slug"] as String,
      name: json["name"] as String,
      category: json["category"] as String,
      quantity: json["quantity"] as int,
      sources: List<String>.from(json["sources"] as List),
      confidence: (json["confidence"] as num).toDouble(),
      suggested: json["suggested"] as bool? ?? false,
      isSafety: json["is_safety"] as bool? ?? false,
      status: json["status"] as String? ?? "pending",
      custom: json["custom"] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        "item_id": itemId,
        "slug": slug,
        "name": name,
        "category": category,
        "quantity": quantity,
        "sources": sources,
        "confidence": confidence,
        "suggested": suggested,
        "is_safety": isSafety,
        "status": status,
        "custom": custom,
      };
}

class WeatherInfo {
  WeatherInfo({
    required this.placeName,
    required this.avgTempC,
    required this.minTempC,
    required this.maxTempC,
    required this.precipProbability,
    required this.tags,
    this.source = "forecast",
  });

  final String placeName;
  final double avgTempC;
  final double minTempC;
  final double maxTempC;
  final double precipProbability;
  final List<String> tags;

  /// "forecast" or "climate" (estimated from past years for trips beyond the forecast range).
  final String source;

  factory WeatherInfo.fromJson(Map<String, dynamic> json) {
    return WeatherInfo(
      placeName: json["place_name"] as String? ?? "",
      avgTempC: (json["avg_temp_c"] as num?)?.toDouble() ?? 0,
      minTempC: (json["min_temp_c"] as num?)?.toDouble() ?? 0,
      maxTempC: (json["max_temp_c"] as num?)?.toDouble() ?? 0,
      precipProbability: (json["precip_probability"] as num?)?.toDouble() ?? 0,
      tags: List<String>.from(json["tags"] as List? ?? const []),
      source: json["source"] as String? ?? "forecast",
    );
  }

  Map<String, dynamic> toJson() => {
        "place_name": placeName,
        "avg_temp_c": avgTempC,
        "min_temp_c": minTempC,
        "max_temp_c": maxTempC,
        "precip_probability": precipProbability,
        "tags": tags,
        "source": source,
      };
}

class Trip {
  Trip({
    required this.id,
    required this.destination,
    required this.startDate,
    required this.endDate,
    required this.people,
    required this.activities,
    required this.preference,
    this.listId,
    this.weather,
    this.items = const [],
    this.rating,
    this.status = "draft",
  });

  final String id;
  String destination;
  DateTime startDate;
  DateTime endDate;
  int people;
  List<String> activities;
  String preference;
  int? listId;
  WeatherInfo? weather;
  List<PackingItem> items;
  int? rating;
  String status;

  int get duration => _day(endDate).difference(_day(startDate)).inDays + 1;

  int get pendingCount => items.where((e) => e.status == "pending").length;

  /// Days from today until the trip starts (negative once it has started).
  int get daysUntilStart => _day(startDate).difference(_day(DateTime.now())).inDays;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  factory Trip.fromJson(Map<String, dynamic> json) {
    return Trip(
      id: json["id"] as String,
      destination: json["destination"] as String,
      startDate: DateTime.parse(json["start_date"] as String),
      endDate: DateTime.parse(json["end_date"] as String),
      people: json["people"] as int,
      activities: List<String>.from(json["activities"] as List),
      preference: json["preference"] as String,
      listId: json["list_id"] as int?,
      weather: json["weather"] == null
          ? null
          : WeatherInfo.fromJson(Map<String, dynamic>.from(json["weather"] as Map)),
      items: (json["items"] as List? ?? [])
          .map((e) => PackingItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      rating: json["rating"] as int?,
      status: json["status"] as String? ?? "draft",
    );
  }

  Map<String, dynamic> toJson() => {
        "id": id,
        "destination": destination,
        "start_date": startDate.toIso8601String(),
        "end_date": endDate.toIso8601String(),
        "people": people,
        "activities": activities,
        "preference": preference,
        "list_id": listId,
        "weather": weather?.toJson(),
        "items": items.map((e) => e.toJson()).toList(),
        "rating": rating,
        "status": status,
      };
}
