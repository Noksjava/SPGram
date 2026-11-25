# Changelog

## 0.2.67

- Update notices were simplified and the Updates screen was refreshed with clearer version and status colors.
- Installer-only updates now open installation instructions from the Updates menu.

## 0.2.58 - 0.2.66

- Read indicators were added to sent messages, and reader names and times were added where Telegram provides read receipts.
- Fullscreen GIFs were moved to streaming playback at source cadence.
- Channel handles and links to posts were added. Channel and user pictures can be viewed full-size, and messaging and blocking were added to user profiles.
- Photo, sticker, and GIF cards were stabilized during loading and cache eviction.
- Video seeking and quick reopen were hardened, and temporary media from interrupted playback is cleared at launch.
- Fullscreen playback was prioritized over background work, chat-list updates were batched, and GIFs were given smoother playback within a fixed texture budget.
- Settings rows were standardized and given matching icons, with account details and switching under My profile.
- GIF cards were kept at a fixed size during loading and playback, and download progress was moved inside the preview.
- The sign-in header was simplified.
- Posts containing a single photo or video now open directly when there is no accompanying text or quote.
- Sender names and selectable links were added to the message reader.
- Account management was moved under My profile, and Wi-Fi radio controls were combined into one toggle.
- PortMaster artwork packaging and the listing description were updated.
- Missing avatars are now retried after stale cache entries and interrupted downloads.
- Update checks were moved to the main Settings menu and made available on builds that use the full installer for updates.
- An unread-message divider was added to chat history.
- Sponsored Telegram links were routed to their destinations in the app.
- The installed version was added to Settings.
- PortMaster listing details were expanded, cover artwork was added, and the genre was set to Other.
- Background update checks on launch were added, with a switch in Settings and separate confirmation for installation.
- The release repository was pinned by the installer, and verified updates were made available without editing a configuration file.

## 0.2.57

- Signed manifests were made mandatory for app-only updates.
- A pinned AArch64 TDLib build recipe was added and native binary fingerprints were recorded.

## 0.2.56

- Local account data is now cleared after Telegram confirms sign-out.
- Restrictions on copying, forwarding, and disappearing media were enforced.
- Media conversion was limited to local inputs and supported formats.

## 0.2.55

- Performance controls and a Low memory preset were added to reduce texture memory use.

## 0.2.54

- Wi-Fi toggles and automatic reconnection after Wi-Fi returns were added on supported KNULLI builds.

## 0.2.53

- Comments were reordered oldest first, and history requests past the start of a thread were stopped.
- Comment reactions were added.

## 0.2.52

- Settings navigation was improved.

## 0.2.50

- A scrollable comment reader with media and direct replies was added.

## 0.2.49

- The startup intro was made optional and its volume was reduced.

## 0.2.48

- A video intro was added to cover app startup.

## 0.2.47

- A setting was added to keep Wi-Fi awake while SPgram is open.

## 0.2.46

- Automatic reconnection after network changes and resume was added, along with a manual reconnect action.

## 0.2.45

- Group and channel video posts are now opened in the reader before playback, with the selected clip preserved in video albums.

## 0.2.43

- The R2 shortcut was corrected to return to the last-read message while preserving newer unread messages.

## 0.2.42

- Avatar loading was made more reliable during media conversion, and queued portrait loads are now canceled when leaving a chat.
- Local performance diagnostics were added.

## 0.2.41

- Memory use was reduced by capping decoded media, loading only visible avatars, and reusing chat layouts.

## 0.2.40

- Avatar texture memory was capped, and blocking avatar conversion was removed.

## 0.2.39

- Stalled history requests were given timeouts and retries.
- WebP conversion was moved off the UI thread, and animation uploads were spread across frames.

## 0.2.38

- Quotes were made selectable in the reader so they can jump to the original message.
- Full-color Unicode emoji and Telegram artwork for custom emoji were added to messages and reactions.

## 0.2.37

