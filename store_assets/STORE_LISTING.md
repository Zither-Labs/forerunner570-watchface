# Connect IQ Store Submission Sheet — DualTrack

## App Identity
- **App Name:** `DualTrack`
- **Category / App Type:** Watch Face
- **Version:** `1.0.0`
- **Package File:** `bin/DualTrack.iq`
- **Developer Website / Support URL:** `https://github.com/Zither-Labs/forerunner570-watchface`
- **Supported Devices:**
  - Garmin Forerunner 570 (47mm — `454×454` AMOLED)
  - Garmin Forerunner 570 (42mm — `390×390` AMOLED)
  - Garmin Forerunner 945 / Forerunner 945 LTE (`240×240` 64-Color MIP)

---

## Short Tagline
High-density runner telemetry watch face with dual outer progress arcs, 6 layouts, dual time zones, and an on-watch 360° Color Wheel.

---

## Full Store Description
**DualTrack** is a high-contrast instrument watch face engineered for Garmin Forerunner AMOLED and MIP watches. It combines running & recovery telemetry, a 2-line weather forecast, a progressive 7-day step target with sparkline, dual progress arcs with curved rim labels, and a live 14-city world clock in one clean dial.

### Works Right Out of the Box (No Account or Calendar Setup Required)
- By default, the center capsule displays your live **Daily Activity Summary** (`TODAY | Distance • Calories kcal`) with zero extra setup or permissions required.
- Optional **Calendar / Banner Modes** let you switch the center capsule in Garmin Connect IQ settings to:
  1. **Daily Summary** *(Default)*
  2. **Next Event** *(auto-falls back to Daily Summary when your schedule is clear)*
  3. **Always Next Event**
  4. **Custom Banner Note** *(your own motivational text or reminder)*
- *(Optional Private Google Calendar Bridge)*: Want full meeting titles on your wrist without sharing account credentials? Copy `google_calendar_bridge.gs` from `https://github.com/Zither-Labs/forerunner570-watchface`:
  1. Open `script.google.com`, paste `google_calendar_bridge.gs`, and set `EXPECTED_TOKEN`.
  2. Deploy as a **Web app** (**Execute as:** `Me`, **Access:** `Anyone`).
  3. Set **Middle Banner / Calendar Sync** to **On** in Garmin Connect IQ settings and paste your `/exec?key=SECRET` URL. Your events and URL stay strictly private between your Google Apps Script and your watch.

### 6 Selectable Layouts (#1–#6)
1. **Top Clock + Wide Box + Smooth Bezel**
2. **Pure Black Minimal** *(borderless HUD with thin laser arcs)*
3. **Split Screen** *(stacked left hours/minutes + telemetry deck)*
4. **Top Banner + Slanted Motorsport Boxes** *(Default — Midnight Ceramic Navy theme + Mixed bold numbers/clean labels + outer dual progress arcs)*
5. **Two-Tone Split** *(horizon split using your active theme colors)*
6. **Two-Tone Outer Ring + Black Center** *(24-hour perimeter ring + black center dial)*

### Curved Outer Arc Labels & Interactive On-Watch Color Wheel
- **Curved Bottom-Rim Arc Labels:** Left arc tracks **Steps vs. Target**, right arc tracks **Weekly Intensity Minutes vs. Goal** — selectable between **Label + %**, **Label Only**, **% Only**, or **Off**.
- **7 Curated Color Themes + On-Watch 360° Color Wheel:** Pick from 7 built-in high-contrast palettes or customize any Primary, Secondary/Ring, and Background color directly on your watch via **Hold UP → Watch Face → DualTrack → Customize** (touch ring to choose hue, tap center pill for `VIVID / MUTED / DEEP / SILVER` tone, press **START** to save).

### Telemetry, Weather & Shortcuts
- **Weather Header:** Current temp, feels-like/hi/lo range, and precipitation probability.
- **7-Day Step Target & Sparkline:** Choose 7-day average (`100%`, `+5%`, `+10%`) or Garmin fixed goal, paired with a 7-day bar chart.
- **Configurable Gauges:** Readiness estimate or Garmin Training Status, Recovery Time, Heart Rate, plus customizable bottom-left (`Intensity / Calories / Distance`) and bottom-right (`Body Battery / Stress / Calories / Floors`) dials.
- **14-City World Clock:** Instant second timezone readout (Kathmandu +5:45, New Delhi, London, New York, Chicago, Denver, Los Angeles, Paris/Berlin, Dubai, Bangkok, Singapore, Tokyo, Sydney, Auckland).
- **Touch-and-Hold Glance Shortcuts (Forerunner 570):** Long-press Weather, Calendar, Steps, Readiness, Heart Rate, Body Battery, or Battery to jump straight to the native Garmin glance.
- **Always-On Display (AOD):** Burn-in-safe minimal AMOLED sleep mode (`< 10%` lit pixels).

---

## What's New in v1.0.0 (Initial Public Release)
- Public launch of **DualTrack** for Garmin Forerunner 570 (47mm & 42mm AMOLED) and Forerunner 945 / 945 LTE (64-color MIP).
- 6 switchable layouts (`#1`–`#6`), 7 curated non-cobalt color schemes, and an **On-Watch Interactive 360° Color Wheel** (`Hold UP -> Watch Face -> DualTrack -> Customize`).
- Curved bottom-rim outer progress arc labels (`STEPS %` / `INT %`), 7-day average step target + sparkline, 14-city world clock, Daily Activity Summary default pill, and optional private Calendar JSON Bridge.

---

## App Permissions Notes (For Connect IQ Review)
- **Background & Communications:** Only active when the user manually configures their own optional self-hosted calendar bridge JSON URL in Watch Face Settings. No data is collected or transmitted anywhere else.
- **ComplicationSubscriber:** Used on CIQ 5+ devices (Forerunner 570) for native Training Readiness/Status, Recovery Time, Calendar time, and touch-and-hold glance shortcuts (`Complications.exitTo()`).
- **SensorHistory:** Reads recent Heart Rate, Body Battery, and Stress history samples on-device.

---

## Portal Upload Checklist
| Connect IQ Portal Slot | File Path | Dimensions |
| :--- | :--- | :--- |
| **App Package (`.iq`)** | `bin/DualTrack.iq` | Multi-device build |
| **Cover Image** | `store_assets/cover_image.png` | `500×500` PNG |
| **Hero Image (2:1)** | `store_assets/hero_banner.png` | `1440×720` PNG |
| **Screenshot 1 (Default Active)** | `store_assets/screenshot_1_active.png` | `500×500` PNG |
| **Screenshot 2 (AMOLED AOD)** | `store_assets/screenshot_2_aod.png` | `500×500` PNG |
| **Screenshot 3 (All 6 Layouts)** | `store_assets/screenshot_3_layouts.png` | `1000×640` PNG |
| **Screenshot 4 (Color Wheel + Themes)** | `store_assets/screenshot_4_color_wheel.png` | `900×500` PNG |
| **Screenshot 5 (Themes & 945 MIP)** | `store_assets/screenshot_5_themes_and_mip.png` | `900×500` PNG |
