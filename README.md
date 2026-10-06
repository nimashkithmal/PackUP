# PackUP

PackUP builds a packing list for a trip from the destination, the dates, the number of people and the planned activities. It checks the weather, applies packing rules, works out quantities and gives each item a confidence score from a machine-learning model. What travellers pack, skip or rate is stored as feedback, and the model retrains on it.

PackUP combines a rule engine, live weather data and an ML confidence score. There is no chatbot.

- **App:** Flutter (Android, iOS, web)
- **API:** FastAPI (Python)
- **Database:** MySQL
- **Weather:** Open-Meteo (free, no API key)
- **ML:** scikit-learn

---

## Contents

1. [Features](#features)
2. [How it works](#how-it-works)
3. [Project structure](#project-structure)
4. [Requirements](#requirements)
5. [Step 1: Start the backend](#step-1-start-the-backend)
6. [Step 2: Run the app](#step-2-run-the-app)
   - [Chrome (web)](#chrome-web)
   - [Android](#android)
   - [iOS](#ios)
7. [Release builds](#release-builds)
8. [Configuration](#configuration)
9. [Database](#database)
10. [Machine learning](#machine-learning)
11. [API reference](#api-reference)
12. [Tests](#tests)
13. [Firebase mode (optional)](#firebase-mode-optional)
14. [Troubleshooting](#troubleshooting)

---

## Features

- Email and password accounts. Passwords are stored as PBKDF2 hashes and sessions use JWT tokens.
- Trips are stored on the server, so they appear on every device after sign-in.
- **Weather-aware lists.** Trips in the next 15 days use the live forecast. Later trips use an estimate from the same dates in the last 5 years.
- **Rules** for 6 activities (hiking, sightseeing, beach, camping, business, temple), weather conditions (rain, cold, hot) and essentials.
- **Quantities** depend on trip length, number of people and packing style (Minimal / Normal / Prepared).
- **Confidence score** for every item, combining rule priority, similar past trips, overall keep rate and an ML model.
- **Item statuses:** packed, need to buy, not needed. You can also add your own items or remove items.
- **Filters** (All / To pack / Packed / To buy), a packing progress bar and swipe-to-delete with undo.
- **Share** the list (WhatsApp, email and so on) or copy it as text.
- **Reminders** on the home screen for trips starting within 3 days.
- **Rate a list** with 1–5 stars. Ratings and packed items are used to retrain the model.
- Edit or delete trips. Editing keeps your statuses and custom items.
- Light and dark mode.

---

## How it works

```
Flutter app ──HTTPS + Bearer token──▶ FastAPI ──▶ MySQL
                                        │
                                        └──▶ Open-Meteo (geocoding, forecast, history)
```

When you tap **Build my packing list**, the API does the following:

1. **Weather.** It looks up the destination's coordinates. Then it uses the forecast for trips within 15 days, or the past 5 years for later dates. The result gets tags: `rain` (≥ 60% chance), `cold` (< 18 °C), `hot` (> 28 °C) or `normal`.
2. **Rules.** It collects essentials, activity rules and weather rules. Each rule has a priority from 0 to 100.
3. **Quantity.** It applies one of these formulas:

   | Mode | Formula |
   |---|---|
   | per day per person | ⌈ base × days × people × factor + extra × people ⌉ |
   | per person | ⌈ people × factor ⌉ |
   | per group | 1 |

   The factor is 0.7 for Minimal, 1.0 for Normal and 1.25 for Prepared. For example, a 3-day trip for 2 people on Minimal gives 1 × 3 × 2 × 0.7 = 4.2, so **5 T-shirts**.

4. **Confidence.** It averages these signals:
   - rule priority
   - keep rate on similar trips (same activity and weather)
   - overall keep rate
   - the model's prediction

   Safety items (ID, medication, first aid, tickets) never show less than 85%. Other items below 62% are marked **Optional**.

5. **Save.** It stores the list and each item so that later feedback can be used for training.

---

## Project structure

```
PackUP/
├── docker-compose.yml        MySQL + API containers
├── .env                      Secrets used by Docker Compose (not in git)
├── firebase/firestore.rules  Only used in Firebase mode
├── backend/
│   ├── app/
│   │   ├── main.py           App start-up, migrations, background retraining
│   │   ├── config.py         Settings loaded from .env
│   │   ├── models.py         Database tables
│   │   ├── migrate.py        Adds new columns and indexes to existing databases
│   │   ├── seed.py           Catalog items and rules
│   │   ├── weather.py        Forecast and climate estimate
│   │   ├── rules.py          Rule engine and quantities
│   │   ├── recommend.py      Recommendation pipeline
│   │   ├── ml_features.py    Feature encoding
│   │   ├── ml_scorer.py      Confidence scores
│   │   ├── training.py       Scheduled retraining
│   │   ├── security.py       Password hashing and JWT
│   │   ├── auth.py           Request authentication
│   │   └── routers/          auth, trips, catalog, recommendations, feedback, admin
│   ├── ml/train.py           Model training
│   ├── sql/schema.sql        MySQL schema (reference)
│   ├── tests/                pytest tests
│   ├── requirements.txt
│   └── .env.example
└── app/
    ├── lib/
    │   ├── main.dart, config.dart, theme.dart
    │   ├── models/trip.dart
    │   ├── services/         auth_service, api_service, trip_repository
    │   └── screens/          login, home, create_trip, generating,
    │                         packing_list, trip_summary, profile
    ├── android/ ios/ web/    Platform projects
    └── test/
```

---

## Requirements

| Tool | Needed for | Install |
|---|---|---|
| Docker Desktop | Backend + MySQL (easiest way) | https://www.docker.com/products/docker-desktop |
| Python 3.11+ | Running the backend without Docker, tests, training | `brew install python` |
| Flutter 3.24+ | Building and running the app | `brew install --cask flutter` |
| Google Chrome | Web | https://www.google.com/chrome |
| Android Studio | Android emulator and SDK | https://developer.android.com/studio |
| Xcode 15+ (macOS only) | iOS simulator and iPhone | Mac App Store |
| CocoaPods (macOS only) | iOS plugins | `brew install cocoapods` |

To check your Flutter setup:

```bash
flutter doctor
```

Each platform you want to use should have a green tick. You only need the platforms you will actually run.

---

## Step 1: Start the backend

Start the backend before you run the app on any platform.

### Option A: Docker (recommended)

1. Create the secrets file in the project root. Do this once.

   ```bash
   cd PackUP
   cat > .env <<EOF
   JWT_SECRET=$(python3 -c "import secrets;print(secrets.token_urlsafe(48))")
   ADMIN_TOKEN=$(python3 -c "import secrets;print(secrets.token_urlsafe(24))")
   CORS_ORIGINS=*
   EOF
   ```

2. Start MySQL and the API:

   ```bash
   docker compose up -d --build
   ```

3. Check that the API is running:

   ```bash
   curl http://127.0.0.1:8000/health
   ```

   The expected reply is `{"status":"ok"}`.

- Interactive API docs: http://127.0.0.1:8000/docs
- The first start creates the tables, adds the rules and trains the model in the background.

**Useful commands:**

```bash
docker compose logs -f api     # Follow the API logs
docker compose restart api     # Restart the API
docker compose down            # Stop everything (data is kept)
docker compose down -v         # Stop and DELETE all data
```

### Option B: Run the API with Python (for development)

1. Start only MySQL with Docker:

   ```bash
   docker compose up -d mysql
   ```

2. Set up the Python environment:

   ```bash
   cd backend
   python3 -m venv .venv
   source .venv/bin/activate
   pip install -r requirements.txt
   ```

3. Create `backend/.env` and add a random `JWT_SECRET`:

   ```bash
   cp .env.example .env
   ```

4. Train the model and start the API. `--reload` restarts it when code changes.

   ```bash
   export PYTHONPATH=.
   python ml/train.py
   uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
   ```

> **Without MySQL:** set `DATABASE_URL=sqlite:///./packup.db` in `backend/.env`.
>
> **Port 8000 already in use:** the Docker `api` container is probably running. Stop it with `docker compose stop api`.

---

## Step 2: Run the app

Install the app's dependencies once:

```bash
cd app
flutter pub get
```

The app reaches the API at the address set by `API_BASE`. The right value depends on where the app runs:

| Where the app runs | `API_BASE` |
|---|---|
| Chrome on the same computer | `http://127.0.0.1:8000` (default, nothing to pass) |
| Android emulator | `http://10.0.2.2:8000` |
| iOS simulator | `http://127.0.0.1:8000` (default, nothing to pass) |
| Real Android phone or iPhone | `http://<your computer's Wi-Fi IP>:8000` |

To find your computer's Wi-Fi IP:

```bash
ipconfig getifaddr en0          # macOS
hostname -I                     # Linux
ipconfig                        # Windows: look for "IPv4 Address"
```

To list the devices Flutter can see:

```bash
flutter devices
```

While the app is running, press `r` in the terminal to hot reload, `R` to restart and `q` to quit.

> Values passed with `--dart-define` are read when the app starts. After changing one, quit with `q` and run again. `r` and `R` don't apply the new value.

---

### Chrome (web)

```bash
cd app
flutter run -d chrome
```

Chrome opens automatically.

**To run on a fixed port:**

```bash
flutter run -d web-server --web-port 5000
```

Then open http://localhost:5000.

> Don't pass `API_BASE=http://10.0.2.2:8000` when running in Chrome. That address only exists inside the Android emulator, and the app shows `Failed to fetch`.

---

### Android

#### One-time setup

1. Install **Android Studio**.
2. Open **More Actions → SDK Manager** and install an Android SDK and the **Android SDK Command-line Tools**.
3. Accept the licences:

   ```bash
   flutter doctor --android-licenses
   ```

#### Emulator

1. In Android Studio, open **More Actions → Virtual Device Manager**, create a device (for example a Pixel 8) and start it.

   Alternatively, from the terminal:

   ```bash
   flutter emulators                       # list emulators
   flutter emulators --launch <emulator_id>
   ```

2. Run the app:

   ```bash
   cd app
   flutter run -d emulator-5554 --dart-define=API_BASE=http://10.0.2.2:8000
   ```

   If it is the only device connected, `-d emulator-5554` isn't needed.

#### Real Android phone

1. On the phone, open **Settings → About phone** and tap **Build number** 7 times to enable Developer options.
2. Open **Settings → Developer options** and turn on **USB debugging**.
3. Connect the phone by USB and allow the computer when the phone asks.
4. Connect the phone and the computer to the **same Wi-Fi network**.
5. Run the app with your computer's IP:

   ```bash
   cd app
   flutter devices                         # find the phone's id
   flutter run -d <phone_id> --dart-define=API_BASE=http://192.168.1.20:8000
   ```

> If the phone can't reach the API, allow incoming connections for Docker or Python in your computer's firewall (macOS: **System Settings → Network → Firewall**).

---

### iOS

> Building for iOS requires a **Mac** with **Xcode**.

#### One-time setup

1. Install **Xcode** from the Mac App Store and open it once to finish installing components.
2. Point the command-line tools at Xcode and finish its first launch:

   ```bash
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -runFirstLaunch
   ```

3. Install CocoaPods and the iOS plugins:

   ```bash
   brew install cocoapods
   cd app/ios && pod install && cd ..
   ```

4. In Xcode, go to **Settings → Platforms** and download an **iOS Simulator** runtime if none is installed.

#### iOS Simulator

1. Start a simulator:

   ```bash
   open -a Simulator
   ```

2. Run the app:

   ```bash
   cd app
   flutter run -d ios
   ```

   If several simulators are open, use `flutter devices` and pass the simulator's id with `-d`.

The simulator shares the Mac's network, so the default `http://127.0.0.1:8000` works.

#### Real iPhone

1. Open the Xcode workspace:

   ```bash
   open app/ios/Runner.xcworkspace
   ```

2. In Xcode, select **Runner** → **Signing & Capabilities**:
   - **Team:** choose your Apple ID. A free account works.
   - **Bundle Identifier:** change `com.example.packup` to something unique, for example `com.yourname.packup`.
3. On the iPhone, turn on **Settings → Privacy & Security → Developer Mode** and restart the phone.
4. Connect the iPhone by USB, unlock it and tap **Trust**.
5. Run the app with your Mac's IP:

   ```bash
   cd app
   flutter run -d <iphone_id> --dart-define=API_BASE=http://192.168.1.20:8000
   ```

6. The first time, the iPhone may block the app as "Untrusted Developer". Open **Settings → General → VPN & Device Management**, trust your Apple ID and run the app again.
7. If iOS asks for **Local Network** access, tap **Allow**. Otherwise the app can't reach your Mac.

> With a free Apple ID, the app installed on the iPhone expires after 7 days. Run it again from Xcode or Flutter to reinstall it.

---

## Release builds

Before building for release, put the API on a public server with **HTTPS** and pass its address with `API_BASE`.

| Platform | Command | Output |
|---|---|---|
| Web | `flutter build web --dart-define=API_BASE=https://api.example.com` | `app/build/web/`: upload it to any static host (Firebase Hosting, Netlify, Vercel, Nginx) |
| Android APK | `flutter build apk --release --dart-define=API_BASE=https://api.example.com` | `app/build/app/outputs/flutter-apk/app-release.apk` |
| Android (Play Store) | `flutter build appbundle --release --dart-define=API_BASE=https://api.example.com` | `app/build/app/outputs/bundle/release/app-release.aab` |
| iOS (App Store / TestFlight) | `flutter build ipa --release --dart-define=API_BASE=https://api.example.com` | `app/build/ios/ipa/`: upload it with Xcode or Transporter |

Before you release:

- Change the Android `applicationId` in `app/android/app/build.gradle.kts`.
- Change the iOS bundle identifier in Xcode.
- Set `CORS_ORIGINS` on the API to your web app's address. Don't leave it as `*`.
- Use a long random `JWT_SECRET` and a strong MySQL password (`MYSQL_PASSWORD` and `MYSQL_ROOT_PASSWORD` in the root `.env`).

---

## Configuration

The API reads these settings from `backend/.env`. With Docker Compose, the values come from the root `.env` instead.

| Variable | Default | Meaning |
|---|---|---|
| `DATABASE_URL` | `sqlite:///./packup.db` | Database connection, for example `mysql+pymysql://packup:packup@127.0.0.1:3306/packup` |
| `AUTH_MODE` | `local` | `local`: accounts in MySQL. `firebase`: Firebase ID tokens |
| `JWT_SECRET` | dev value | **Required.** A long random string used to sign tokens |
| `JWT_EXPIRE_DAYS` | `30` | How long a sign-in lasts |
| `CORS_ORIGINS` | `*` | Comma-separated web origins allowed to call the API |
| `RETRAIN_INTERVAL_HOURS` | `24` | Background retraining interval. `0` turns it off |
| `ADMIN_TOKEN` | empty | Turns on `/v1/admin/*` when set |
| `FORECAST_HORIZON_DAYS` | `15` | Trips further out than this use the climate estimate |
| `CLIMATE_YEARS` | `5` | Number of past years used for the climate estimate |
| `SYNTHETIC_FADE_EVENTS` | `300` | Number of real feedback events at which synthetic training data reaches 5% weight |
| `FIREBASE_PROJECT_ID`, `GOOGLE_APPLICATION_CREDENTIALS` | empty | Only used in Firebase mode |

The app takes these build options through `--dart-define`:

| Option | Default | Meaning |
|---|---|---|
| `API_BASE` | `http://127.0.0.1:8000` | API address |
| `USE_FIREBASE` | `false` | Use Firebase Auth and Firestore |

---

## Database

The tables are created automatically when the API starts. The schema is also in `backend/sql/schema.sql` for reference.

| Table | Contents |
|---|---|
| `users` | Accounts: email, password hash, default packing style |
| `trips` | Each user's trips, with items and statuses |
| `catalog_items` | The 36 catalog items: category, quantity mode, safety flag |
| `activity_rules`, `weather_rules`, `duration_rules` | The rule engine |
| `generated_lists` | Every generated list, with its weather and rating |
| `list_item_events` | Per-item feedback (ML training data) |
| `ml_models` | Training history and metrics |

**Look at the data:**

```bash
docker compose exec mysql mysql -u packup -ppackup packup
```

```sql
SHOW TABLES;
SELECT email, preference, created_at FROM users;
SELECT destination, start_date, status, rating FROM trips;
SELECT * FROM generated_lists WHERE uid <> 'synthetic' ORDER BY id DESC LIMIT 10;
```

**GUI tools** (TablePlus, DBeaver, MySQL Workbench) connect with:

| Field | Value |
|---|---|
| Host | `127.0.0.1` |
| Port | `3306` |
| User | `packup` |
| Password | `packup` |
| Database | `packup` |

---

## Machine learning

- **Model:** `GradientBoostingClassifier`. It predicts whether a traveller keeps an item (packed or need to buy) or skips it (not needed).
- **Features:**
  - latitude and longitude
  - trip length and number of people
  - average temperature and rain chance
  - weather tags
  - packing style
  - activities (one-hot)
  - item (one-hot)
- **Cold start:** 150 synthetic trips let the model work before there are real users. Their weight drops from 100% to 5% as real feedback grows.
- **Retraining:** runs on start-up when no current model exists, then every 24 hours if new feedback has arrived. The API loads the new model without restarting.

To train manually:

```bash
cd backend
source .venv/bin/activate
PYTHONPATH=. python ml/train.py
```

You can also trigger retraining through the API:

```bash
curl -X POST http://127.0.0.1:8000/v1/admin/retrain -H "X-Admin-Token: <ADMIN_TOKEN>"
```

To check the current model:

```bash
curl http://127.0.0.1:8000/v1/admin/model -H "X-Admin-Token: <ADMIN_TOKEN>"
```

---

## API reference

Full interactive docs are at http://127.0.0.1:8000/docs. All `/v1` routes except register, login, activities and catalog need the header `Authorization: Bearer <token>`.

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | Health check |
| POST | `/v1/auth/register` | Create an account and get a token |
| POST | `/v1/auth/login` | Sign in and get a token |
| GET | `/v1/me` | Current user |
| PUT | `/v1/me/preference` | Set the default packing style |
| GET | `/v1/trips` | List my trips |
| PUT | `/v1/trips/{id}` | Create or update a trip |
| DELETE | `/v1/trips/{id}` | Delete a trip |
| GET | `/v1/activities` | Available activities |
| GET | `/v1/catalog` | All catalog items |
| POST | `/v1/recommendations` | Generate a packing list |
| POST | `/v1/trips/{id}/feedback` | Save item statuses and the rating |
| GET | `/v1/admin/model` | Model status (`X-Admin-Token`) |
| POST | `/v1/admin/retrain` | Retrain now (`X-Admin-Token`) |

**Example:**

```bash
TOKEN=$(curl -s -X POST localhost:8000/v1/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"email":"me@example.com","password":"secret123"}' \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['token'])")

curl -s -X POST localhost:8000/v1/recommendations \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"trip_id":"t1","destination":"Ella","start_date":"2026-12-20","end_date":"2026-12-22","people":2,"activities":["hiking"],"preference":"normal"}'
```

---

## Tests

**Backend:** the tests use their own SQLite file and never touch MySQL.

```bash
cd backend
source .venv/bin/activate
python -m pytest -q
```

**App:**

```bash
cd app
flutter analyze
flutter test
```

---

## Firebase mode (optional)

By default, accounts and trips are stored in MySQL through the API. To use Firebase Auth and Firestore instead:

1. In the [Firebase Console](https://console.firebase.google.com), create a project. Then enable **Authentication → Email/Password** and create a **Firestore Database**.
2. Generate the app config. This replaces `app/lib/firebase_options.dart`.

   ```bash
   npm install -g firebase-tools && firebase login
   dart pub global activate flutterfire_cli
   cd app && flutterfire configure
   ```

3. Deploy the Firestore rules:

   ```bash
   firebase deploy --only firestore:rules
   ```

4. Get a service-account key for the API: **Project settings → Service accounts → Generate new private key**. Save it as `backend/serviceAccount.json` and **don't commit it**.
5. Set these values in `backend/.env`, then restart the API:

   ```
   AUTH_MODE=firebase
   FIREBASE_PROJECT_ID=<your-project-id>
   GOOGLE_APPLICATION_CREDENTIALS=./serviceAccount.json
   ```

6. Run the app with Firebase turned on:

   ```bash
   flutter run -d chrome --dart-define=USE_FIREBASE=true
   ```

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `Failed to fetch, uri=http://10.0.2.2:8000/...` in Chrome | `10.0.2.2` only works in the Android emulator. Run `flutter run -d chrome` without `API_BASE`. |
| `Can't reach the PackUP server` | Check that the API is running with `curl http://127.0.0.1:8000/health`. On a real phone, use your computer's IP and the same Wi-Fi network, and check the firewall. |
| `Your session has expired` | Sign in again. Tokens last 30 days, and changing `JWT_SECRET` signs everyone out. |
| `Could not find the destination` | Check the spelling, or try a nearby town or city. |
| `Address already in use` on port 8000 | The Docker `api` container is running. Use it, or stop it with `docker compose stop api`. |
| Port 3306 in use | A local MySQL server is already running. Stop it (`brew services stop mysql`) or change the port in `docker-compose.yml`. |
| `CocoaPods not installed` / pod errors | `brew install cocoapods`, then `cd app/ios && pod install --repo-update` |
| iOS "Untrusted Developer" | On the iPhone, open **Settings → General → VPN & Device Management** and trust your Apple ID. |
| Android licence errors | `flutter doctor --android-licenses` |
| A yellow-black overflow stripe flashes in debug mode | This happens when the browser window is very small, for example with DevTools docked. It doesn't appear in release builds. |
| Old demo accounts no longer work | Accounts are now stored on the server. Register again. |