- Settings contrast was improved, quit confirmation was added, and keyboard language selection was simplified.

## 0.2.36

- An R2 shortcut for returning from older chat history was added.

## 0.2.35

- Media playback in comments and navigation to quoted comments were added.
- Sender names in notifications and post headers were corrected.

## 0.2.34

- Profile name and bio editing were added, along with Telegram emoji pack support.

## 0.2.33

- Face-button calibration was added, and button hints were corrected.

## 0.2.32

- Reply previews, full quotes, and a keyboard draft preview were added.

## 0.2.31

- Comments were made accessible from the post reader, and comment threads were expanded to show quotes and live edits.

## 0.2.30

- The Settings transition was improved, and drafts and scroll position were preserved when opening it.

## 0.2.29

- Header navigation and font customization were expanded. Forwarded channel and group profiles were corrected.

## 0.2.28

- Controller hints were improved, and the composer was hidden in read-only chats.

## 0.2.27

- Grouped media posts, channel comments, and separate sticker and GIF pickers were added.
- Notification sound playback for unmuted chats was corrected.

## 0.2.26

- Sticker and GIF sending was fixed for TDLib 1.8.67.

## 0.2.25

- Reading positions were saved per account.
- Inline links and post text for audio and video were made visible.
- Audio playback with seeking and temporary file cleanup was added.

## 0.2.24

- Muted chat indicators were distinguished from active notifications, and a new-message sound was added.

## 0.2.23

- Search and message selection were consolidated in Options, and Controls scrolling was fixed.

## 0.2.22

- Chat membership and removal were corrected across folders.

## 0.2.21

- Video thumbnails were added, and overlap between playback times and controller hints was fixed.

## 0.2.20

- Controller remapping and a combined photo-and-text reader were added.

## 0.2.19

- Shoulder-button zoom, D-pad panning, and controller navigation in the composer were added.
- Six keyboard layouts were added, including offline Pinyin.

## 0.2.18

- The interface was restyled with retro visuals, animated feedback, and incoming-message notifications.

## 0.2.17

- Looping GIF and sticker previews and fullscreen GIF viewing were added.
- Saved Messages and Archived Chats were made compact, and pinned chats were marked.

## 0.2.16

- Video activation was fixed, and forwarded messages were given sender attribution.

## 0.2.15

- A fullscreen reader with scrolling and paging was added.

## 0.2.14

- Legacy firmware launchers and unused background notification and VPN controls were removed.

## 0.2.13

- Chats were corrected to open at the first unread message, and history paging was fixed.

## 0.2.12

- GIF and WebM sticker previews and static WebP conversion were restored.

## 0.2.11

- Video attachment playback and broader codec support, including software AV1 decoding, were added.

## 0.2.10

- Video preparation progress and playback fallback were added.
- TDLib event ordering was fixed, and message content was removed from debug logs.

## 0.2.9

- The image cache was capped at 256 MiB, and on-demand video conversion with temporary file cleanup was added.
- An AArch64 FFmpeg runtime was bundled.

## 0.2.8

- Saved Messages, Archived Chats, and unread-position navigation were added.
- The in-memory history window was bounded, and menu clipping and Settings scrolling were fixed.

## 0.2.7

- Physical face-button icons and a persistent Confirm and Back swap were added.

## 0.2.6

- A ready-to-install KNULLI package with phone and QR sign-in was added.

## 0.2.5

- Sponsored messages and search results were added, along with impression and click reporting.
- Read receipts were limited to visible messages.

## 0.2.4

- Encrypted session storage was isolated for the sign-in preview.

## 0.2.2

- The app and installer were renamed to SPgram, and the main interface was translated to English.

## 0.2.1

- Phone and QR sign-in and two-step verification were added.

## 0.2.0

- App-only updating and rollback were added with session preservation.

## 0.1.0

- PortMaster startup and native TDLib loading were fixed.
- Per-account database encryption and separate production and test storage were added.
- Private files were excluded from release packages.
