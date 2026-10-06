import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

import "package:packup/main.dart";
import "package:packup/models/trip.dart";
import "package:packup/services/auth_service.dart";

void main() {
  testWidgets("login screen validates before signing in", (tester) async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthService();
    await auth.restore();
    await tester.pumpWidget(PackUpApp(auth: auth));

    await tester.ensureVisible(find.text("Sign in"));
    await tester.tap(find.text("Sign in"));
    await tester.pump();
    expect(find.text("Enter your email."), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, "Email"), "a@b.co");
    await tester.enterText(find.widgetWithText(TextField, "Password"), "123");
    await tester.ensureVisible(find.text("Sign in"));
    await tester.tap(find.text("Sign in"));
    await tester.pump();
    expect(find.text("Password must be at least 6 characters."), findsOneWidget);
  });

  test("validators", () {
    expect(AuthService.validateEmail("x"), isNotNull);
    expect(AuthService.validateEmail("me@site.lk"), isNull);
    expect(AuthService.validatePassword("secret1"), isNull);
  });

  test("trip json round trip keeps custom items", () {
    final trip = Trip(
      id: "t1",
      destination: "Ella",
      startDate: DateTime(2026, 12, 20, 15),
      endDate: DateTime(2026, 12, 22, 9),
      people: 2,
      activities: ["hiking"],
      preference: "normal",
      items: [PackingItem.custom(name: "Kite", category: "activity", quantity: 1)],
    );
    expect(trip.duration, 3);
    final copy = Trip.fromJson(trip.toJson());
    expect(copy.items.single.custom, isTrue);
    expect(copy.items.single.itemId, lessThan(0));
  });
}
