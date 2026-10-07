# Al-Qalam Alerts (mobile app)

Flutter app for staff and teachers. It shows the notification inbox, lets the IT team,
complaints team and contact-us team handle their items, and lets every user follow the
tickets they opened. It talks to the Laravel API in this repository (`routes/api.php`, prefix `/api/v1`).

> This folder contains only the Dart source (`lib/`) and `pubspec.yaml`.
> It was written without a Flutter SDK on the machine, so it has **not been compiled yet**.
> Expect to fix small compile errors on the first `flutter run`.

## First-time setup

1. Install Flutter (3.19 or newer): https://docs.flutter.dev/get-started/install
2. Generate the Android / iOS projects inside this folder:

   ```
   cd mobile
   flutter create . --org iq.edu.alqalam --project-name qalam_notify --platforms android,ios
   flutter pub get
   ```

   `flutter create` keeps the existing `lib/` and `pubspec.yaml`. Delete the generated `test/widget_test.dart`.

3. Push notifications (Firebase), the short way — no Firebase CLI needed:

   1. https://console.firebase.google.com → Add project (name: Al-Qalam).
   2. In the project: Add app → Android → package name `iq.edu.alqalam.qalam_notify` → Register
      → Download `google-services.json` → put it in `mobile/android/app/`.
      The Gradle build picks it up automatically (see `android/app/build.gradle.kts`).
   3. Project settings → Cloud Messaging → make sure "Firebase Cloud Messaging API (V1)" is enabled.
   4. Project settings → Service accounts → Generate new private key → open the downloaded JSON,
      copy its whole content.
   5. On the website: Notifications settings → "Mobile App" section → paste the JSON, switch push on, save.
   6. Rebuild the app (`flutter build apk --release`), install it, sign in, then press
      "Send a test push to my phone" on the website.

   Without `google-services.json` the app still builds and runs, only push is off.

4. (Optional) `flutterfire configure` does the same as step 3.2 and also sets up iOS.

5. Run against the local site (Android emulator reaches the PC at `10.0.2.2`):

   ```
   php artisan serve            # in the Laravel project
   flutter run --dart-define=API_BASE=http://10.0.2.2:8000/api/v1
   ```

   Plain `http://` needs `android:usesCleartextTraffic="true"` in the debug `AndroidManifest.xml`.
   Release builds use `https://alqalam.edu.iq/api/v1` by default.

## Who sees what

| Tab | Shown to | API |
| --- | --- | --- |
| Notifications | everyone | `GET /notifications` |
| Tickets | users with `it_tickets.manage` | `/tickets` |
| Complaints | users with `complaint.manage` | `/complaints` |
| Messages | users with `contact.manage` | `/contacts` |
| My tickets | everyone (teachers follow replies and status here) | `/my/tickets` |

Permissions are the same Spatie permissions used by the website, so roles are managed in one place.

## Tickets without signing in

The sign-in screen has an "open an IT ticket without signing in" button (`POST /tickets/submit`).
An admin can switch it off from the website (IT tickets management → "Sign-in required to open tickets");
the button then disappears and the server refuses guest tickets. Signed-in users open tickets from the
"My tickets" tab, and those tickets are tied to their account.

## Teacher portfolio and account pages

The account menu (top corner) opens website pages inside the app, already signed in: academic profile,
education, teaching, research and biography for teachers, and the account page for everyone
(employees included). The app asks `POST /web-login` for a one-time link and loads it in a web view,
so these pages behave exactly as on the website and need no separate maintenance.
File uploads inside those pages (profile photo, research files) go through the `file_picker` package on Android.

## Before publishing

- iOS push needs an Apple Developer account and an APNs key uploaded to Firebase.
- Set the app icon and name (`flutter_launcher_icons` is the usual tool).
- Android: `flutter build appbundle`; iOS: `flutter build ipa`.
