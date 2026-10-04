# Letea: mobile app for Android and iOS

One Flutter codebase that builds both the Android app (Play Store) and the iOS app (App Store). Firebase is the backend: phone login, database, file storage, push notifications and server functions.

## What's inside

| Part | Where | What it does |
|---|---|---|
| Customer app | `lib/screens/customer/` | Browse and search, cart, checkout (M-Pesa, Airtel Money, cash), prescription photo, live order tracking on Google Maps, delivery PIN |
| Provider app | `lib/screens/provider/` | Register a business, post products/services with photos, accept or decline orders, mark packed, view prescriptions |
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
- Place an order and watch the sample shop accept it and the sample rider, Juma, collect it and ride to you on the map.
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
   - `MAPS_API_KEY`: your Google Maps key (setup step 5). Optional for a first look: without it the tracking map is blank.
5. **Build.** Repo → **Actions** → **Android preview APK** → **Run workflow**. It takes about 10–15 minutes and also deploys the database rules and server functions.
6. **First run only:** open the finished run and download **letea-android-preview**. Inside:
   - `SAVE-AS-ANDROID_KEYSTORE_BASE64-secret.txt`: save its contents as a new secret named `ANDROID_KEYSTORE_BASE64`, so every future build has the same signature.
   - `fingerprints-add-to-firebase.txt`: add both lines (SHA1 and SHA256) in Firebase → Project settings → your Android app → **Add fingerprint**. Phone login needs this.
   - Then run the workflow once more.
7. **Install.** Download the new `letea-preview.apk` on your Android phone (or send it via WhatsApp/Drive), tap it, and allow **Install unknown apps** when asked. Share the same file with your test shops and riders.
8. **Testing without SMS costs:** Firebase → Authentication → Phone → **Phone numbers for testing**, e.g. `+255700000001` with code `123456`.

### iPhone: TestFlight
Apple does not allow installing apps from a file. iPhone testers install through Apple's **TestFlight** app:
1. Join the Apple Developer Program ($99/year).
2. On a Mac, complete the iOS setup below, then run `flutter build ipa` and upload with Xcode → Organizer.
3. In App Store Connect → TestFlight, add testers by email. They install the **TestFlight** app and then Letea.

No Mac? Cloud build services that support Flutter (for example Codemagic) can build and send the app to TestFlight from your GitHub repo. You still need the Apple Developer account.

### Both, right now: the web preview
Until the apps are built, open the **Letea Live** link on any phone and use the browser's **Add to Home screen**. It opens like an app and uses the same order flow.

---

## Setup (about 1–2 hours the first time)

You need a computer. iOS builds need a **Mac with Xcode**; Android works on Windows, Mac or Linux.

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

### 5. Google Maps key
In Google Cloud Console (same project) enable **Maps SDK for Android** and **Maps SDK for iOS**, then create an API key and restrict it to your app.

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
Inside `<application>`:
```xml
<meta-data android:name="com.google.android.geo.API_KEY" android:value="YOUR_MAPS_KEY"/>
```

**Phone login on Android:** Firebase needs your app's signing fingerprints.
```bash
cd android && ./gradlew signingReport
```
Copy the **SHA-1** and **SHA-256** into Firebase Console → Project settings → your Android app. Do this again for your release key and for the Play Store's app signing key (Play Console → Setup → App signing).

Run it: plug in a phone with USB debugging on, then `flutter run`.

## iOS setup (on a Mac)

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
6. **Google Maps:** in `ios/Runner/AppDelegate.swift`:
   ```swift
   import GoogleMaps
   // inside application(_:didFinishLaunchingWithOptions:), before GeneratedPluginRegistrant:
   GMSServices.provideAPIKey("YOUR_MAPS_KEY")
   ```
7. In Terminal: `cd ios && pod install && cd ..`, then `flutter run` with an iPhone connected.

---

### 6. Test with real phones
Use Firebase Console → Authentication → Phone → **Phone numbers for testing** to add fake numbers with fixed codes, so you can test without SMS costs. Then use three phones (or one phone switching roles from the ⇄ menu): customer orders, provider accepts and packs, rider accepts and delivers.

### 7. Turn on mobile money
Cash on delivery works now. For M-Pesa / Airtel Money:
1. Sign up with a Tanzanian payment provider. You can go direct to each network or use an aggregator that covers all networks. You will need your business registration (BRELA), TIN and a bank account.
2. Fill in `functions/payments.js` with their API (the file shows exactly where).
3. Store keys as secrets and redeploy:
   ```bash
   firebase functions:secrets:set PAYMENT_API_KEY
   firebase functions:secrets:set PAYMENT_WEBHOOK_SECRET
   ```
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
