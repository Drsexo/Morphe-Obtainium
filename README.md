<div align="center">

[![Title](https://readme-typing-svg.demolab.com?font=Press+Start+2P&duration=1500&pause=100&color=853BFF&center=true&multiline=true&width=530&height=120&lines=Morphe+Apps+Builder;Updated+Daily;Lightweight+APKs)](https://git.io/typing-svg)  
[![Telegram](https://img.shields.io/badge/Telegram-853BFF?style=for-the-badge&logo=telegram&logoColor=white)](https://t.me/Morphe_Obtainium_releases)  

![YouTube](https://img.shields.io/endpoint?style=flat-square&logo=youtube&logoColor=%23FF0000&color=%237028E7&url=https%3A%2F%2Fraw.githubusercontent.com%2FDrsexo%2FMorphe-Obtainium%2Fupdate%2Fyoutube-morphe-badge.json)
![YouTube Music](https://img.shields.io/endpoint?style=flat-square&logo=youtubemusic&logoColor=%23FF0000&color=%237028E7&url=https%3A%2F%2Fraw.githubusercontent.com%2FDrsexo%2FMorphe-Obtainium%2Fupdate%2Fyoutube-music-morphe-badge.json)
![Reddit](https://img.shields.io/endpoint?style=flat-square&logo=reddit&logoColor=%23FF4500&color=%237028E7&url=https%3A%2F%2Fraw.githubusercontent.com%2FDrsexo%2FMorphe-Obtainium%2Fupdate%2Freddit-morphe-badge.json)
![X](https://img.shields.io/endpoint?style=flat-square&logo=x&logoColor=%23000000&color=%237028E7&url=https%3A%2F%2Fraw.githubusercontent.com%2FDrsexo%2FMorphe-Obtainium%2Fupdate%2Fx-piko-badge.json)
![Instagram](https://img.shields.io/endpoint?style=flat-square&logo=instagram&logoColor=%23E4405F&color=%237028E7&url=https%3A%2F%2Fraw.githubusercontent.com%2FDrsexo%2FMorphe-Obtainium%2Fupdate%2Finstagram-piko-badge.json)

</div>

Automated builder for Morphe and Piko patched apps with Obtainium support.  
Fork of [j-hc/revanced-magisk-module](https://github.com/j-hc/revanced-magisk-module), focused on Morphe/Piko patches and arm64-only builds.

## What's different

- **Morphe + Piko patches** instead of ReVanced
- **Per-app releases**: each app gets its own GitHub release tag, easy to roll back
- **Auto-fallback**: if the latest app version fails to patch, tries older versions automatically
- **Smaller APKs**: arm64 only, strips other libs
- **KSU/APatch support**: proper `nsenter` mount on boot, not just Magisk
- **Better mounting**: `nosuid,nodev` bind mounts, susfs auto-hide, idempotent re-mount on boot, cleaner path under `/data/adb/Morphe-Module`
- **curl-impersonate**: bypasses anti-bot checks on APKMirror/Uptodown

## Apps Built

| App | Patches | Build Mode | Obtainium |
|:--------:|:---|:---|:-:|
| <img src="docs/youtube.png" width="30" height="30"> **YouTube** | Morphe | APK + Module | [![Add][badge]][obt] |
| <img src="docs/music.png" width="30" height="30"> **YouTube Music** | Morphe | APK + Module | [![Add][badge]][obt] |
| <img src="docs/reddit.png" width="30" height="30"> **Reddit** | Morphe | APK | [![Add][badge]][obt] |
| <img src="docs/x.png" width="30" height="30"> **X (Twitter)** | Piko | APK | [![Add][badge]][obt] |
| <img src="docs/instagram.png" width="30" height="30"> **Instagram** | Piko | APK | [![Add][badge]][obt] |

[badge]: https://img.shields.io/badge/Add-Add?style=flat-square&logo=Obtainium&logoColor=%23ffffff&logoSize=auto&color=%237028E7
[obt]: https://drsexo.github.io/Morphe-Obtainium/Obtainium.html

## Build Schedule

Builds run **daily at midnight UTC**, triggered only when new stable patches are released.  
Tries the latest app version first; if patching fails, falls back to older versions.

## Manual Installation

### Root (Magisk/KernelSU/APatch Module)
1. Download and install the Magisk module (`.zip`) from [Releases](../../releases)
2. Reboot
3. (Recommended) Use [zygisk-detach](https://github.com/j-hc/zygisk-detach) to detach the app from Play Store updates

### Non-root (APK)
1. Download and install the APK from [Releases](../../releases)
2. Install [MicroG-RE](https://github.com/MorpheApp/MicroG-RE/releases) for Google login functionality
