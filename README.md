# Nothing Gallery (Enhanced Edition)

[![Release](https://img.shields.io/github/v/release/arjid200/Nothing-Gallery?color=red&label=Latest%20Release)](https://github.com/arjid200/Nothing-Gallery/releases/latest)
[![Build Release APK](https://github.com/arjid200/Nothing-Gallery/actions/workflows/build-apk.yml/badge.svg)](https://github.com/arjid200/Nothing-Gallery/actions/workflows/build-apk.yml)
[![License](https://img.shields.io/github/license/arjid200/Nothing-Gallery?color=%23247EE0)](LICENSE)

<img src="https://raw.githubusercontent.com/jerichoi224/Nothing-Gallery/main/images/feature_art.png">

An enhanced, high-performance fork of [Nothing-Gallery by jerichoi224](https://github.com/jerichoi224/Nothing-Gallery), purpose-built to bring Google Photos-level speed, fast scrolling, media organization, and a Nothing OS dot-matrix privacy vault to Android.

---

## ⚡ What's New Compared to the Original

| Feature | Original (`jerichoi224`) | Enhanced Fork (`arjid200`) |
| :--- | :--- | :--- |
| **Fast Scroller** | ❌ None (manual flick scrolling only) | ✅ **Google Photos-style semi-circle thumb scroller** with floating date bubble & haptics |
| **Album Sorting** | ❌ Flat unordered grid without dates | ✅ **Date-grouped & date-sorted** (newest-first under date headers like Google Photos) |
| **Recycle Bin / Trash** | ❌ None (deleting directly prompted system delete) | ✅ **Dedicated 30-day Trash page** with multi-select restore & permanent deletion |
| **Google Photos Trash Sync**| ❌ Trashed media lingered in Google Photos | ✅ **Native `MediaStore.createDeleteRequest`** permanently purges files and syncs across Google Photos |
| **Restore Folder Integrity**| ❌ Duplicated restored files into `/Pictures` | ✅ **In-place untrash / scan** restoring files directly to their original folders (`DCIM/Camera`, `Download`, etc.) |
| **Locked / Private Vault** | ❌ None | ✅ **Nothing OS dot-matrix 4-digit PIN vault** with hidden storage & in-place unlock |
| **Timeline Filter Pills** | ❌ None | ✅ **Filter pills** (`[ALL]`, `[PHOTOS]`, `[VIDEOS]`, `[SCREENSHOTS]`, `[FAVORITES]`) |
| **Grid Column Scaling** | ❌ Fixed 4 columns | ✅ **Dynamic grid toggle (`4 / 3 / 2` columns)** in Timeline and Album view |
| **EXIF & Metadata** | ❌ Basic title only | ✅ **Swipe-up EXIF Bottom Sheet** (file size, MP, resolution, camera model, date/time, interactive GPS map launcher) |
| **Video Player** | ❌ Basic play/pause | ✅ **Enhanced player** with 10s skip/rewind, loop toggle button, and EXIF inspector |
| **Large Album Performance** | ⚠️ Lag / memory spikes with 1,000+ photos | ✅ **Lazy `SliverGrid` virtualization** + batched chunk loader (`100` instant + `500`-item chunks) |
| **Automated Releases** | ❌ Manual local builds | ✅ **Automated GitHub Actions CI/CD** compiling installable release APKs on every push |

---

## ✨ Feature Highlights

### 1. Google Photos-Style Semi-Circle Fast Scroller (`MediaFastScroller`)
- Draggable semi-circle handle anchored along the right edge of **Timeline**, **Every Album**, **Videos**, and **Favorites**.
- Effortlessly glide through libraries of 1,000s of photos in seconds.
- **Floating Date Pill**: As you scrub, an animated pill displays the exact month, day, and year (`● Nov 11` / `● Oct 28, 2024`) of photos currently under your thumb.
- **Haptic Feedback**: Crisp tactile ticks trigger as you scrub across different date sections.
- **Discreet UX**: Reveals briefly on folder open or scroll, then smoothly fades out so your photos remain unobstructed.

### 2. Date-Grouped & Date-Sorted Albums
- Photos and videos inside **every album** are now organized under clean date headers (`Nov 11`, `2024 Oct 28`), matching the Google Photos layout.
- Fully virtualized with `SliverGrid` + `SliverFixedExtentList` so scrolling through albums with thousands of items is butter-smooth at 120Hz.

### 3. Dedicated Recycle Bin / Trash
- Safely stages deleted media with a 30-day retention countdown.
- Full multi-select selection bar: **RESTORE**, **DELETE FOREVER**, or **EMPTY TRASH**.
- **Android MediaStore Trash Sync**: Restoring untrashes files back into their **exact source folder** (preventing unwanted `/Pictures` folders). Permanent deletion invokes Android's native `createDeleteRequest` so media is purged permanently and immediately removed from Google Photos Bin as well.

### 4. Nothing OS Dot-Matrix Locked Vault
- Protect sensitive photos and videos in an isolated, encrypted-at-rest vault.
- Authenticated with a Nothing OS-styled dot-matrix 4-digit PIN keypad with error shake animations.
- Multi-select **UNLOCK** (restores in place to original directory) or **DELETE**.

### 5. Media Filter Pills & Grid Scaling
- Quick filter pills at the top of Timeline: `[ALL]`, `[PHOTOS]`, `[VIDEOS]`, `[SCREENSHOTS]`, and `[FAVORITES]`.
- Top header toggle to instantly switch between **2, 3, or 4 columns** to fit any screen size or thumbnail preference.

### 6. EXIF Details Bottom Sheet
- Tap the **Info (i)** button or swipe up on any photo/video.
- Inspect detailed metadata: formatted file size, megapixels, dimensions, camera model, date & time, and full storage path.
- If GPS coordinates are embedded, tap **Open in Google Maps** for instant navigation.

### 7. Enhanced Video Player
- 10-second skip forward and rewind buttons.
- Continuous loop toggle button with active red accent indicator.
- Integrated EXIF inspector.

---

## 📲 Download & Installation

Download the latest pre-compiled, self-signed `.apk` directly from GitHub Releases:

👉 **[Download Latest APK from Releases](https://github.com/arjid200/Nothing-Gallery/releases/latest)**

*Note: The APK is signed with universal release keys and works on any Android device running Android 8.0+ (API 26+) through Android 14+.*

---

## 🛠️ Automated Build (GitHub Actions)

Every commit to `main` triggers `.github/workflows/build-apk.yml`:
1. Checks out the repository.
2. Configures Java 17 Temurin and Flutter `3.13.9`.
3. Compiles `flutter build apk --release --no-tree-shake-icons`.
4. Uploads the build artifact and attaches it to GitHub Releases.

---

## 📄 License & Credits

- Original project by [jerichoi224](https://github.com/jerichoi224/Nothing-Gallery).
- Fork enhancements, fast scroller, native trash sync, and locked vault by [arjid200](https://github.com/arjid200/Nothing-Gallery).
- Distributed under the [GNU General Public License v3.0](LICENSE).
