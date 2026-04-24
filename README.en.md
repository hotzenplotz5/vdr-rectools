# 🎬 vdr-rectools

**vdr-rectools** (formerly *vdr-reccleaner*) is a modular, fully automated Bash suite for the Video Disk Recorder (VDR). It is used for managing, repairing, converting, and seamlessly integrating VDR recordings into media centers like Plex or Kodi.

---

## ✨ Features

* **📥 Smart Import:** Automatically detects and processes various video formats (e.g., MKV, MP4, AVI, MOV) and codecs (H.264, HEVC, MiniDV, web formats), choosing the optimal import strategy (remuxing or re-encoding).
* **📝 Intelligent Metadata:** Reads `.nfo` files (title, plot) during import and writes them directly into the VDR's `info` file for a perfect presentation.
* **🎬 TVScraper Integration:** Optionally triggers a metadata scrape in VDR after import (modes: `immediate` or `batch`).
* **🛠️ Smart Repair:** Repairs faulty recordings in a two-stage process: first, a quick header fix, followed by a full re-encode if necessary.
* **💬 Auto-Subtitles:** Automatically searches for matching subtitles during import and saves them as an `.srt` file with the recording.
* **🗜️ H.265 Shrink Mode:** Compresses large recordings into the space-saving HEVC (H.265) codec at the touch of a button.
* **📺 VDR OSD Integration:** Automatically integrates into the `reccmds.conf` command menu of the VDR.
* **✉️ Intelligent Reporting:** Sends success or failure reports via email.
* **🧹 Auto-Cleanup:** Finds and deletes empty recording folders in the video directory.

---

## ⚙️ The Import Workflow in Detail

The import process is the core of `vdr-rectools`. The script scans the `IMPORT_DIR` for common video files like `.mkv`, `.mp4`, `.avi`, `.mov`, or `.ts`.
When a file is found, the following happens in the background:

1.  **Find Metadata:** The script looks for a corresponding `.nfo` file (e.g., `My Movie.nfo`). If `<title>` and `<plot>` are found, they are used for the VDR recording. Otherwise, the filename is used as the title.
2.  **Create Structure:** A VDR-compliant recording folder is created (e.g., `/srv/vdr/video/My_Movie/2026-04-22.10.00.1-0.rec/`).
3.  **Gentle Remuxing:** The source file (`.mkv`, `.mp4`, etc.) is converted into a VDR-compatible `.ts` file without quality loss (`-c copy`).
4.  **Repair & Index:** The new `.ts` file is processed by `smart_repair` to correct timestamps. Afterward, the VDR index (`index`) is regenerated.
5.  **Write Metadata:** The `info` file is populated with the title and description from step 1.
6.  **Subtitles & TVScraper:** The script searches for subtitles and (if configured) triggers the TVScraper plugin.
7.  **Cleanup:** After a successful import, the original file is deleted from the import directory.

---

## 📦 System Requirements

The script is optimized for Debian/Ubuntu-based systems (like yaVDR). The following dependencies are automatically resolved when installing the `.deb` package:

* `vdr`
* `ffmpeg`
* `bash` (>= 4.0)
* `coreutils`, `findutils`
* `subliminal` (for subtitle download)
* `bsd-mailx` or `mailutils` (for reporting)

---

## 🚀 Installation

### Option A: Installation via the pre-built `.deb` package (Recommended)
Download the latest release from the GitHub Releases page and install it conveniently via APT.

```bash
# Replace * with the current version number
sudo apt install ./vdr-rectools_*.deb
```

### Option B: Manual Installation from Source Code
This method is intended for developers or for manual customizations.

```bash
# Clone the repository
git clone https://github.com/hotzenplotz5/vdr-rectools.git
cd vdr-rectools

# Build & install the package
debuild -us -uc
# Replace * with the current version number
sudo dpkg -i ../vdr-rectools_*.deb
```

---

## ⚙️ Configuration

File: `/etc/vdr/conf.d/vdr-rectools.conf`

