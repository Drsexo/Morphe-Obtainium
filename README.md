<div align="center">

# Morphe Builder
   
[![Build](https://github.com/Drsexo/Morphe-Obtainium/actions/workflows/build.yml/badge.svg)](https://github.com/Drsexo/Morphe-Obtainium/actions/workflows/build.yml)

</div>

Automated builder for Morphe apps with Obtainium support.  Enhanced for **personal** use.
Based on [j-hc/revanced-magisk-module](https://github.com/j-hc/revanced-magisk-module)

## 📦 Apps Built

| App           | Patches  | Build Mode |
| ------------- | -------- | ------------------- |
| YouTube       | Morphe   | APK + Magisk Module |
| YouTube Music | Morphe   | APK + Magisk Module |
| Reddit        | Morphe   | APK                 |

## 📅 Build Schedule

Builds are scheduled automatically to run **every day at midnight UTC**, triggered only when new stable patches are released.

## 📱 Installation guide

### Root (Magisk/KernelSU/APatch Module)
1. Download the Magisk module (`.zip`) from [Releases](../../releases)
2. Install via Magisk/KernelSU/APatch
3. Reboot
4. (Recommended) Use [zygisk-detach](https://github.com/j-hc/zygisk-detach) to detach the app from Play Store updates

### Non-root (APK)
1. Download the APK from [Releases](../../releases)
2. Install [MicroG-RE](https://github.com/MorpheApp/MicroG-RE/releases) for Google login functionality
3. Install the patched APK

### 📥 Obtainium (Recommended)
[Obtainium](https://github.com/ImranR98/Obtainium) allows you to install and update apps directly from this repository within the app.

### Quick Add (One-click)
Click the button below on your Android device to add apps:

[![Add to Obtainium](https://img.shields.io/badge/Obtainium-Add%20Apps-2ecc71?style=for-the-badge&logo=android)](https://drsexo.github.io/Morphe-Obtainium/Obtainium.html)

## 🙏 Credits

- [j-hc](https://github.com/j-hc) - Original [revanced-magisk-module](https://github.com/j-hc/revanced-magisk-module) builder architecture
- [MorpheApp](https://github.com/MorpheApp) - Morphe patches, CLI, and MicroG-RE
- [ReVanced](https://github.com/ReVanced) - Original ReVanced patches and tools
- [WSTxda](https://github.com/WSTxda) - Original MicroG-RE concept
- [ImranR98](https://github.com/ImranR98) - Obtainium app