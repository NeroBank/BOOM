BOOMGRATULATIONS — Upgrade build

This is a separate upgrade workspace. It does not overwrite the existing NeroBank/BOOM repository.


Included


Red/black BOOM interface and recovered logo/font assets

API-Football fixtures and live fixtures

BOOM Picks information page (clearly labelled as informational, not guaranteed AI output)

Device-local match History (save matches from fixture cards)

In-app notification inbox and preference toggle

BOOM Pro information showing the recovered ₦2,000 monthly plan reference

Optional Supabase SDK initialization using the existing project URL and publishable key

GitHub Actions workflow to generate Android scaffolding and build an APK


Important integration status


Supabase URL points to the existing project. The publishable key is passed at build time.

The existing profiles and subscriptions tables are not modified. Their exact schema and RLS rules still need source-side verification before writing user/subscription data.

Paystack checkout is intentionally not enabled in this build. The existing secure Supabase Edge Function/webhook must be recovered and tested before payment collection is turned on.

History and notifications in this upgrade are stored locally on the device. Cloud sync and Android push notifications require backend/FCM integration in a later verified step.

API-Football key is supplied as a GitHub Actions secret named API_FOOTBALL_KEY.

Supabase secrets are SUPABASE_URL and SUPABASE_ANON_KEY.


Build

Push this project to a GitHub repository, then open Actions → Build BOOMGRATULATIONS Android APK → Run workflow.
The APK appears under the completed workflow run's Artifacts section.


Safety

Do not commit Paystack secret keys, Supabase service-role keys, signing passwords, or private API credentials.

