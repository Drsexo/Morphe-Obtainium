<div align="center">

<a href="https://git.io/typing-svg"><img src="https://readme-typing-svg.demolab.com?font=&weight=900&size=25&duration=3000&pause=50&color=7E9B8A&center=true&width=435&height=40&lines=Morphe+Builder;Updated+daily" alt="Typing SVG" /></a>  
![Build](https://img.shields.io/github/actions/workflow/status/Drsexo/Morphe-Obtainium/build.yml?style=for-the-badge&logo=jenkins&logoColor=%23ffffff&logoSize=auto&color=%237E9B8A)

</div>

Automated builder for Morphe apps with Obtainium support.  Enhanced for **personal** use.  
Based on [j-hc's revanced builder](https://github.com/j-hc/revanced-magisk-module)

## 📦 Apps Built

| App | Patches | Build Mode | Obtainium |
|:--------:|:---|:---|:---:|
| <img src="docs/youtube.png" width="20" height="20"> **YouTube** | Morphe | APK + Module | [![Add][badge]][obt] |
| <img src="docs/music.png" width="20" height="20"> **YouTube Music** | Morphe | APK + Module | [![Add][badge]][obt] |
| <img src="docs/reddit.png" width="20" height="20"> **Reddit** | Morphe | APK | [![Add][badge]][obt] |
| <img src="docs/x.png" width="20" height="20"> **X (Twitter)** | Piko | APK | [![Add][badge]][obt] |

[badge]: https://img.shields.io/badge/Add-Add?style=flat-square&logo=Obtainium&logoColor=%23ffffff&logoSize=auto&color=%237028E7
[obt]: https://drsexo.github.io/Morphe-Obtainium/Obtainium.html

## 📅 Build Schedule
Builds are scheduled automatically to run **every day at midnight UTC**, triggered only when new stable patches are released.

## 📱 Manual Installation
### Root (Magisk/KernelSU/APatch Module)
1. Download and install the Magisk module (`.zip`) from [Releases](../../releases)
2. Reboot
3. (Recommended) Use [zygisk-detach](https://github.com/j-hc/zygisk-detach) to detach the app from Play Store updates

### Non-root (APK)
1. Download and install the APK from [Releases](../../releases)
2. Install [MicroG-RE](https://github.com/MorpheApp/MicroG-RE/releases) for Google login functionality

## 🙏 Credits
- [j-hc](https://github.com/j-hc) - Original [revanced-magisk-module](https://github.com/j-hc/revanced-magisk-module) builder architecture
- [MorpheApp](https://github.com/MorpheApp) - Morphe patches, CLI, and MicroG-RE
- [ReVanced](https://github.com/ReVanced) - Original ReVanced patches and tools
- [WSTxda](https://github.com/WSTxda) - Original MicroG-RE concept
- [ImranR98](https://github.com/ImranR98) - Obtainium app