| Variable | Description | Default |
| :--- | :--- | :--- |
| **AUTO_START_NIGHT** | Enables the nightly automatic scan (1=On, 0=Off) | `0` |
| **AUTO_TIMER** | General switch for timer-based actions | `0` |
| **IMPORT_DIR** | Path for video files to import | `/srv/video/Filme` |
| **MAIL_NOTIFY** | Email address for status reports | (empty) |
| **AUTO_SUB_DOWNLOAD** | Automatic download of subtitles | `1` |
| **SUB_LANG** | Language for subtitles (e.g., de, en) | `de` |
| **AUTO_ENCODE_IMPORT** | Automatic re-encoding on import (1=On, 0=Off) | `1` |
| **CRF_H264_DEFAULT** | CRF value for H.264 (lower=better) | `23` |
| **PRESET_H264_DEFAULT** | Preset for H.264 (e.g., `medium`, `fast`) | `medium` |
| **CRF_H265_DEFAULT** | CRF value for H.265 (lower=better) | `23` |
| **PRESET_H265_DEFAULT** | Preset for H.265 (e.g., `medium`, `fast`) | `medium` |
| **HW_ACCEL** | Hardware acceleration (`none`, `nvenc`, `vaapi`, `qsv`) | `none` |
| **CRF_H264_FALLBACK** | CRF value for fallback encoding | `23` |
| **PRESET_H264_FALLBACK**| Preset for fallback encoding | `fast` |
| **MIN_COMPRESSION_RATIO_H264** | Max file size in % of original for H.264 encodes | `70` |
| **MIN_COMPRESSION_RATIO_H265** | Max file size in % of original for H.265 encodes | `50` |
| **MIN_COMPRESSION_RATIO_H264_FALLBACK** | Max file size in % of original for H.264 fallback | `70` |
| **MIN_FREE_GB** | Minimum free disk space in GB | `20` |
| **MAX_FILES** | Maximum number of files per run | `10` |
| **PAUSE_WORK** | Pause between work steps (seconds) | `30` |
| **PAUSE_CHECK** | Pause between file checks (seconds) | `2` |
| **SNAPSHOT_TIME** | Timestamp for generated preview images | `00:05:00` |

---

## 🕹 Usage

### Terminal Commands
* `vdr-rectools start` - Starts a full scan (import & cleanup) in the background.
* `vdr-rectools import` - Starts only the import process.
* `vdr-rectools repair` - Starts a repair run for all recordings.
* `vdr-rectools status` - Shows PID, runtime, and the last log lines.
* `vdr-rectools stop` - Stops running background processes cleanly.
* `vdr-rectools cron` - Simulates the timer call (checks `AUTO_START_NIGHT`).
* `vdr-rectools repair_single <path>` - Repairs a single recording (path to the .rec folder).

### Systemd Timer (Automation)
The timer is active by default and triggers the scan (usually at night). However, it only runs if `AUTO_START_NIGHT=1` is set.
```bash
sudo systemctl status vdr-rectools.timer
```

---

## 📈 Monitoring & Feedback

### Logging
All operations are logged in detail. This is the first place to check for problems:
* **Path:** `/var/log/vdr-rectools.log`
* **Content:** Start/stop times, FFmpeg output during remuxing, import results.

### Email Notifications
If `MAIL_NOTIFY` is set, the script sends an email after each run with:
* A summary of imported films and repaired recordings.
* Warnings if disk space is low (`MIN_FREE_GB`).
* Detailed error messages if an import or remuxing failed.

---

## 📺 VDR OSD Integration
The commands are automatically integrated into the VDR menu (Commands key within a recording):
* **Repair recording (Rectools):** Starts repair for the current recording.
* **Cut commercials (Rectools):** Cuts the recording based on VDR marks.
* **Save space H.265 (Rectools):** Converts the recording to HEVC.
* **Plex/Kodi Sync (Rectools):** Triggers synchronization for external players.

---

## 📄 License & Maintainer
GPL-3.0+ | Maintainer: **Holger Schvestka** <hotzenplotz5@gmx.de>
