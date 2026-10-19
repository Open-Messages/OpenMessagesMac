# OpenMessages for Mac

A SwiftUI app that shows the verification codes synced from [OpenMessages](https://github.com/Open-Messages/OpenMessages) on your Android phone. Codes are encrypted on the phone and decrypted only on this Mac, using a sync key that only you know.

- A main window lists recent codes, with copy and delete for each one.
- A menu bar item shows the latest five codes. Click one to copy it.
- Optional notification and auto-copy when a new code arrives.
- New codes appear within about 5 seconds. Expired codes (older than 24 hours) are hidden.

## How it works

The app uses no Firebase SDK. It talks to Firebase directly over REST:

1. **Google sign-in.** It uses the OAuth authorization code flow with PKCE, shown in an `ASWebAuthenticationSession` sheet. The OAuth client comes from your Firebase Apple app (`CLIENT_ID` and `REVERSED_CLIENT_ID`).
2. **Firebase Auth.** It exchanges the Google ID token through `accounts:signInWithIdp`, then refreshes tokens through `securetoken.googleapis.com`.
3. **Firestore.** It reads `users/{uid}.otpSync` to get the key parameters. It then polls `users/{uid}/otps` with a `createdAt >=` cursor, so each poll reads only new records.
4. **Decryption.** It derives the key with PBKDF2-HMAC-SHA256 (CommonCrypto) and opens each record with AES-256-GCM (CryptoKit). The format is specified in [`OpenMessages/docs/otp-sync.md`](https://github.com/Open-Messages/OpenMessages/blob/main/docs/otp-sync.md).

Because there is no Firebase SDK, the app needs no keychain-sharing entitlement or provisioning profile. It runs with an ad-hoc signature. The Firebase session and the derived sync key are stored in your login keychain. The passphrase itself is not stored.

## Setup

1. Follow the Firebase setup in [`OpenMessages/docs/otp-sync.md`](https://github.com/Open-Messages/OpenMessages/blob/main/docs/otp-sync.md). Your Firebase project needs Google sign-in enabled, Firestore created and the rules deployed.
2. In the same Firebase project, add an **Apple app** with bundle ID `com.hummcare.messages.mac`, then download its `GoogleService-Info.plist`.
3. Build the app:

   ```sh
   scripts/build-app.sh path/to/GoogleService-Info.plist   # → build/OpenMessages.app
   open build/OpenMessages.app
   ```

   Alternatively, put the plist in `~/Library/Application Support/OpenMessages/` and build without an argument.
4. On the phone, open Messages › Settings › OTP sync. Sign in, create a sync key and turn on **Sync verification codes**.
5. On the Mac, sign in with the same Google account and enter the sync key.

## Development

```sh
swift build        # debug build
swift run          # runs without a bundle: no notifications, and sign-in still works
swift test         # crypto tests that share a test vector with the Android app
```

Requirements: macOS 14 or later, and Xcode 16 or later (Swift 6 toolchain).

## Notes

- **Firestore reads.** Each poll costs about one read, even when nothing changes. At a 5-second interval that is about 17,000 reads per day while the app runs. Change `AppModel.pollInterval` if you need fewer.
- **Changing the key.** If you change the sync key on the phone, the Mac notices the new salt within about 5 minutes, or straight away when you click Refresh, and asks for the new key.
- **Keychain prompts.** An ad-hoc signature changes with every rebuild, so macOS may ask once to allow keychain access after you rebuild.
- **Distribution.** Before you share the app, sign it with a Developer ID and notarize it.
