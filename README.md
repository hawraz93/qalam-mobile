# Al-Qalam mobile app

Flutter (Android) app for Al-Qalam University staff and teachers: notification inbox, IT
tickets, complaints and contact messages for the teams that handle them, the user's own
tickets, account settings, and the teacher's academic portfolio (profile, photo, CV, office
hours, education, teaching, research).

It talks to the website's API at `https://alqalam.edu.iq/api/v1`. The API lives in the
website repository ([hawraz93/qalam-website](https://github.com/hawraz93/qalam-website),
`app/Http/Controllers/Api/Mobile`, `routes/api.php`).

## Run locally

Requirements: Flutter 3.47 (stable), Android SDK, a phone with USB debugging or an emulator.

```
flutter pub get
flutter run
```

Against a local copy of the website (the Android emulator reaches the PC at `10.0.2.2`):

```
php artisan serve                                             # in the website project
flutter run --dart-define=API_BASE=http://10.0.2.2:8000/api/v1
```

Push notifications need `android/app/google-services.json` from the Firebase project
`al-qalam-13487` (already in the repo). Without it the app still runs; only push is off.

## Release a new version

1. Bump `version:` in `pubspec.yaml` (for example `1.5.0+7`) and `S.appVersion` in
   `lib/strings.dart`, commit, push.
2. Tag and push the tag:

   ```
   git tag v1.5.0
   git push origin v1.5.0
   ```

3. GitHub Actions builds a signed APK and publishes it under **Releases** as
   `al-qalam-v1.5.0.apk`. Copy the asset link.
4. On the website: Notification settings → Mobile app → set "Latest version" to `1.5.0`
   and paste the link into "APK download link" (set "Minimum allowed version" when older
   apps must update). Phones show an update prompt the next time the app opens.

The tag must match the `pubspec.yaml` version or the workflow stops.

### Signing

Release builds are signed with the keystore described in `android/key.properties`
(never committed). Keep the keystore file and its passwords somewhere safe: an APK
signed with a different key cannot be installed over an existing install.

- Locally: `android/key.properties` points at the keystore outside the repo.
- GitHub Actions reads these repository secrets (Settings → Secrets and variables → Actions):

  | Secret | Value |
  | --- | --- |
  | `ANDROID_KEYSTORE_BASE64` | the `.jks` file encoded with base64 |
  | `ANDROID_KEYSTORE_PASSWORD` | keystore password |
  | `ANDROID_KEY_ALIAS` | key alias |
  | `ANDROID_KEY_PASSWORD` | key password |

Without the secrets the release workflow fails on purpose rather than producing a
debug-signed APK.

## Layout

| Path | What |
| --- | --- |
| `lib/main.dart` | app shell, sign-in, bottom navigation, update and push-health banners |
| `lib/theme.dart`, `lib/widgets.dart` | design system: colours, Vazirmatn font, cards, lists, pickers |
| `lib/screens/home.dart` | dashboard |
| `lib/screens/inbox.dart`, `tickets.dart`, `complaints.dart`, `contacts.dart`, `work.dart` | lists and detail screens |
| `lib/screens/account.dart` | account, password, language, app lock, notification settings |
| `lib/screens/teacher.dart`, `portfolio.dart` | academic profile and its lists |
| `lib/push.dart` | Firebase messaging, device registration, phone-side notification checks |
| `lib/lock.dart` | PIN / fingerprint lock |
| `lib/update.dart` | version check against `/config` |
| `lib/strings.dart` | Arabic, Kurdish and English texts |
| `android/app/src/main/kotlin/.../MainActivity.kt` | native bridge for notification and battery settings pages |

Texts live in `lib/strings.dart` under three maps (`ar`, `ckb`, `en`); add a key to all three.
