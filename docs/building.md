# Building and releasing

## Checking a download

Each release lists the SHA-256 checksum of every file in `SHA256SUMS.txt`, and `SHA256SUMS.txt.asc` is my GPG signature of that list. The key is published at [github.com/Subsical.gpg](https://github.com/Subsical.gpg) and its fingerprint is in the release notes:

```sh
curl -sL https://github.com/Subsical.gpg | gpg --import
gpg --verify SHA256SUMS.txt.asc SHA256SUMS.txt
sha256sum --check --ignore-missing SHA256SUMS.txt
```

The release notes also give the fingerprint of the certificate the APK is signed with, which `apksigner verify --print-certs` shows, and the thumbprint of the certificate the Windows app is signed with. Windows shows that one under the file's Properties → Digital Signatures, and PowerShell prints it with `(Get-AuthenticodeSignature backscroll.exe).SignerCertificate.Thumbprint`.

## Building from source

You need [Flutter](https://docs.flutter.dev/get-started/install) 3.47 or newer, plus the usual toolchain for the platform you build on.

```sh
git clone https://github.com/Subsical/Backscroll.git
cd Backscroll
flutter pub get
flutter run
```

Release builds:

| Platform | Command | Output |
| --- | --- | --- |
| Windows | `flutter build windows` | `build/windows/x64/runner/Release/` |
| Linux | `flutter build linux` | `build/linux/x64/release/bundle/` |
| Android | `flutter build apk` | `build/app/outputs/flutter-apk/app-release.apk` |

On Linux the login window and the keychain need a few system packages. On Debian or Ubuntu:

```sh
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev \
  libwebkit2gtk-4.1-dev libsoup-3.0-dev libsecret-1-dev
```

The Android app needs Android 7.0 or newer.

## Tests

```sh
flutter test
```

The tests talk to a fake Discord API, so they need no token. They cover the API client and rate limits, channel permissions, the markdown parser, the HTML, JSON and CSV writers, pins-only exports, searching and jumping to a result, resuming after a crash (the output has to be byte for byte the same as an uninterrupted run), converting between formats (which has to give the same file as exporting in that format), the upload queue and every host.

The pictures in the README come from the tests in `test/screenshots`. `app_screens_test.dart` renders the app screens and the frames of the GIF, and `sample_export_test.dart` writes the sample exports to `build/screenshots/export`, which were then opened in a browser:

```sh
SCREENSHOTS=$PWD/build/screenshots flutter test test/screenshots
```

Set `TWEMOJI_DIR` to a folder of Twemoji 72x72 PNGs to get emoji in the app screens.

The game screenshots, avatars and icons in the sample server are real images under the MIT license, from Godot's demo projects, Kenney's starter kits and Microsoft's Fluent Emoji; [`SOURCES.md`](../test/screenshots/images/SOURCES.md) lists each one.

The engine in `lib/core` is plain Dart with no Flutter imports; `lib/app` is the interface.

## Publishing a release

GitHub Actions builds the Windows, Linux and Android versions and publishes them as a release. Either push a tag:

```sh
git tag v1.0.0-beta.2
git push origin v1.0.0-beta.2
```

or open the **build** workflow under **Actions**, press **Run workflow** and enter the version. Versions with a hyphen, like `1.0.0-beta.2`, become pre-releases, and plain ones like `1.0.0` normal releases. The version also shows up on the app's About page.

## Signing

A release signs the APK, the Windows app and the checksum list, and stops if any of the secrets below is missing. Builds without a version only sign what they have secrets for, so they still work in a fork. Secrets go under **Settings → Secrets and variables → Actions**.

**Android.** Android only installs a new version over an old one when both are signed with the same key. Create the key once:

```sh
keytool -genkeypair -keystore backscroll.jks -alias backscroll -keyalg RSA -keysize 4096 -validity 10000
base64 -w0 backscroll.jks
```

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE` | The base64 text from above |
| `ANDROID_KEYSTORE_PASSWORD` | The password you chose |
| `ANDROID_KEY_ALIAS` | `backscroll` |
| `ANDROID_KEY_PASSWORD` | Only needed if the key has its own password |

Keep `backscroll.jks` somewhere safe, because an APK signed with any other key can't update the installed app. To sign local builds with it as well, put `storeFile` (relative to `android/app`), `storePassword`, `keyAlias` and `keyPassword` into `android/key.properties`, which git ignores.

**Windows.** The build signs with [Jsign](https://github.com/ebourg/jsign). The free way is a self-signed certificate. Windows doesn't trust one, so SmartScreen still warns on the first run, but every release carries the same signature, and its thumbprint is in the release notes to compare against. Create it once:

```sh
keytool -genkeypair -keystore backscroll-windows.pfx -storetype PKCS12 -alias backscroll -keyalg RSA -keysize 4096 -validity 3650 -dname "CN=Your Name" -ext EKU=codeSigning -ext KU=digitalSignature
base64 -w0 backscroll-windows.pfx
```

| Secret | Value |
| --- | --- |
| `WINDOWS_SIGN_STORETYPE` | `PKCS12` |
| `WINDOWS_SIGN_FILE` | The base64 text from above |
| `WINDOWS_SIGN_STOREPASS` | The password you chose |
| `WINDOWS_SIGN_ALIAS` | `backscroll` |

The same step can also sign with a certificate from a CA, because Jsign works with the cloud signing services those come with. Its [documentation](https://ebourg.github.io/jsign/) lists the store types and what each one expects in these secrets.

**Checksums.** The release job signs `SHA256SUMS.txt` with GPG. Create a key for it and export both halves:

```sh
gpg --quick-generate-key "Your Name <you@example.com>" ed25519 sign never
gpg --export-secret-keys you@example.com | base64 -w0    # the private key, for the secret
gpg --armor --export you@example.com                     # the public key
```

Add the public key to your GitHub account under **Settings → SSH and GPG keys**, which publishes it at `github.com/<you>.gpg` where the release notes point.

| Secret | Value |
| --- | --- |
| `GPG_PRIVATE_KEY` | The exported private key, base64 encoded |
| `GPG_PASSPHRASE` | Its passphrase, if it has one |
