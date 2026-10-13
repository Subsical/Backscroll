# Privacy policy

Backscroll exports your Discord conversations on your own device. There is no Backscroll server or account, and the app has no analytics, ads, tracking or crash reporting. Nothing about you is collected.

## What stays on your device

- **Your Discord token.** It is kept in your system's secure storage: the Secret Service on Linux, the Android Keystore on Android, and DPAPI encryption tied to your user account on Windows. It is only ever sent to discord.com. Logging an account out in Backscroll deletes its token.
- **Settings**, including the name and avatar of each account you added and the hosts you set up. Keys and passwords for hosts go into the same secure storage as tokens.
- **Export progress**, so an export can carry on after the app closes.
- **The upload cache**, a list of files that were already uploaded and where, so the same file isn't uploaded twice. You can clear it under Settings → Attachment hosts.
- **Your exports**, written to the folder you choose. What happens to them after that is up to you.

To remove everything Backscroll stored, log each account out and remove your hosts before uninstalling. On Android uninstalling alone is enough; on other systems the settings folder and keychain entries can outlive the app.

## Who Backscroll talks to

- **Discord** (discord.com, cdn.discordapp.com and media.discordapp.net), to read, search and export your conversations and download their attachments, avatars and emoji. Discord's own [privacy policy](https://discord.com/privacy) covers that.
- **The Discord login page.** **Log in with Discord** opens discord.com inside the app. Backscroll doesn't read what you type there. Once you're logged in it reads the token from the page, then deletes that page's cookies and storage.
- **jsDelivr** (cdn.jsdelivr.net), for the emoji images shown in the app. HTML exports also load emoji from jsDelivr and code highlighting from cdnjs (cdnjs.cloudflare.com) when someone opens them, and attachments that were kept as Discord links load from Discord. These services see the viewer's IP address and which file is requested.
- **Attachment hosts you set up yourself**, such as Catbox, ImgBB, an S3 bucket or a ShareX uploader. When an export re-hosts attachments, the files are uploaded there and that host's terms and privacy policy apply. Files on Catbox, ImgBB and most ShareX hosts are public: anyone with a link can open them.

Backscroll sends nothing anywhere else.

## Permissions

- **Network access**, to reach the services above.
- **Notifications** on Android, to show progress while an export runs in the background.
- **Storage** on Android 10 and older, to save exports to your Downloads folder.

## Other people's messages

An export contains messages written by other people. Treat it with the same care you'd want for your own messages, and don't share it in ways the people in it wouldn't agree to.
