# FR570 Runner Pro (Garmin Forerunner 570 Watch Face)

A high-density Monkey C watch face built for the **Garmin Forerunner 570** (**42mm** `390×390` and **47mm** `454×454` AMOLED displays) featuring live training/recovery metrics, a rich 2-line weather forecast header, a **7-Day Running Average Step Target + Sparkline**, a **Next Calendar Event Card (Start Time + Title)**, a **Kathmandu (`UTC+5:45`) World Clock**, and **touch-and-hold glance shortcuts**.

## Features
- **Training, Recovery & Intensity Telemetry:**
  - **Training Pod (`ReadinessMode`):** Switchable between a composite **Readiness Estimate** (weighted from Body Battery, Stress, and Recovery Time) and Garmin's native **Training Status** complication (`COMPLICATION_TYPE_TRAINING_STATUS`), since Garmin Connect IQ does not expose the raw native Training Readiness score to third-party watch faces.
  - **Recovery Time Remaining (`RECOVERY`):** Subscribes to `COMPLICATION_TYPE_RECOVERY_TIME`.
  - **Weekly Intensity Minutes (`INTENSITY`):** Tracks weekly active minutes vs. weekly goal (`ActivityMonitor.Info.activeMinutesWeek` / `activeMinutesWeekGoal`) and drives the **Right Outer Progress Arc**.
  - **Live HR & Body Battery (`HR • BB`):** Combines live heart rate with Body Battery `%`.
- **Rich 2-Line Weather & Forecast Header:**
  - Line 1: Date + Current Temp + Feels-Like Temp (`NOV 19 • 18° FL16°`).
  - Line 2: Condition + Daily High/Low + Precipitation Chance `%` + Humidity `%` (`CLR H21/L11 • P20% H55%`).
- **7-Day Running Average Step Target & Sparkline:**
  - Reads up to 7 past days via `Toybox.ActivityMonitor.getHistory()` with 4 target modes (`100%`, `+5%`, `+10%`, or Garmin default), drives the **Left Outer Progress Arc**, and plots a 7-bar history sparkline + threshold line between `STEPS` and `7D TARGET`.
- **Battery % + Days Remaining:**
  - Bottom gauge displays both charge `%` and estimated days remaining (`System.Stats.batteryInDays`).
- **Touch-and-Hold Watch Face Shortcuts (`FR570WatchFaceDelegate.mc`):**
  - Long-press any zone on the watch face to jump straight into its native Garmin glance via `Complications.exitTo()`:
    - Top Weather Header → Weather Glance
    - Next Event Card → Calendar Glance
    - Training / Recovery / Steps / Intensity / HR / Battery pods → Matching Garmin Health & Training Glances
  - *(Note: For Music controls, hold the Forerunner 570's physical **DOWN** button from the watch face.)*
- **Next Event Card + Kathmandu World Clock + AMOLED AOD:**
  - Shows your next event start time + title (via `FR570CalendarServiceDelegate.mc` + `google_calendar_bridge.gs`, with `COMPLICATION_TYPE_CALENDAR_EVENTS` fallback) and your selectable dual world clock defaulting to **Kathmandu (`KTM • UTC+5:45`)**.

## Layout Styles, Themes & Design Notes
See [`DESIGN_NOTES.md`](DESIGN_NOTES.md) for the engineering & UX breakdown (1:1 physical 47mm preview workflow, TrueType `RobotoCondensedBold` scaling, 270° circular ring geometry, string compaction, and Connect IQ Beta deployment tips).

- **4 Watch Face Layout Styles (`CardStyle`):**
  1. `1. Chrono Ring Dials & Stadium Ribbon` *(Default)* — Notched halo bezel arcs, 270° `READY` ring + `REC` capsule + `STEPS` bay, and 3 bottom circular ring dials (`INTENS`, `HEART`, `BODY`).
  2. `4. Segmented Tach & Panoramic Cockpit Bay` — 12-block tachometer outer arcs, racing-cut slanted badges, unified Row 1 cockpit bay, and ticked circular bottom dials.
  3. `1+4 Hybrid` — Notched chrono bezel + stadium ribbons paired with the unified Row 1 cockpit bay and clean ring dials.
  4. `3. Seamless Pitch-Black AMOLED HUD` — Zero background boxes (`#000000`) with tapered laser hairlines and curved bottom arc meters.
- **4 Non-Blue Themes (`AccentColor`):** *Stealth Graphite & Racing Crimson* (default), *Warm Carbon & Solar Gold*, *Warm Bronze & Champagne*, and *Light Titanium / Alabaster*.
- **15 Configurable Connect IQ Settings:** Layout style, theme, chrono ticks toggle, outer arcs toggle, 7D sparkline toggle, gauge rings/bars toggle, seconds badge toggle, weather bar detail, world clock city (14 cities, `KTM` default), step target mode, training readiness/status toggle, customizable bottom-left & bottom-right metrics, battery format, and optional calendar JSON bridge URL.

## Project Structure
- `manifest.xml` — Connect IQ manifest targeting `fr57047mm` and `fr57042mm` with `Background`, `Communications`, `ComplicationSubscriber`, and `SensorHistory` permissions.
- `monkey.jungle` — Build configuration pointing to `manifest.xml`.
- `DESIGN_NOTES.md` — Physical-scale legibility, typography, and Monkey C rendering lessons.
- `studio/fr570_watchface_studio.html` — Interactive browser studio with theme switcher, 4 layout styles, touch shortcut tester, and `1:1 Watch Size (1.4")` scale toggle.
- `source/FR570WatchFaceApp.mc` — App entry point, touch delegate wiring, 15-minute temporal background registration, and background storage handler.
- `source/FR570WatchFaceDelegate.mc` — `WatchUi.WatchFaceDelegate` capturing `onPress` coordinates for touch shortcuts.
- `source/FR570WatchFaceView.mc` — Watch-face rendering, weather forecast, 7-day step target, complications, world clock, touch routing, and AOD burn-in protection.
- `source/FR570CalendarServiceDelegate.mc` — Background JSON fetcher (`Communications.makeWebRequest`) for calendar event titles.
- `google_calendar_bridge.gs` — Optional Google Apps Script endpoint returning `{ "time", "title" }`.
- `resources/settings/` & `resources/strings/` — Connect IQ phone app configuration.
- `resources/drawables/` — Launcher icon metadata and `launcher_icon.png`.

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
