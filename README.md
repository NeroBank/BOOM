# BOOMGRATULATIONS Flutter app

A compact red-themed football app starter with Fixtures, Live, Picks, Results and Account screens.

## Included
- League/country grouping, countries sorted A–Z in the filter list
- Fixture start time, country flag, league name/badge emoji, stadium name and 1/X/2 sample odds
- League-position badges: 1–3 green, 4–15 blue, 16+ red with a crying emoji
- Recent form indicators using green W, gold D and red L
- Responsive Flutter UI and Android APK GitHub Actions workflow
- Optional API-Football API-key build variable; API key is not hardcoded

## Important data note
With a valid API-Football key, the app maps the `/fixtures` response for the selected date or live fixtures, retrieves `/standings` by league and season for team ranks, uses `/fixtures?last=50&status=FT-AET-PEN` for recent results, and attempts `/odds?date=YYYY-MM-DD` to map Match Winner Home/Draw/Away prices into 1/X/2. Match times are requested in the Africa/Lagos timezone. API coverage and quota depend on your plan; unavailable odds show as em dashes, and missing stadiums show as “Stadium not listed”. The included fallback demo rows are illustrative only and must not be treated as verified match data or betting advice. API-Football's documented endpoints and response behavior: https://www.api-football.com/documentation_v3.

## Build an APK using GitHub Actions
1. Create a GitHub repository named `boomgratulations`.
2. Upload the contents of this ZIP to the repository root (not the ZIP file itself).
3. Open **Settings → Secrets and variables → Actions → New repository secret**.
4. Name the secret `API_FOOTBALL_KEY` and paste your private API-Football key. You can skip this for demo mode.
5. Open **Actions → Build BOOMGRATULATIONS Android APK → Run workflow**.
6. When the workflow finishes, open the successful run and download the `boomgratulations-release-apk` artifact.
7. Extract the downloaded artifact ZIP on your phone and install `app-release.apk`. Android may ask you to allow installs from that source.

## Build locally
Install Flutter SDK and Android SDK, then run:
```bash
flutter create . --platforms android --project-name boomgratulations
flutter pub get
flutter run
flutter build apk --release
```

## Font note
The app requests the `Times New Roman` font family. Android devices may not have that exact font installed, so Android can substitute a serif font unless the font file is licensed and bundled into the project.

## Troubleshooting
- If Android says “App not installed”, uninstall an older app with the same package/signing identity or build a fresh APK.
- GitHub Actions creates the APK; this ZIP is source/configuration, not a prebuilt APK.
- Do not commit API keys into Dart source or Git history.
