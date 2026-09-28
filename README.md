<div align="center">

[![Title](https://readme-typing-svg.demolab.com?font=Press+Start+2P&duration=1500&pause=100&color=853BFF&center=true&multiline=true&width=530&height=120&lines=Morphe+Apps+Builder;Updated+Daily;Lightweight+APKs)](https://git.io/typing-svg)  
[![Telegram](https://img.shields.io/badge/Telegram-853BFF?style=for-the-badge&logo=telegram&logoColor=white)](https://t.me/Morphe_Obtainium_releases)  

![YouTube](https://img.shields.io/endpoint?style=flat-square&logo=youtube&logoColor=%23FF0000&color=%237028E7&url=https%3A%2F%2Fraw.githubusercontent.com%2FDrsexo%2FMorphe-Obtainium%2Fupdate%2Fyoutube-morphe-badge.json)
![YouTube Music](https://img.shields.io/endpoint?style=flat-square&logo=youtubemusic&logoColor=%23FF0000&color=%237028E7&url=https%3A%2F%2Fraw.githubusercontent.com%2FDrsexo%2FMorphe-Obtainium%2Fupdate%2Fyoutube-music-morphe-badge.json)
![Reddit](https://img.shields.io/endpoint?style=flat-square&logo=reddit&logoColor=%23FF4500&color=%237028E7&url=https%3A%2F%2Fraw.githubusercontent.com%2FDrsexo%2FMorphe-Obtainium%2Fupdate%2Freddit-morphe-badge.json)
![X](https://img.shields.io/endpoint?style=flat-square&logo=x&logoColor=%23000000&color=%237028E7&url=https%3A%2F%2Fraw.githubusercontent.com%2FDrsexo%2FMorphe-Obtainium%2Fupdate%2Fx-piko-badge.json)
![Instagram](https://img.shields.io/endpoint?style=flat-square&logo=instagram&logoColor=%23E4405F&color=%237028E7&url=https%3A%2F%2Fraw.githubusercontent.com%2FDrsexo%2FMorphe-Obtainium%2Fupdate%2Finstagram-piko-badge.json)
![Messenger](https://img.shields.io/endpoint?style=flat-square&logo=messenger&logoColor=%2300B2FF&color=%237028E7&url=https%3A%2F%2Fraw.githubusercontent.com%2FDrsexo%2FMorphe-Obtainium%2Fupdate%2Fmessenger-hush-badge.json)
![Facebook](https://img.shields.io/endpoint?style=flat-square&logo=facebook&logoColor=%230187F2&color=%237028E7&url=https%3A%2F%2Fraw.githubusercontent.com%2FDrsexo%2FMorphe-Obtainium%2Fupdate%2Ffacebook-hush-badge.json)
![Google Photos](https://img.shields.io/endpoint?style=flat-square&logo=googlephotos&logoColor=%23F4B400&color=%237028E7&url=https%3A%2F%2Fraw.githubusercontent.com%2FDrsexo%2FMorphe-Obtainium%2Fupdate%2Fgoogle-photos-morphe-badge.json)

</div>

Automated builder for Morphe, Piko and Hush patched apps with Obtainium support.  
Fork of [j-hc/revanced-magisk-module](https://github.com/j-hc/revanced-magisk-module), focused on Morphe/Piko/Hush patches and arm64-only builds.

## What's different

- **Morphe, Piko and Hush patches** instead of ReVanced
- **Per-app releases**: each app gets its own release tag, easy to roll back
- **Auto-fallback**: if the latest app version fails to patch, tries older versions automatically
- **Smaller APKs**: arm64 only, strips other libs
- **Root support**: Magisk/KernelSU/APatch. Proper `nsenter` mounts with `nosuid,nodev`, susfs auto-hide, and optional **NoMount** VFS injection (KSU/APatch, chosen at install)
- **curl-impersonate**: bypasses anti-bot checks on APKMirror/Uptodown

## Apps Built

| App | Patches | Build Mode | Obtainium |
|:--------:|:---|:---|:-:|
| <img src="docs/youtube.png" width="30" height="30"> **YouTube** | Morphe | APK + Module | [![Add][badge]][obt] |
| <img src="docs/music.png" width="30" height="30"> **YouTube Music** | Morphe | APK + Module | [![Add][badge]][obt] |
| <img src="docs/reddit.png" width="30" height="30"> **Reddit** | Morphe | APK | [![Add][badge]][obt] |
| <img src="docs/x.png" width="30" height="30"> **X (Twitter)** | Piko | APK | [![Add][badge]][obt] |
| <img src="docs/instagram.png" width="30" height="30"> **Instagram** | Piko | APK | [![Add][badge]][obt] |
| <img src="docs/messenger.png" width="30" height="30"> **Messenger** | Hush | APK | [![Add][badge]][obt] |
| <img src="docs/facebook.png" width="30" height="30"> **Facebook** | Hush | APK | [![Add][badge]][obt] |
| <img src="docs/google-photos.png" width="30" height="30"> **Google Photos** | Morphe | APK + Module | [![Add][badge]][obt] |

[badge]: https://img.shields.io/badge/Add-Add?style=flat-square&logo=Obtainium&logoColor=%23ffffff&logoSize=auto&color=%237028E7
[obt]: https://drsexo.github.io/Morphe-Obtainium/Obtainium.html

## Build Schedule

Builds run **daily at midnight UTC**, triggered only when new stable patches are released.

## Manual Installation

### Root (Magisk/KernelSU/APatch Module)
1. Download and install the Magisk module (`.zip`) from [Releases](../../releases)
2. Reboot
3. (Recommended) Use [zygisk-detach](https://github.com/j-hc/zygisk-detach) to detach Google apps from Play Store updates

### Non-root (APK)
1. Download and install the APK from [Releases](../../releases)
2. For Google apps (YouTube, Music, Google Photos), install [MicroG-RE](https://github.com/MorpheApp/MicroG-RE/releases) for login
