# Audia

### Your music. Your way. No interruptions.

**Audia** is a high-performance, open-source Music client for iOS, built with SwiftUI and powered by MPVKit.

Designed for people who love music and care about the listening experience. Audia brings together a beautiful interface, powerful playback controls, seamless library synchronization, and a feature-packed audio engine — all in one place.

No unnecessary clutter. No annoying ads. Just you and your music.


---

## Take a Look Around

A little preview of what your music experience looks like.

<p align="center">
  <img src="App%20UI%20Screenshots/Screenshot%20iPhone%2017%20Pro%2011-24-2026%20at%201.39.30%E2%80%AFPM.png" width="24%" />
  <img src="App%20UI%20Screenshots/Screenshot%20iPhone%2017%20Pro%2011-24-2026%20at%201.39.51%E2%80%AFPM.png" width="24%" />
  <img src="App%20UI%20Screenshots/Screenshot%20iPhone%2017%20Pro%2011-24-2026%20at%201.39.58%E2%80%AFPM.png" width="24%" />
  <img src="App%20UI%20Screenshots/Screenshot%20iPhone%2017%20Pro%2011-24-2026%20at%201.40.04%E2%80%AFPM.png" width="24%" />
</p>
<p align="center">
  <img src="App%20UI%20Screenshots/Screenshot%20iPhone%2017%20Pro%2011-24-2026%20at%201.40.21%E2%80%AFPM.png" width="24%" />
  <img src="App%20UI%20Screenshots/Screenshot%20iPhone%2017%20Pro%2011-24-2026%20at%201.40.31%E2%80%AFPM.png" width="24%" />
  <img src="App%20UI%20Screenshots/Screenshot%20iPhone%2017%20Pro%2011-24-2026%20at%201.40.40%E2%80%AFPM.png" width="24%" />
  <img src="App%20UI%20Screenshots/Screenshot%20iPhone%2017%20Pro%2011-24-2026%20at%201.41.06%E2%80%AFPM.png" width="24%" />
</p>

---

## ✨ What Makes Audia Different?

Not just another music player. Audia packs a lot under the hood.

### Playback That Just Feels Right

Your music deserves more than basic playback controls.

- **Ad-Free Streaming** — Enjoy music and videos without commercial interruptions.
- **MPVKit Audio Engine** — Powered by libmpv for reliable, low-latency playback.
- **Background Playback** — Keep the music going with full Lock Screen and Control Center integration.
- **10-Band Equalizer** — Shape your sound with ±12 dB controls and 15 built-in presets.
- **Audio Normalization** — Consistent volume using EBU R128 loudness normalization.
- **Gapless Playback** — Move between tracks without missing a beat.
- **In-App Volume Control** — Adjust volume right from the player.
- **Artwork Gestures** — Swipe album artwork to skip tracks.

### Music Is Better When You Can See It

Sometimes you want to listen. Sometimes you want to watch.

- **Music Videos** — Switch between audio and high-quality video whenever you like.
- **Metal Rendering** — Hardware-accelerated video rendering with automatic aspect ratio handling.
- **Audio-Only Mode** — Skip video playback to save battery and mobile data.

### Bring Your Playlists Along

Switching music platforms shouldn't mean starting your library from scratch.

- **Spotify Import** — Bring your public Spotify playlists into Audia.
- **YouTube Music Import** — Import playlists directly using their links.
- **No API Keys Needed** — Import Spotify playlists containing up to 100 tracks without additional setup.
- **Optional Spotify API** — Configure your own API credentials for larger playlists.
- **Smart Track Matching** — Match songs using ISRC, title, and artist information, backed by local caching.

Just paste a playlist link. Let Audia do the matching.

### Your Queue, Your Rules

Keep your listening experience exactly how you like it.

- **Persistent Queue** — Your queue, shuffle, and repeat preferences are saved automatically.
- **Autoplay** — Discover similar tracks when your queue runs out.
- **Queue Management** — Reorder, add, or remove upcoming tracks with ease.

### Your Music Goes Offline

Internet connection? Optional.

- **Offline Playback** — Download music and podcasts for listening anywhere.
- **Automatic Downloads** — Automatically download liked songs and new podcast episodes.
- **Wi-Fi Only Downloads** — Avoid unwanted mobile data usage.
- **Storage Management** — Monitor and manage downloaded content from Settings.

### Your Library, Always in Sync

Your music collection deserves a proper home.

- **YouTube Music Sync** — Sync playlists, albums, artists, podcasts, and liked songs.
- **Smart Playlists** — Liked Songs, Listening History, Offline Downloads, and My Top 50.
- **Custom Playlists** — Create and manage your own playlists with optional cloud sync.
- **Podcast Support** — Browse podcasts and keep track of episode progress.

### Find Your Next Favorite Track

There's always something new to discover.

- **Personalized Home** — Quick Picks, mood-based recommendations, and curated collections.
- **Explore** — Discover new releases, charts, genres, and mood stations.
- **Live Search** — Instant suggestions with filters for songs, albums, artists, playlists, and podcasts.
- **Smart Link Detection** — Automatically recognize Spotify and YouTube Music links for quick importing.

### A Player That Feels Like Home

Because the little details matter.

