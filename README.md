# Letea: mobile app for Android and iOS

One Flutter codebase that builds both the Android app (Play Store) and the iOS app (App Store). Firebase is the backend: phone login, database, file storage, push notifications and server functions.

## What's inside

| Part | Where | What it does |
|---|---|---|
| Customer app | `lib/screens/customer/` | Browse and search, cart, checkout (M-Pesa, Airtel Money, cash), prescription photo, product pages with photo galleries, pin delivery spot on a map, live order tracking on a street map with road route and arrival time, delivery PIN |
| Provider app | `lib/screens/provider/` | Register a business and pin the shop on the map, post products/services with up to 5 photos each (camera or gallery), edit listings, accept or decline orders, track the rider coming to collect, view prescriptions |
| Rider app | `lib/screens/rider/` | Go online/offline, see open jobs, accept (first rider wins), GPS sharing during the trip, confirm delivery with PIN, earnings |
| Login | `lib/screens/auth/` | Phone number + SMS code. One account can be customer, provider and rider |
| Security rules | `firestore.rules`, `storage.rules` | Who can see and change what. Customers can't see other people's orders, riders only see open jobs and their own trips |
| Server functions | `functions/` | Prices re-checked on the server, order creation, PIN check (5 tries max), push notifications, payment hooks |

### How an order moves

```
Customer places order ──► createOrders function (checks prices, makes PIN)
Provider: Accept ──► Mark packed            (service: Accept ──► Start trip)
Rider: Accept job ──► Picked up, start trip (GPS shared every ~50 m)
Rider enters customer's PIN ──► confirmDelivery function ──► Delivered
```
Each step sends a push notification to the next person.

---

## Install a preview on your phone

### Fastest: preview mode (no setup)
Every build from this repo works on its own until you connect Firebase. It runs in **preview mode** (a "PREVIEW" ribbon in the corner):
- Sample shops in Dar es Salaam, a pharmacy, a kitchen, fundis and a laundry.
- Sign in with **any Tanzanian number** and the code **123456**. No SMS is sent.
- Place an order and watch the sample shop accept it and the sample rider, Juma, ride along real Dar es Salaam roads to the shop and then to you, on a live street map.
- Register as a provider and post listings with photos from your camera or gallery. Sample items show category artwork until shops add their own photos.
- Use a second number to try being a provider or a rider. Register as a rider and switch **Online** to take jobs yourself.
- Data stays on that phone and resets when the app is closed.

Download: repo → **Actions** → latest **Android preview APK** run → **Artifacts → letea-android-preview** → unzip → install `letea-preview.apk` (allow **Install unknown apps**).

### Connected to your real database

### Android: build the APK on GitHub (no Flutter needed on your computer)
GitHub builds the app for you and gives you an `.apk` file to install.

1. **Firebase project.** At https://console.firebase.google.com create a project, upgrade it to **Blaze**, and turn on **Authentication → Phone**, **Firestore** (location `europe-west1`) and **Storage** (setup step 3, parts 1–3).
2. **Service account key.** Firebase Console → ⚙ Project settings → **Service accounts** → **Generate new private key**. A `.json` file downloads.
   Then in https://console.cloud.google.com/iam-admin/iam (same project) find that account (`firebase-adminsdk-…`), click ✏ and add the role **Editor**, so it can deploy functions and register the app. This key is powerful: never share it or put it in the code.
3. **GitHub repo.** Create a free account at https://github.com, make a **private** repository, and upload this whole folder (including the hidden `.github` folder). If drag-and-drop skips `.github`, use GitHub Desktop or `git push`.
4. **Secrets.** In the repo: **Settings → Secrets and variables → Actions → New repository secret**:
   - `FIREBASE_PROJECT_ID`: the project id (Project settings → General)
   - `FIREBASE_SERVICE_ACCOUNT`: paste the entire contents of the `.json` file
5. **Build.** Repo → **Actions** → **Android preview APK** → **Run workflow**. It takes about 10–15 minutes and also deploys the database rules and server functions.
6. **First run only:** open the finished run and download **letea-android-preview**. Inside:
   - `SAVE-AS-ANDROID_KEYSTORE_BASE64-secret.txt`: save its contents as a new secret named `ANDROID_KEYSTORE_BASE64`, so every future build has the same signature.
   - `fingerprints-add-to-firebase.txt`: add both lines (SHA1 and SHA256) in Firebase → Project settings → your Android app → **Add fingerprint**. Phone login needs this.
   - Then run the workflow once more.
7. **Install.** Download the new `letea-preview.apk` on your Android phone (or send it via WhatsApp/Drive), tap it, and allow **Install unknown apps** when asked. Share the same file with your test shops and riders.
8. **Testing without SMS costs:** Firebase → Authentication → Phone → **Phone numbers for testing**, e.g. `+255700000001` with code `123456`.

