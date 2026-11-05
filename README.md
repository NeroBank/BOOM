BOOMGRATULATIONS — Android upgrade

This Flutter project preserves the supplied BOOMGRATULATIONS logo and Montserrat fonts.


Included


Home, Live, Picks, History, Alerts, Pro and Account sections

Light, dark and system appearance options

API-Football fixtures and live scores

Selectable league standings seasons

League positions and last-five W/D/L form boxes under team names when standings data is available

Match analysis screen with each team's last five matches, head-to-head meetings and available match statistics

Local match history and in-app notifications

GitHub Actions APK build and Android launcher icon generation


Required GitHub Actions secret

Add API_FOOTBALL_KEY under repository Settings → Secrets and variables → Actions. The app cannot retrieve live football data without a valid API-Football key and an account plan that permits the requested endpoint/season.


Optional Supabase values are passed as SUPABASE_URL and SUPABASE_ANON_KEY build-time variables. Do not add service-role or Paystack secret keys to the mobile app.


Build

Push the contents of this folder to the repository root, then open Actions → Build BOOMGRATULATIONS Android APK → Run workflow. Download the BOOMGRATULATIONS-APK artifact from the completed run.


The GitHub workflow generates the Android platform folder, runs dependency resolution and static analysis, builds a release APK, and uploads it.