- **Minimal Dark Interface** — Pure black backgrounds and distraction-free layouts.
- **Satoshi Typography** — Modern, clean typography throughout the app.
- **Floating Navigation** — Smooth capsule-style tabs with a responsive mini-player.
- **14 Accent Themes** — Give Audia your own visual identity.
- **Player Backgrounds** — Choose artwork-based glow effects or a clean, solid dark background.
- **Regional Controls** — Choose from 14 content regions and manage explicit content filtering.

### Your Privacy Matters

Your music is personal. Your listening experience should be too.

- **No Login Required** — Get started without creating an account.
- **No Ads or Tracking** — No advertising, trackers, or third-party analytics.
- **Local History Controls** — Independently enable or disable search and playback history.
- **Privacy First** — Enjoy your music without unnecessary data collection.

---

## 🚀 Getting Started

Ready to give Audia a spin?

Audia can be installed on compatible iOS devices using your preferred sideloading method.

### Installation Options

| Method | Description |
|---|---|
| **AltStore** | Install and refresh apps using AltServer |
| **SideStore** | Sideload apps directly from your device |
| **Feather** | Manage and install signed IPA packages |

### 📦 Add Audia as a Source

Copy the source URL below and add it to your sideloading manager.

```text
https://raw.githubusercontent.com/Akshayykadam/Audia_iOS/main/altstore.json
```

Prefer downloading manually?

Head over to [**GitHub Releases**](https://github.com/Akshayykadam/Audia_iOS/releases) and grab the latest `.ipa` file.

---

## 🛠️ Build It Yourself

Want to explore the code, customize Audia, or build your own version? You're welcome to.

### Requirements

- macOS with **Xcode 16.0 or later**
- iOS 16.0+ deployment target
- Xcode Command Line Tools

Install the command line tools if you haven't already:

```bash
xcode-select --install
```

### Clone the Repository

```bash
git clone https://github.com/Akshayykadam/Audia_iOS.git

cd Audia_iOS
```

### Build with Xcode

```bash
xcodebuild -scheme Audia \
  -destination 'generic/platform=iOS Simulator' build
```

### Build an IPA

Want to package your own build?

```bash
./build_ipa.sh
```

Your resulting unsigned IPA will be available at:

```text
build/Audia.ipa
```

---

## Built on Open Source

Audia wouldn't be possible without the incredible work of the open-source community.

A huge thank you to the developers and maintainers behind these projects:

| Project | What It Does |
|---|---|
| [Trop](https://github.com/SwiftyMedia/Trop) | Original project and foundational SwiftUI architecture |
| [SwiftyTube](https://github.com/SwiftyMedia/SwiftyTube) | Swift client for YouTube's InnerTube API |
| [MPVKit](https://github.com/mpvkit/MPVKit) | Media playback engine integration |
| [mpv](https://mpv.io/) | Powerful cross-platform media player |
| [GRDB.swift](https://github.com/groue/GRDB.swift) | SQLite database toolkit |
| [Nuke](https://github.com/kean/Nuke) | Image loading and caching |
| [Marquee](https://github.com/SwiftUIKit/Marquee) | Smooth scrolling text for SwiftUI |
| [Satoshi](https://www.fontshare.com/fonts/satoshi) | Typeface by Indian Type Foundry |

**Special thanks to [SwiftyMedia](https://github.com/SwiftyMedia)** for creating Trop, the project Audia was originally forked from. Audia builds upon that foundation and extends it with its own features, design, and playback experience.

Please check the respective projects for their individual licenses and attribution requirements.

---

## 📄 License

Audia is free and open-source software licensed under the **[GNU General Public License v3.0](LICENSE)**.

You are welcome to study, modify, and redistribute the source code in accordance with the terms of GPL-3.0.

See the [LICENSE](LICENSE) file for the complete license.

---

## ⚠️ Disclaimer & Third-Party Services

Audia is an **independent, community-developed open-source project**. It is not affiliated with, endorsed by, sponsored by, or officially associated with Google LLC, YouTube, YouTube Music, Spotify AB, or any of their subsidiaries or affiliates.

All third-party names, logos, trademarks, and service marks belong to their respective owners and are used solely for identification and compatibility purposes.

Audia is an unofficial client that interacts with third-party services and publicly accessible content. It is not an official YouTube Music or Spotify application, nor is it intended to impersonate or replace their official products.

**Please keep the following in mind:**

- **Third-party services:** Audia depends on services and interfaces that are not controlled by this project. Their availability, functionality, and compatibility may change without notice.
- **Content ownership:** Audia does not own, host, or claim ownership of music, videos, or other third-party content accessed through the application. All rights remain with their respective copyright holders.
- **User responsibility:** Users are responsible for ensuring that their use of Audia complies with applicable laws, copyright requirements, and the terms and policies of the services they access.
- **No guarantees:** This software is provided "AS IS", without warranties or guarantees of any kind, to the maximum extent permitted by applicable law.

The developers and contributors are not responsible for misuse of the application, copyright infringement, third-party service restrictions, or any resulting claims or damages, to the extent permitted by law.

---

<p align="center">
  <strong>Made for the love of music.</strong>
  <br />
  <sub>Built with SwiftUI. Powered by open source. Enjoyed by you.</sub>
  <br /><br />
  ⭐ If you like Audia, consider starring the repository!
</p>
