import "package:cloud_firestore/cloud_firestore.dart";

import "../config.dart";
import "../models/trip.dart";
import "auth_service.dart";

/// Trips live in Firestore (Firebase mode) or in the PackUP API's MySQL database.
class TripRepository {
  TripRepository(this.auth);
  final AuthService auth;

  String get uid => auth.current!.uid;

  Future<List<Trip>> listTrips() async {
    final List<Trip> trips;
    if (kUseFirebase) {
      final snap = await FirebaseFirestore.instance
          .collection("trips")
          .where("uid", isEqualTo: uid)
          .get();
      trips = snap.docs.map((d) => Trip.fromJson(d.data())).toList();
    } else {
      trips = await auth.api.listTrips();
    }
    trips.sort((a, b) => b.startDate.compareTo(a.startDate));
    return trips;
  }

  Future<void> saveTrip(Trip trip) async {
    if (kUseFirebase) {
      final data = trip.toJson()..["uid"] = uid;
      await FirebaseFirestore.instance.collection("trips").doc(trip.id).set(data);
      return;
    }
    await auth.api.saveTrip(trip);
  }

  Future<void> deleteTrip(Trip trip) async {
    if (kUseFirebase) {
      final doc = FirebaseFirestore.instance.collection("trips").doc(trip.id);
      final items = await doc.collection("items").get();
      final batch = FirebaseFirestore.instance.batch();
      for (final d in items.docs) {
        batch.delete(d.reference);
      }
      batch.delete(doc);
      await batch.commit();
      return;
    }
    await auth.api.deleteTrip(trip.id);
  }

  Future<String?> preference() async {
    if (kUseFirebase) {
      final doc = await FirebaseFirestore.instance.collection("users").doc(uid).get();
      return doc.data()?["packingPreference"] as String?;
    }
    return auth.api.preference();
  }

  Future<void> savePreference(String value) async {
    if (kUseFirebase) {
      await FirebaseFirestore.instance.collection("users").doc(uid).set({
        "packingPreference": value,
      }, SetOptions(merge: true));
      return;
    }
    await auth.api.setPreference(value);
  }
}