### iPhone (no Mac needed)
GitHub builds the iPhone app on its Mac computers (workflow **iOS build**, about 30–45 minutes). Every build:
- checks that the app opens and tracks a delivery on a virtual iPhone, and saves screenshots to the **ios-screenshots** branch;
- puts **letea-ios-unsigned.ipa** on the **ios-preview** release:
  https://github.com/nyangehance-netizen/jaza/releases/tag/ios-preview

Apple doesn't let iPhones install an app straight from a file. There are two ways to get it on a phone:

**A. Your own iPhone, free (needs a Windows PC or Mac for 10 minutes)**
1. On the computer, install **iTunes** (Windows, from apple.com, not the Microsoft Store) and **Sideloadly** (sideloadly.io).
2. Download `letea-ios-unsigned.ipa` from the ios-preview release above.
3. Connect the iPhone with a cable and tap **Trust** on the phone.
4. Open Sideloadly, drag in the IPA, enter your Apple ID and press **Start**. Sideloadly signs the app with your Apple ID.
5. On the iPhone:
   - **Settings → General → VPN & Device Management** → tap your Apple ID → **Trust**.
   - On iOS 16 or newer, also turn on **Settings → Privacy & Security → Developer Mode** and restart when asked.
6. Open Letea. With a free Apple ID the app stops opening after **7 days**: run Sideloadly again to renew it. Good for your own testing, not for customers.

**B. TestFlight, for testers and real users ($99/year Apple Developer Program)**
1. Join the Apple Developer Program at developer.apple.com.
2. In **App Store Connect → Apps → +**, create the app: name *Letea*, bundle ID **com.letea.letea**. If that ID is taken, pick another and change `BUNDLE_ID` in `.github/workflows/ios.yml` and `--org` in both workflows.
3. In **App Store Connect → Users and Access → Integrations → App Store Connect API**, create a key with **Admin** access and download the `.p8` file. It can only be downloaded once.
4. Add four GitHub secrets:
   - `APPLE_TEAM_ID`: from developer.apple.com → Account → Membership.
   - `ASC_KEY_ID` and `ASC_ISSUER_ID`: both shown on the API keys page.
   - `ASC_KEY_P8`: open the `.p8` file in Notepad and paste all of it.
5. Run **iOS build** again. It signs the app and uploads it to TestFlight by itself.
6. In **App Store Connect → TestFlight**, add testers by email. They install Apple's **TestFlight** app, then Letea. Builds last 90 days, and each new build updates their app.

**Phone login and notifications on iPhone** (only once Firebase is connected): upload an **APNs key** (developer.apple.com → Keys → +, tick *Apple Push Notifications service*) to Firebase Console → Project settings → Cloud Messaging → Apple app. The build adds the login URL scheme and push settings automatically.

### Both, right now: the web preview
Until the apps are built, open the **Letea Live** link on any phone and use the browser's **Add to Home screen**. It opens like an app and uses the same order flow.

---

## Setup (about 1–2 hours the first time)

You only need this section to build on your own computer. GitHub builds both apps for you without it. Building iOS yourself needs a **Mac with Xcode**; Android works on Windows, Mac or Linux.

### 1. Install the tools
- Flutter SDK: https://docs.flutter.dev/get-started/install (then run `flutter doctor` and fix what it lists)
- Node.js 20 or newer: https://nodejs.org
- Firebase CLI: `npm install -g firebase-tools`, then `firebase login`
- FlutterFire CLI: `dart pub global activate flutterfire_cli`

### 2. Create the Android and iOS project folders
Inside this folder run:
```bash
flutter create . --org com.letea --project-name letea --platforms android,ios
flutter pub get
```
This adds the `android/` and `ios/` folders without touching the code in `lib/`.
Change `com.letea` to your own reverse domain. It becomes your app ID and cannot be changed after you publish.

### 3. Create the Firebase project
1. Go to https://console.firebase.google.com, create a project named **letea**.
2. Upgrade to the **Blaze (pay as you go)** plan. Cloud Functions need it. Small apps usually stay inside the free allowance; set a budget alert.
3. Turn on:
   - **Authentication → Sign-in method → Phone**
   - **Firestore Database** (production mode). For the location pick `europe-west1`, the same region the functions use.
   - **Storage**
4. Connect the app:
   ```bash
   flutterfire configure --project=<your-firebase-project-id> --platforms=android,ios
   ```
   This replaces `lib/firebase_options.dart` and adds `google-services.json` (Android) and `GoogleService-Info.plist` (iOS).

### 4. Deploy rules, indexes and functions
```bash
firebase use <your-firebase-project-id>
cd functions && npm install && cd ..
firebase deploy --only firestore,storage,functions
```
For prescriptions: in Google Cloud Console → IAM, give the **App Engine / Compute default service account** the role **Service Account Token Creator**. The pharmacy's private prescription links need it.

### 5. Maps (no key needed)
Maps use **OpenStreetMap** street tiles and road routes from an **OSRM** routing server, so there is no API key or billing to set up. The free public servers are fine for testing and a small launch, but their rules ask busy apps to move to a paid provider. When you grow, change the two URLs in `lib/services/map_config.dart` (tile servers such as MapTiler, Stadia Maps or Thunderforest; routing from a hosted OSRM, GraphHopper or similar). Riders' **Directions** button opens Google Maps (or any maps app) for turn-by-turn navigation.

