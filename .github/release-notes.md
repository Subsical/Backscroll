Pick the file for your system:

| System | File | First run |
| --- | --- | --- |
| Windows 10 or 11, 64-bit | `backscroll-windows-x64.zip` | Unzip it anywhere and run `backscroll.exe`. $WINDOWS_FIRST_RUN |
| Linux, 64-bit | `backscroll-linux-x64.tar.gz` | Extract it and run `backscroll/backscroll`. It needs GTK 3, WebKitGTK 4.1 and libsecret, which most desktops already have. |
| Android 7.0 or newer | `backscroll-android.apk` | Open the file on your phone and allow installing apps from your browser or file manager when asked. Later versions install over it. |

## Checking a download

`SHA256SUMS.txt` lists the SHA-256 checksum of every file, and `SHA256SUMS.txt.asc` is a GPG signature of that list by the key `$GPG_FINGERPRINT`, which is also at https://github.com/$OWNER.gpg:

```sh
curl -sL https://github.com/$OWNER.gpg | gpg --import
gpg --verify SHA256SUMS.txt.asc SHA256SUMS.txt
sha256sum --check --ignore-missing SHA256SUMS.txt
```

The APK is signed with the certificate whose SHA-256 fingerprint is `$APK_FINGERPRINT`. $WINDOWS_SIGNATURE
