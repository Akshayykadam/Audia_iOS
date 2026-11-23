# Audia

A high-performance, AMOLED-optimized YouTube Music client for iOS built with SwiftUI and powered by `libmpv`.

Audia is designed for smooth, battery-efficient, and ad-free music and video streaming. It offers deep YouTube Music account synchronization, hardware-accelerated video playback, a built-in 10-band equalizer, offline downloads, and seamless Spotify playlist importing.

---

# Features

### Playback & Audio

- **Ad-Free Streaming** — Enjoy music and videos without interruptions.
- **Powered by MPVKit** — Reliable, low-latency playback with the libmpv engine.
- **Background Playback** — Full Lock Screen and Control Center controls with album artwork and playback progress.
- **10-Band Equalizer** — Fine-tune your sound with ±12 dB controls and 15 built-in presets.
- **Audio Normalization** — Consistent volume levels with EBU R128 loudness normalization.
- **Gapless Playback** — Seamless transitions between tracks.
- **In-App Volume Control** — Adjust playback volume directly from the player.
- **Artwork Gestures** — Swipe album artwork to skip tracks.

### Video Playback

- **Music Videos** — Switch between audio and high-quality video anytime.
- **Metal Rendering** — Hardware-accelerated video with automatic aspect ratio handling.
- **Audio-Only Mode** — Save battery and data by disabling video playback.

### Playlist Import

- **Spotify & YouTube Music Import** — Import public playlists by simply pasting a link.
- **No Setup Required** — Import Spotify playlists of up to 100 tracks without API keys.
- **Spotify API Support** — Optional API credentials for larger playlists.
- **Smart Track Matching** — Accurate matching using ISRC, title, artist, and local caching.

### Queue & Playback Management

- **Persistent Queue** — Your queue, shuffle, and repeat settings are saved automatically.
- **Autoplay** — Discover similar tracks when your queue ends.
- **Queue Management** — Easily reorder, add, and remove upcoming tracks.

### Offline Downloads

- **Offline Playback** — Download music and podcasts for offline listening.
- **Auto Downloads** — Automatically download liked songs and new podcast episodes.
- **Wi-Fi Only Downloads** — Keep mobile data usage under control.
- **Storage Management** — Monitor downloads and manage storage from Settings.

### Library & Sync

- **YouTube Music Sync** — Sync playlists, albums, artists, podcasts, and liked songs.
- **Smart Playlists** — Liked Songs, Listening History, Offline Downloads, and My Top 50.
- **Custom Playlists** — Create and manage your own playlists with optional cloud sync.
- **Podcast Support** — Browse podcasts and keep track of episode progress.

### Discover & Search

- **Personalized Home** — Quick Picks, mood-based recommendations, and curated lists.
- **Explore** — Discover new releases, charts, genres, and mood stations.
- **Live Search** — Instant suggestions with filters for songs, albums, artists, playlists, and podcasts.
- **Link Detection** — Automatically recognize Spotify and YouTube Music links for quick importing.

### Design & Customization

- **Minimal Dark Interface** — Pure black backgrounds and clean, distraction-free layouts.
- **Satoshi Typography** — Modern typography throughout the app.
- **Floating Navigation** — Smooth capsule-style tabs with a responsive mini-player.
- **14 Accent Themes** — Choose from a range of colors to personalize the interface.
- **Player Backgrounds** — Artwork-based glow or a clean, solid dark background.
- **Regional Controls** — Choose from 14 content regions and manage explicit content filtering.

### Playlist Import

- **Direct Playlist Import** — Import Spotify and YouTube Music playlists simply by pasting a link.
- **Smart Music Matching** — Automatically find matching tracks using our multi-layer music matching engine.
- **No Setup Required** — Import Spotify playlists of up to 100 tracks without API keys or account login.
- **Accurate Track Matching** — Uses ISRC, title, artist, and local caching for reliable results.

### Privacy

- **No Login Required** — Start listening without creating an account.
- **No Ads or Tracking** — No advertising, trackers, or third-party analytics.
- **Local History Controls** — Enable or disable search and playback history independently.
- **Privacy First** — Your listening experience stays focused on your music.

## Installation

Audia can be sideloaded on iOS devices using **AltStore**, **SideStore**, or **Feather**.

### Sideloading Source URL
Add the source URL to your sideloading manager:

```text
https://raw.githubusercontent.com/Akshayykadam/Audia_iOS/main/altstore.json
```

Or download the latest `.ipa` directly from the [Releases](https://github.com/Akshayykadam/Audia_iOS/releases) page.

---

## Building from Source

### Requirements
- macOS running **Xcode 16.0+**
- iOS 16.0+ deployment target
- Command Line Tools installed (`xcode-select --install`)

### Build with Xcode
```bash
git clone https://github.com/Akshayykadam/Audia_iOS.git
cd Audia_iOS
xcodebuild -scheme Audia -destination 'generic/platform=iOS Simulator' build
```

### Build IPA Package
To compile and package an unsigned IPA locally:
```bash
./build_ipa.sh
```
The resulting IPA will be placed in `build/Audia.ipa`.

---

## Credits & Acknowledgments

Audia is made possible by the open-source community and builds upon the work of several fantastic projects and developers:

- **[Trop](https://github.com/SwiftyMedia/Trop)** — Audia was originally forked from Trop by [SwiftyMedia](https://github.com/SwiftyMedia). Huge credit and thanks to the original authors for building the foundational SwiftUI architecture and client concepts.
- **[SwiftyTube](https://github.com/SwiftyMedia/SwiftyTube)** — Swift client library for interacting with YouTube's InnerTube API, created by SwiftyMedia.
- **[MPVKit](https://github.com/mpvkit/MPVKit)** & **[mpv](https://mpv.io/)** — The high-performance, cross-platform media player powering Audia's audio engine, equalizers, loudness normalization, and Metal-accelerated video pipeline.
- **[GRDB.swift](https://github.com/groue/GRDB.swift)** — Robust SQLite toolkit by Gwendal Roué, powering offline downloads, library caching, and listening history.
- **[Nuke](https://github.com/kean/Nuke)** — Fast image loading, disk caching, and preheating framework by Alexander Grebenyuk.
- **[Marquee](https://github.com/SwiftUIKit/Marquee)** — Smooth marquee scrolling animation for SwiftUI.
- **[Satoshi Font](https://www.fontshare.com/fonts/satoshi)** — Clean geometric typeface designed by the Indian Type Foundry and distributed via Fontshare.

---

## Licenses

### Project License
Audia is free and open-source software released under the **[GNU General Public License v3.0](LICENSE)** (GPL-3.0). See the [LICENSE](LICENSE) file for the full license text.

---

## Disclaimer

Audia is an independent open-source client and is not affiliated with, endorsed by, or associated with Google LLC or YouTube.
