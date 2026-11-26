# FR570 Runner Pro (Garmin Forerunner 570 & 945 Watch Face)

A high-density Monkey C watch face built for **Garmin Forerunner 570** (**47mm** `454×454` and **42mm** `390×390` AMOLED) and **Garmin Forerunner 945 / 945 LTE** (`240×240` 64-color MIP), featuring live training/recovery metrics, a rich 2-line weather header, a **7-Day Running Average Step Target + Sparkline**, a **Middle Activity / Calendar / Note Banner**, a selectable **World Clock** (`KTM` default), and **touch-and-hold glance shortcuts** on FR570.

## Features
- **Works Out of the Box Without Calendar Setup (`CalendarMode`):**
  - By default (`Off - Daily Summary`), the center pill shows your live **`TODAY | Distance • Calories kcal`** summary (`5.4 km • 1,840 kcal`) — no permissions or calendar URL needed.
  - Switchable in Garmin Connect IQ settings to:
    - **Off - Daily Summary (Distance & Calories)** *(default)*
    - **On - Next Event (or Daily Summary when free)**
    - **On - Next Event Only (`--:--` when free)**
    - **Off - Custom Banner Note** *(displays your own custom text pill)*
- **Optional Google Calendar Setup (Full Meeting Titles):**
  1. Open [script.google.com](https://script.google.com) signed into your own Google account, create a **New project**, and paste [`google_calendar_bridge.gs`](google_calendar_bridge.gs).
  2. Set a private passphrase in `var EXPECTED_TOKEN = "YourSecretHere";`, click **Deploy → New deployment → Web app** (**Execute as:** `Me`, **Who has access:** `Anyone`), and authorize calendar access.
  3. In your phone's **Garmin Connect IQ** app → **Watch Face Settings**, set **Middle Banner / Calendar Sync** to **On**, and paste `https://script.google.com/macros/s/.../exec?key=YourSecretHere` into **Calendar JSON Bridge URL**. Your URL and events stay strictly private between your Google Apps Script and your watch.
- **Training, Recovery & Intensity Telemetry:**
  - **Training Pod (`ReadinessMode`):** Switchable between a composite **Readiness Estimate** (Body Battery + Stress + Recovery Time) and native **Training Status** (FR570).
  - **Recovery Time Remaining (`REC`):** Native complication on FR570.
  - **Weekly Intensity Minutes (`INTENS`):** Tracks weekly active minutes vs. weekly goal and drives the **Right Outer Progress Arc**.
- **Rich Weather Header, 7-Day Step Target Sparkline & Battery:**
  - Date + Temp + Hi/Lo/Precip, 7-day average step goal + bar chart, configurable left/right dial metrics, and battery `%` + days remaining.
- **Touch-and-Hold Watch Face Shortcuts (FR570):**
  - Long-press any zone to jump straight to its native Garmin glance via `Complications.exitTo()`.

## Layout Styles & Themes
- **6 Watch Face Layouts (`CardStyle`):**
  1. `#1 Top Clock + Wide Box + Smooth Bezel` *(Default)*
  2. `#2 Pure Black Minimal (No Boxes, Thin Arcs)`
  3. `#3 Split Screen: Big Stacked Clock on Left`
  4. `#4 Top Event Banner + Slanted Boxes` *(with outer dual progress arcs)*
  5. `#5 Red & Blue Split: Red Top / Blue Bottom`
  6. `#6 Red & Blue Outer Ring + Black Center`
- **4 Color Schemes (`AccentColor` for `#1`–`#4`):** *Black + Red & Orange*, *Black + Gold & Green*, *Black + Vivid Cobalt Blue*, and *Royal Blue + Crimson Red & Gold* (plus **Font Style** selector: *Normal / Crisp*, *Bold*, or *Mixed*).

## Project Structure
- `manifest.xml` — Targets `fr57047mm`, `fr57042mm`, `fr945`, and `fr945lte` with `Background`, `Communications`, `ComplicationSubscriber`, and `SensorHistory`.
- `monkey.jungle` — Maps `source-comp` for FR570 and `source-nocomp` for FR945 / FR945 LTE.
- `studio/fr570_watchface_studio.html` — Interactive browser preview studio with all layouts, themes, fonts, and middle-banner modes.
- `source/` — App entry point, background calendar JSON fetcher, and responsive AMOLED/MIP view renderer.
- `google_calendar_bridge.gs` — Self-hosted Google Apps Script template with optional `EXPECTED_TOKEN` key check.
- `resources/settings/` & `resources/strings/` — Connect IQ phone settings with built-in setup instructions.

## How to Build, Test & Sideload

### 1. Prerequisites
1. Install **Visual Studio Code** and the official **Monkey C** extension by Garmin.
2. Install the **Garmin Connect IQ SDK Manager**, download the latest Connect IQ SDK (`5.0+` / `7.x` / `8.x`), and download the **Forerunner 570** device package.
3. Generate a developer key in VS Code via `Ctrl+Shift+P` → `Monkey C: Generate a Developer Key`.

### 2. Run in the Garmin Simulator
1. Open `forerunner570-watchface` in VS Code.
2. If your SDK uses a different Forerunner 570 device ID, run `Ctrl+Shift+P` → `Monkey C: Edit Products` to select your installed Forerunner 570 targets.
3. Press `F5` (or `Monkey C: Build Current Project`) to run it in the Connect IQ Simulator.

### 3. Sideload onto Your Forerunner 570 (USB)
1. Run `Ctrl+Shift+P` → `Monkey C: Build for Device` to export a compiled `.prg` file.
2. Connect your Forerunner 570 via USB and copy the `.prg` into `GARMIN/APPS/`.
3. Disconnect safely and choose **FR570 Runner Pro** in your watch-face picker.
