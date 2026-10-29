
# 🔴 BOOMGRATULATIONS

### Football Fixtures • Live Scores • AI Picks • Tips • Results

BOOMGRATULATIONS is a Flutter-based football application designed to provide football fixtures, match information, predictions, tips, league standings and results in one place.

---

## 🚀 Features

- Football fixtures and match information
- Live scores through API-Football
- AI Picks and football predictions
- Football tips
- League tables and standings
- Favourite matches
- Dark mode and light mode
- Red-themed user interface
- Roboto and Montserrat typography
- BOOMGRATULATIONS app branding and logo
- Subscribe to Pro section

---

## 🛠️ Built With

- Flutter
- Dart
- HTTP package
- API-Football
- Google Fonts: Montserrat
- Roboto typography

---

## 📁 Project Structure

```text
boomgratulations/
│
├── android/
├── assets/
│   ├── icon/
│   │   └── app_icon.jpg
│   │
│   ├── fonts/
│   │   ├── Montserrat-Regular.ttf
│   │   └── Montserrat-Bold.ttf
│   │
│   └── logo.jpg
│
├── lib/
│   └── main.dart
│
├── test/
├── pubspec.yaml
└── README.md
```

---

## 📦 Requirements

Before running the application, install:

1. Flutter SDK
2. Dart SDK (included with Flutter)
3. Android Studio or VS Code
4. Android SDK
5. API-Football API key

Check your Flutter installation:

```bash
flutter doctor
```

---

## ⚙️ Installation

Clone or download the project.

Open your terminal in the project directory and run:

```bash
flutter pub get
```

---

## 🔑 API-Football Configuration

BOOMGRATULATIONS uses API-Football to retrieve football fixture and match information.

API endpoint:

```text
https://v3.football.api-sports.io
```

Get your API key from:

https://www.api-football.com/

Pass your API key through Flutter's build define.

### Run the application

```bash
flutter run --dart-define=API_FOOTBALL_KEY=YOUR_API_KEY
```

Replace `YOUR_API_KEY` with your actual API key.

### Build the release APK

```bash
flutter build apk --release --dart-define=API_FOOTBALL_KEY=YOUR_API_KEY
```

**Security note:** A key embedded in an APK can be extracted. For a production app, consider routing API requests through a secure backend rather than distributing a private API key in the application.

---

## 🔤 Font Configuration

The application uses:

- **Roboto:** General text, match details, scores and buttons.
- **Montserrat:** Branding, headings and premium sections.

Montserrat font files are stored in:

```text
assets/fonts/
├── Montserrat-Regular.ttf
└── Montserrat-Bold.ttf
```

The fonts are registered in `pubspec.yaml`.

---

## 🎨 App Theme

- Primary colour: Red
- Dark mode: Supported
- Light mode: Supported
- Typography: Roboto + Montserrat
- App logo: Existing JPG logo

---

## 📱 Android APK Output

After a successful release build, locate the APK here:

```text
build/app/outputs/flutter-apk/app-release.apk
```

You can install the APK on a compatible Android device.

---

## ⭐ Pro Subscription

The application includes a Subscribe to Pro section.

Payment processing, subscription verification and premium account management must be connected to a payment provider and backend before accepting real subscriptions.

---

## ❤️ Favourite Matches

Users can mark matches as favourites for easier access.

---

## 🔒 Security

- Keep API credentials private.
- Avoid uploading API keys to public Git repositories.
- Use a secure backend for production API access.
- Do not commit signing keys or passwords.

---

## 📌 Project Information

**Project Name:** BOOMGRATULATIONS

**Version:** 1.0.0+1

**Framework:** Flutter

**Platform:** Android

**Category:** Football and Sports

---

## 📄 License

All rights reserved unless a separate license is provided.

---

### BOOMGRATULATIONS

**Football. Predictions. Results. All in One Place.**
