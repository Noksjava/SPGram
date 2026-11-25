# SPgram

SPgram is an unofficial Telegram client for the G35XX series with PortMaster. It uses the Telegram API and connects to your existing Telegram account. Its retro interface is designed for the handheld's 640×480 screen and built-in controls, including an on-screen keyboard for typing and signing in.

**Alpha · v0.2.67 · RG35XX SP with KNULLI Gladiator II**

- Browse direct messages, groups, channels, Saved Messages, and Archived Chats. Search conversations and return to your reading position.
- Open long posts in a scrollable reader. See text and attached media together, inspect photos and GIFs, and follow supported quotes back to their original messages.
- Read channel discussions where available, open comments and their attachments, reply, and react. Send messages, stickers, and GIFs in conversations that allow it.
- Play supported videos, audio tracks, and voice messages on demand. Zoom and pan photos and GIFs with the controller.
- Customize themes, fonts, motion, notification sound, and controller mappings. The keyboard supports English, French, Russian, Ukrainian, Polish, and Chinese Pinyin layouts.

## Install

You need an RG35XX device with PortMaster installed on your active storage, and Wi-Fi for Telegram sign-in and use. This alpha targets that device and firmware combination. Compatibility was tested on an RG35XXSP running Knulli Gladiator II, for now other PortMaster devices and firmware is unverified.

1. Download **`SPgram-PortMaster-v0.2.67.zip`** and its matching **`.zip.sha256`** file from the release assets. Keep the installer zipped. [SPgram releases](https://github.com/Noksjava/SPGram/releases)
2. Verify the download on your computer using one of the commands below.
3. Copy the ZIP to **`/userdata/roms/ports/autoinstall/`**. On a readable KNULLI storage card, open the **SHARE** partition and use `roms/ports/autoinstall/`. On Windows, you can also open **`\\KNULLI\share`** in File Explorer while the handheld is on the same network. Use your device's hostname if you changed it. Create the `autoinstall` folder if needed. [PortMaster offline installs](https://portmaster.games/installation/installing-ports/#option-2-offline-installation)
4. Start **PortMaster** on the handheld. It picks up the ZIP and installs SPgram. Exit PortMaster, then launch **SPgram** from EmulationStation's **Ports** category. If it is missing, open **START → Game Settings → Update Gamelists** and check Ports again. 

Verify the ZIP, if necessary.

## Default controls

The button prompts use physical positions so they remain useful across different label layouts.

| Control | Action |
| --- | --- |
| D-pad | Move focus, scroll a post, or pan zoomed media |
| Bottom face button | Confirm or open the selected item |
| Right face button | Go back |
| Top face button | Open Options, including search and message actions where available |
| START | Open Settings from the chat list or open the keyboard in a writable conversation |
| SELECT | Open the Controls guide |
| L1 / R1 | Zoom out / in for photos and GIFs, or scroll a page in the post reader |
| R2 | Return to the read boundary in a conversation when the jump arrow is available |

If Confirm and Back feel swapped, open **Settings → Controls → Calibrate face buttons** and follow the prompts. The sign-in screen also opens button setup with **START**. To change individual actions, use **Settings → Controls → Map keys**. Find keyboard layouts under **Settings → Language settings → Keyboard languages**. When several are enabled, use the globe key to pick one while typing.

## Media and performance

Videos download when you choose to play them. The full installer includes a video converter that prepares supported clips for the handheld, so a large file may take time before playback starts. Closing a video or audio player clears its temporary playback files. The photo cache is limited to 256 MiB, with a target local storage retention of one day.

If busy chats feel slow, try **Settings → Visual settings → Performance → Low memory**. That preset uses initials in place of avatars, still previews in place of inline animations, on-demand images, and a smaller decoded texture cache. You can set those options individually.

## Updates and account data

Update with the next full PortMaster ZIP using the same installation steps. In v0.2.61 and later, open **Settings → Updates** to see the installed and latest published versions, check manually, or turn off **Check at launch**. In-app installation requires a build with the trusted release key and a signed update. Keep `/userdata/roms/ports/telegramsp/conf/` to retain your session and settings.

## Security and account privacy

SPgram collects no analytics, usage statistics or crash reports for the project. The app receives your chats through TDLib and processes them on the handheld so it can display them. SPgram has no project-operated server, telemetry uploader, or remote access feature that would let the developer retrieve your messages, account details, or session. The updater requests public release information and files from GitHub without sending Telegram account or chat data. Diagnostic logs stay on the handheld unless you choose to share them.

Sign-in goes directly to Telegram. SPgram uses Telegram's TDLib library on your handheld for QR and phone sign-in. Telegram is the only recipient of the phone number, login code, and two-step verification password you enter. The API ID and hash bundled with the installer identify SPgram as a client. Each installation still needs its own authorized Telegram session.

Note: Session data stays on the handheld. SPgram generates a random 32-byte key for each account and Telegram environment. TDLib uses it to encrypt the local database. The key lives alongside the database and downloaded media and some account metadata are stored separately from the encrypted database. Anyone who can copy both the database and its key can read the local data. Keep the SD card and any backups of the `conf/` folder private. [TDLib database encryption](https://core.telegram.org/tdlib/docs/classtd_1_1td__api_1_1set_tdlib_parameters.html)

After Telegram confirms sign out, SPgram removes that account's local database, key, downloads and saved reading positions. If you lose the handheld or the sdcard, you can revoke its session from **Settings → Devices** in Telegram on another device. [Telegram session management](https://telegram.org/faq#q-my-phone-was-stolen-what-do-i-do)

## Troubleshooting

| Problem | What to check |
| --- | --- |
| SPgram is missing from Ports | Check that the untouched installer ZIP went into the active storage's `roms/ports/autoinstall/` folder. Launch PortMaster again and refresh the gamelist. |
| SPgram returns immediately to Ports | Check `telegramsp/conf/launcher.log` in your ports folder. If it reports a missing runtime, open **Options → Runtime Manager** in PortMaster. [PortMaster runtime help](https://portmaster.games/installation/installing-ports/#troubleshooting) |
| The app asks for API credentials | Confirm you installed the full PortMaster ZIP from the project's release assets. |
| Telegram stops loading after a Wi-Fi drop | Check KNULLI's network status, then use **Settings → Advanced → Reconnect to Telegram**. |
| Sign-in asks for email verification | This alpha supports QR and phone sign-in, including passwords. Email verification in the client is still unsupported. |

When reporting a problem, include the SPgram version, handheld model, KNULLI version, what you pressed, and what happened. Share relevant log lines after removing private account information. [Report an issue](https://github.com/Noksjava/SPGram/issues)

## Future plans

- Add more PortMaster supported devices - hopefully with help from owners who can test on real hardware - and eventually turn it into client that would work on every PM-supported device. If you'd like to test, open an issue with your handheld model, hardware details and firmware version [here.](https://github.com/Noksjava/SPGram/issues)
- Moderation tool update: add group and channel moderation actions for people with the relevant Telegram permissions, with clear confirmation before removing content or restricting members.
- Everyday improvements: Keep refining chat navigation, typing, search, and media playback. Add more features from bigger official TG clients, improve startup and responsiveness on low memory devices, use tester feedback to guide the next round of features.

## License and credits

SPgram is distributed under the MIT License. Bundled components carry their own license notices.