---

## Android setup

**`android/app/build.gradle`** (or `build.gradle.kts`), in `defaultConfig`:
```
minSdk = 23
```

**`android/app/src/main/AndroidManifest.xml`**, above `<application>`:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```
Before `</manifest>` (lets riders open directions in a maps app):
```xml
<queries>
  <intent>
    <action android:name="android.intent.action.VIEW"/>
    <data android:scheme="https"/>
  </intent>
</queries>
```

**Phone login on Android:** Firebase needs your app's signing fingerprints.
```bash
cd android && ./gradlew signingReport
```
Copy the **SHA-1** and **SHA-256** into Firebase Console → Project settings → your Android app. Do this again for your release key and for the Play Store's app signing key (Play Console → Setup → App signing).

Run it: plug in a phone with USB debugging on, then `flutter run`.

## iOS setup on your own Mac (optional: GitHub does all of this for you)

Open `ios/Runner.xcworkspace` in Xcode.

1. **Runner → Signing & Capabilities:** choose your Apple Developer team. Add the capabilities **Push Notifications** and **Background Modes → Remote notifications**.
2. **Minimum iOS version:** set the deployment target to **15.0** (General tab), and at the top of `ios/Podfile`: `platform :ios, '15.0'`.
3. **`ios/Runner/Info.plist`**, add:
   ```xml
   <key>NSLocationWhenInUseUsageDescription</key>
   <string>Letea uses your location to pin your delivery address and, for riders, to show customers where their order is.</string>
   <key>NSCameraUsageDescription</key>
   <string>Take a photo of your prescription or of products you sell.</string>
   <key>NSPhotoLibraryUsageDescription</key>
   <string>Choose photos of products you sell.</string>
   ```
4. **Phone login on iOS:** in Info.plist add a URL type whose scheme is the `REVERSED_CLIENT_ID` from `GoogleService-Info.plist`:
   ```xml
   <key>CFBundleURLTypes</key>
   <array><dict><key>CFBundleURLSchemes</key><array><string>com.googleusercontent.apps.XXXX</string></array></dict></array>
   ```
5. **Push notifications:** in the Apple Developer site create an **APNs Auth Key (.p8)**, then upload it in Firebase Console → Project settings → Cloud Messaging → Apple app configuration. Phone login also uses this to skip the reCAPTCHA screen.
   Then make the small edit described in the comment above `startMobilePayment` in `functions/index.js`, and run `firebase deploy --only functions`.
4. Give the provider your webhook URL (shown after deploy, ends in `/paymentWebhook`).

### 8. Verify pharmacies
Prescription medicine can only be listed by providers marked verified. After checking a pharmacy's licence, set `provider.verified = true` on their document in Firestore (`users/<their uid>`). To let staff do this from the app later, give them an `admin` custom claim with the Firebase Admin SDK.

---

## Publishing

**Google Play** ($25 one-time developer fee):
1. Create an upload key and set up release signing: https://docs.flutter.dev/deployment/android
2. `flutter build appbundle`
3. Upload `build/app/outputs/bundle/release/app-release.aab` in Play Console. Fill in the data-safety form (you collect phone number, location, photos), add a privacy policy URL, and start with **Internal testing**.

**Apple App Store** ($99 per year Apple Developer Program):
1. `flutter build ipa`
2. Upload with Xcode Organizer or Transporter, test through **TestFlight**, then submit for review.
3. Apple asks for a demo login. Give them a test phone number and code from step 6.

## Before a public launch
- Write a privacy policy and terms. Tanzania's Personal Data Protection Act 2022 applies, and you handle health data (prescriptions).
- Pharmacies must hold valid licences; keep the verification step strict.
- Decide your commission. The code charges a flat TSh 2,000 delivery fee (`DELIVERY_FEE` in `functions/index.js` and `deliveryFee` in `lib/state/cart.dart`); change both together.
- Set a Firebase budget alert and turn on App Check to block fake app traffic.
- Riders share location only while the app is open on a trip. Background tracking needs extra store approval; add it later if needed.

## Project map
```
lib/
  main.dart                 app start
  theme.dart                colours and shapes (Letea green + mango)
  models/models.dart        users, listings, orders, order steps
  services/                 auth (SMS), database, location, push notifications
  state/cart.dart           cart on the phone
  widgets/common.dart       shared pieces (status chip, order summary, messages)
  screens/gate.dart         login check + role switcher
  screens/auth/             phone login, register as customer/provider/rider
  screens/customer/         browse, cart/checkout, orders, live tracking
  screens/provider/         orders, listings, post listing, business
  screens/rider/            jobs, trips with GPS, earnings
functions/
  index.js                  orders, PIN check, payments, notifications
  payments.js               connect your mobile money provider here
firestore.rules             database security
storage.rules               photo and prescription security
firestore.indexes.json      database indexes
```
