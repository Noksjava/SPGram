# SPGram
SPgram is an unofficial Telegram client for the RG35XX series with PortMaster support.

Based on archeryfox’s TGmuOS-LOVE https://github.com/archeryfox/TGmuOS-LOVE

# SPgram

SPgram is an unofficial Telegram client for the Anbernic RG35XX SP running KNULLI. It uses the Telegram API and connects to your existing Telegram account. Its retro interface is designed for the handheld's 640×480 screen and built-in controls, including an on-screen keyboard for typing and signing in.

First alpha · v0.2.57 · Target device: RG35XX SP

- Browse direct messages, groups, channels, Saved Messages, and Archived Chats. Search conversations and return to your reading position.
- Open long posts in a scrollable reader. See text and attached media together, inspect photos and GIFs, and follow supported quotes back to their original messages.
- Read channel discussions where available, open comments and their attachments, reply, and react. Send messages, stickers, and GIFs in conversations that allow it.
- Play supported videos, audio tracks, and voice messages on demand. Zoom and pan photos and GIFs with the controller.
- Customize themes, fonts, motion, notification sound, and controller mappings. The keyboard supports English, French, Russian, Ukrainian, Polish, and Chinese Pinyin layouts.

## Install

You need an RG35XX SP wit PortMaster installed on your active storage and Wi-Fi for Telegram sign in and use. This alpha targets 35xxSP and Knulli Gladiator II 2025. Compatibility on other PortMaster devices and firmware is unverified.

1. Download **`SPgram-PortMaster-v0.2.57.zip`** and its matching **`.zip.sha256`** file from the release assets. Keep the installer zipped. [SPgram releases](https://github.com/Noksjava/SPGram/releases)
2. Verify the download on your computer using one of the commands below.
3. Copy the ZIP to **`/userdata/roms/ports/autoinstall/`**. On a storage card, open the **SHARE** partition and use `roms/ports/autoinstall/`. On Windows, you can also open **`\share`** in File Explorer while the handheld is on the same network. Use your device's hostname if you changed it. Create the `autoinstall` folder if needed. [PortMaster offline installs](https://portmaster.games/installation/installing-ports/#option-2-offline-installation)
4. Start **PortMaster** on the handheld. It picks up the ZIP and installs SPgram. Exit PortMaster, then launch **SPgram** from **Ports** category. If it is missing, open **START → Game Settings → Update Gamelists** and check Ports again. Example: [KNULLI PortMaster guide](https://knulli.org/systems/portmaster/)

When reporting a problem, include the SPgram version, handheld model, firmware version, what you pressed, and what happened. Share relevant log lines after removing private account information. [Report an issue](https://github.com/Noksjava/SPGram/issues)

## Security and account privacy

SPgram uses Telegram's TDLib library on your handheld for QR and phone sign-in. Telegram is the only recipient of the phone number, login code, and two-step verification password you enter. The API ID and hash bundled with the installer identify SPgram as a client. Each installation still needs its own authorized Telegram session.

Session data stays on the handheld. SPgram generates a random 32-byte key for each account and Telegram environment. TDLib uses it to encrypt the local database. The key lives alongside the database and downloaded media and some account metadata are stored separately from the encrypted database. Anyone who can copy both the database and its key can read the local data. Keep the SD card and any backups of the `conf/` folder private. [TDLib database encryption](https://core.telegram.org/tdlib/docs/classtd_1_1td__api_1_1set_tdlib_parameters.html)

You control the session. After Telegram confirms sign out, SPgram removes that account's local database, key, downloads, and saved reading positions. If you lose the handheld, you can revoke its session from **Settings → Devices** in Telegram on another device. [Telegram session management](https://telegram.org/faq#q-my-phone-was-stolen-what-do-i-do)

The app collects no analytics, usage statistics, or crash reports for the project. The app receives your chats through Telegram's TDLib and processes them on the handheld so it can display them. SPgram has no project-operated server, telemetry uploader, or remote access feature that would let the maintainer retrieve your messages, account details or session. The updater requests public release information and files from GitHub without sending Telegram account or chat data. Diagnostic logs stay on the handheld unless you choose to share them.

## Future plans

- [Long term] Improve PortMaster support one device at a time, with help from owners who can test on real hardware. Each port needs checks for installation, controls, screen layout, sign in, media playback, and memory use. If you'd like to test it on your linux handheld, open an issue with your handheld model, hardware details and firmware version. [Volunteer to test](https://github.com/Noksjava/SPGram/issues)
- [Short Term] Mod update. Add group and channel moderation actions for people with the relevant Telegram permissions, with clear confirmation before removing content or restricting members. Keep refining chat navigation, typing, search, and media playback. Improve startup and responsiveness on low memory devices, and use tester feedback to guide the next round of features.

## License

SPgram is distributed under the MIT License. Bundled components carry their own license notices.
