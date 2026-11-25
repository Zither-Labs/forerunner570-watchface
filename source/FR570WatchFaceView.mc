using Toybox.Activity;
using Toybox.ActivityMonitor;
using Toybox.Application.Properties;
using Toybox.Application.Storage;
using Toybox.Complications;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;
using Toybox.SensorHistory;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.WatchUi;
using Toybox.Weather;

//! High-density AMOLED watch face for Garmin Forerunner 570 with training, weather forecast, 7D target, and touch shortcuts.
class FR570WatchFaceView extends WatchUi.WatchFace {

    //! Supported World Clock presets: [City Code, UTC Offset in Minutes].
    private const WORLD_CITIES = [
        ["KTM", 345],   // 0: Kathmandu (UTC+5:45)
        ["DEL", 330],   // 1: New Delhi (UTC+5:30)
        ["LON", 0],     // 2: London / UTC (UTC+0)
        ["NYC", -300],  // 3: New York (UTC-5)
        ["CHI", -360],  // 4: Chicago (UTC-6)
        ["DEN", -420],  // 5: Denver (UTC-7)
        ["LAX", -480],  // 6: Los Angeles (UTC-8)
        ["CET", 60],    // 7: Paris / Berlin (UTC+1)
        ["DXB", 240],   // 8: Dubai (UTC+4)
        ["BKK", 420],   // 9: Bangkok (UTC+7)
        ["SIN", 480],   // 10: Singapore / HK (UTC+8)
        ["TYO", 540],   // 11: Tokyo (UTC+9)
        ["SYD", 600],   // 12: Sydney (UTC+10)
        ["AKL", 720]    // 13: Auckland (UTC+12)
    ];

    private const TRAINING_STATUS_MAP = {
        "PRODUCTIVE" => "PROD",
        "PEAKING" => "PEAK",
        "MAINTAINING" => "MAINT",
        "RECOVERY" => "RECOV",
        "STRAINED" => "STRN",
        "OVERREACHING" => "OVER",
        "UNPRODUCTIVE" => "UNPRD",
        "DETRAINING" => "DETRN",
        "NO STATUS" => "NONE"
    };

    private const CONDITION_LABELS = {
        Weather.CONDITION_CLEAR => "CLR",
        Weather.CONDITION_PARTLY_CLOUDY => "PTCLD",
        Weather.CONDITION_MOSTLY_CLOUDY => "CLDY",
        Weather.CONDITION_CLOUDY => "CLDY",
        Weather.CONDITION_RAIN => "RAIN",
        Weather.CONDITION_LIGHT_RAIN => "LTRN",
        Weather.CONDITION_HEAVY_RAIN => "HVRN",
        Weather.CONDITION_SHOWERS => "SHWR",
        Weather.CONDITION_SCATTERED_SHOWERS => "SHWR",
        Weather.CONDITION_CHANCE_OF_SHOWERS => "SHWR",
        Weather.CONDITION_LIGHT_SHOWERS => "SHWR",
        Weather.CONDITION_HEAVY_SHOWERS => "HVRN",
        Weather.CONDITION_THUNDERSTORMS => "TSTRM",
        Weather.CONDITION_SCATTERED_THUNDERSTORMS => "TSTRM",
        Weather.CONDITION_SNOW => "SNOW",
        Weather.CONDITION_LIGHT_SNOW => "LTSNW",
        Weather.CONDITION_HEAVY_SNOW => "HVSNW",
        Weather.CONDITION_WINDY => "WIND",
        Weather.CONDITION_FOG => "FOG",
        Weather.CONDITION_HAZY => "HAZE",
        Weather.CONDITION_PARTLY_CLEAR => "PTCLR",
        Weather.CONDITION_MOSTLY_CLEAR => "MCLR"
    };

    private var _screenWidth as Lang.Number = 454;
    private var _screenHeight as Lang.Number = 454;
    private var _fontWidthLoaded as Lang.Number = 0;
    private var _isSleeping as Lang.Boolean = false;
    private var _burnInOffsetX as Lang.Number = 0;
    private var _burnInOffsetY as Lang.Number = 0;

    private var _fLabel as Graphics.FontType = Graphics.FONT_XTINY;
    private var _fSmall as Graphics.FontType = Graphics.FONT_XTINY;
    private var _fEvent as Graphics.FontType = Graphics.FONT_XTINY;
    private var _fMidValue as Graphics.FontType = Graphics.FONT_SMALL;
    private var _fValue as Graphics.FontType = Graphics.FONT_TINY;
    private var _fTime as Graphics.FontType = Graphics.FONT_NUMBER_MEDIUM;

    private var _calendarCompId as Complications.Id? = null;
    private var _recoveryCompId as Complications.Id? = null;
    private var _trainingStatusCompId as Complications.Id? = null;

    private var _nextCalendarEvent as Lang.String? = null;
    private var _recoveryHours as Lang.Number? = null;
    private var _trainingStatusText as Lang.String? = null;

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _screenWidth = dc.getWidth();
        _screenHeight = dc.getHeight();
        initVectorFonts(_screenWidth);
    }

    //! Loads all-bold scaled TrueType system vector fonts (RobotoCondensedBold) for 1:1 47mm legibility.
    private function initVectorFonts(width as Lang.Number) as Void {
        if (_fontWidthLoaded == width) {
            return;
        }
        _fontWidthLoaded = width;
        var scale = width.toFloat() / 454.0;
        var boldFaces = ["RobotoCondensedBold", "RobotoRegular"] as Lang.Array<Lang.String>;
        _fLabel = loadVectorFontFace(boldFaces, (22.0 * scale).toNumber(), Graphics.FONT_XTINY);
        _fSmall = loadVectorFontFace(boldFaces, (26.0 * scale).toNumber(), Graphics.FONT_XTINY);
        _fEvent = loadVectorFontFace(boldFaces, (32.0 * scale).toNumber(), Graphics.FONT_TINY);
        _fMidValue = loadVectorFontFace(boldFaces, (36.0 * scale).toNumber(), Graphics.FONT_SMALL);
        _fValue = loadVectorFontFace(boldFaces, (44.0 * scale).toNumber(), Graphics.FONT_TINY);
        _fTime = loadVectorFontFace(boldFaces, (98.0 * scale).toNumber(), Graphics.FONT_NUMBER_MEDIUM);
    }

    private function loadVectorFontFace(
        faces as Lang.Array<Lang.String>,
        pxSize as Lang.Number,
        fallback as Graphics.FontType
    ) as Graphics.FontType {
        if (Graphics has :getVectorFont) {
            try {
                var vf = Graphics.getVectorFont({
                    :face => faces,
                    :size => (pxSize > 8) ? pxSize : 8
                });
                if (vf != null) {
                    return vf as Graphics.FontType;
                }
            } catch (ex) {
            }
        }
        return fallback;
    }

    function onShow() as Void {
        initComplications();
    }

    function onHide() as Void {
        if (Toybox has :Complications) {
            Complications.registerComplicationChangeCallback(null);
        }
    }

    function onEnterSleep() as Void {
        _isSleeping = true;
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        _isSleeping = false;
        _burnInOffsetX = 0;
        _burnInOffsetY = 0;
        WatchUi.requestUpdate();
    }

    //! Subscribes to native Garmin complications for Calendar, Recovery Time, and Training Status.
    private function initComplications() as Void {
        if (!(Toybox has :Complications)) {
            return;
        }
        try {
            Complications.registerComplicationChangeCallback(self.method(:onComplicationUpdated));

            _calendarCompId = subscribeComplication(Complications.COMPLICATION_TYPE_CALENDAR_EVENTS);
            _recoveryCompId = subscribeComplication(Complications.COMPLICATION_TYPE_RECOVERY_TIME);
            _trainingStatusCompId = subscribeComplication(Complications.COMPLICATION_TYPE_TRAINING_STATUS);
        } catch (ex) {
        }
    }

    private function subscribeComplication(compType as Complications.Type) as Complications.Id? {
        try {
            var compId = new Complications.Id(compType);
            if (compId != null) {
                Complications.subscribeToUpdates(compId);
                readComplicationValue(compId);
            }
            return compId;
        } catch (ex) {
        }
        return null;
    }

    function onComplicationUpdated(complicationId as Complications.Id) as Void {
        readComplicationValue(complicationId);
        WatchUi.requestUpdate();
    }

    private function readComplicationValue(complicationId as Complications.Id) as Void {
        try {
            var comp = Complications.getComplication(complicationId);
            var val = (comp != null) ? comp.value : null;

            if (_calendarCompId != null && complicationId.equals(_calendarCompId as Complications.Id)) {
                _nextCalendarEvent = (val != null) ? val.toString() : null;
            } else if (_recoveryCompId != null && complicationId.equals(_recoveryCompId as Complications.Id)) {
                _recoveryHours = parseRecoveryHours(val);
            } else if (_trainingStatusCompId != null && complicationId.equals(_trainingStatusCompId as Complications.Id)) {
                _trainingStatusText = (val != null) ? val.toString() : null;
            }
        } catch (ex) {
        }
    }

    //! Launches the matching native Garmin glance when the user touch-and-holds a zone.
    function launchShortcutAt(x as Lang.Number, y as Lang.Number) as Lang.Boolean {
        if (!(Toybox has :Complications) || !(Complications has :exitTo)) {
            return false;
        }

        var w = _screenWidth;
        var h = _screenHeight;
        var compType = null as Complications.Type?;

        if (y < (h * 0.14)) {
            compType = Complications.COMPLICATION_TYPE_CURRENT_WEATHER;
        } else if (y >= (h * 0.34) && y < (h * 0.48)) {
            compType = Complications.COMPLICATION_TYPE_CALENDAR_EVENTS;
        } else if (y >= (h * 0.47) && y < (h * 0.655)) {
            if (x < (w * 0.32)) {
                compType = Complications.COMPLICATION_TYPE_TRAINING_STATUS;
            } else if (x < (w * 0.45)) {
                compType = Complications.COMPLICATION_TYPE_RECOVERY_TIME;
            } else {
                compType = Complications.COMPLICATION_TYPE_STEPS;
            }
        } else if (y >= (h * 0.655) && y < (h * 0.84)) {
            if (x < (w * 0.39)) {
                var blMode = getNumberProperty("BottomLeftMetric", 0);
                compType = (blMode == 1)
                    ? Complications.COMPLICATION_TYPE_CALORIES
                    : Complications.COMPLICATION_TYPE_INTENSITY_MINUTES;
            } else if (x <= (w * 0.61)) {
                compType = Complications.COMPLICATION_TYPE_HEART_RATE;
            } else {
                var brMode = getNumberProperty("BottomRightMetric", 0);
                if (brMode == 1) {
                    compType = Complications.COMPLICATION_TYPE_STRESS;
                } else if (brMode == 2) {
                    compType = Complications.COMPLICATION_TYPE_CALORIES;
                } else if (brMode == 3) {
                    compType = Complications.COMPLICATION_TYPE_FLOORS_CLIMBED;
                } else {
                    compType = Complications.COMPLICATION_TYPE_BODY_BATTERY;
                }
            }
        } else if (y >= (h * 0.84)) {
            compType = Complications.COMPLICATION_TYPE_BATTERY;
        }

        if (compType != null) {
            try {
                Complications.exitTo(new Complications.Id(compType as Complications.Type));
                return true;
            } catch (ex) {
            }
        }
        return false;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setAntiAlias(true);

        var width = dc.getWidth();
        var height = dc.getHeight();
        _screenWidth = width;
        _screenHeight = height;
        initVectorFonts(width);
        var cx = width / 2;
        var cy = height / 2;

        var clockTime = System.getClockTime();
        var worldCityIndex = getNumberProperty("WorldCity", 0);
        var stepTargetMode = getNumberProperty("StepTargetMode", 0);
        var readinessMode = getNumberProperty("ReadinessMode", 0);
        var themeIndex = getNumberProperty("AccentColor", 0);
        var cardStyle = getNumberProperty("CardStyle", 0);
        var weatherDetailMode = getNumberProperty("WeatherDetailMode", 0);
        var bottomLeftMetric = getNumberProperty("BottomLeftMetric", 0);
        var bottomRightMetric = getNumberProperty("BottomRightMetric", 0);
        var batteryFormat = getNumberProperty("BatteryFormat", 0);
        var theme = getThemePalette(themeIndex);
        var showSeconds = getBooleanProperty("ShowSeconds", true);
        var showChronoTicks = getBooleanProperty("ShowChronoTicks", true);
        var showRings = getBooleanProperty("ShowStepsArc", true);
        var showSparkline = getBooleanProperty("ShowSparkline", true);
        var showMicroGauges = getBooleanProperty("ShowMicroGauges", true);

        var bgColor = (cardStyle == 3 && themeIndex != 3) ? 0x000000 : (theme[:bg] as Lang.Number);
        dc.setColor(bgColor, bgColor);
        dc.clear();

        if (_isSleeping) {
            updateBurnInShift(clockTime.min);
            drawAlwaysOnDisplay(dc, cx, cy, width, clockTime, worldCityIndex);
            return;
        }

        var actInfo = ActivityMonitor.getInfo();
        var steps = (actInfo.steps != null) ? (actInfo.steps as Lang.Number) : 0;
        var bodyBattery = getLatestBodyBattery();
        var stress = getLatestStress();

        var intMins = 0;
        if (actInfo.activeMinutesWeek != null) {
            intMins = (actInfo.activeMinutesWeek as ActivityMonitor.ActiveMinutes).total;
        }
        var intGoal = (actInfo.activeMinutesWeekGoal != null && (actInfo.activeMinutesWeekGoal as Lang.Number) > 0)
            ? (actInfo.activeMinutesWeekGoal as Lang.Number)
            : 150;

        var stepInfo = computeStepTargetInfo(actInfo, stepTargetMode);
        var stepTarget = stepInfo[:target] as Lang.Number;
        var stepHistory = stepInfo[:history] as Lang.Array<Lang.Number>;

        if (showChronoTicks && cardStyle != 1) {
            drawChronographTicks(dc, cx, cy, (width / 2) - 2, theme);
        }
        if (showRings) {
            drawDualProgressArcs(dc, cx, cy, width, steps, stepTarget, intMins, intGoal, cardStyle, theme);
        }

        drawTopWeatherForecastBar(dc, cx, width, height, weatherDetailMode, theme);

        var timeBottomY = drawTimeBlock(dc, cx, width, height, clockTime, theme, showSeconds);
        var pillBottomY = drawWorldClockPill(dc, cx, width, timeBottomY, worldCityIndex, cardStyle, theme);
        var cardBottomY = drawNextEventCard(dc, cx, width, pillBottomY, cardStyle, theme);

        drawDataPodGrid(
            dc, cx, width, height, cardBottomY,
            actInfo, steps, stepTarget, stepTargetMode, stepHistory,
            intMins, intGoal, bodyBattery, stress,
            readinessMode, cardStyle, showSparkline, showMicroGauges,
            bottomLeftMetric, bottomRightMetric, theme
        );
        drawBottomBatteryBar(dc, cx, height, width, batteryFormat, theme);
    }

    //! Returns palette colors for Stealth Graphite & Racing Crimson (0) and 3 other non-blue themes.
    private function getThemePalette(themeIndex as Lang.Number) as Lang.Dictionary {
        if (themeIndex == 1) {
            return {
                :bg => 0x080807, :cardBg => 0x161514, :cardBd => 0x2A2826, :specular => 0x3F3B36,
                :badgeBg => 0x262320, :primary => 0xF59E0B, :secondary => 0xF97316, :bodyBat => 0x10B981,
                :crimson => 0xEF4444, :rec => 0xD97706, :text => 0xFAF8F5, :muted => 0xE4E4E7,
                :dim => 0xD4D4D8, :tickMajor => 0x57534E, :tickMinor => 0x292524, :track => 0x24211E,
                :cloud => 0xE7E5E4, :tipDot => 0xFFFFFF, :pillText => 0xFDE047, :onPrimary => 0x0F0F0F,
                :halo => 0x55340A, :shadow => 0x452805,
                :zoneCols => [0x57534E, 0x10B981, 0xF59E0B, 0xF97316, 0xEF4444],
                :readyCols => [0xEF4444, 0xF59E0B, 0x10B981, 0xF97316]
            };
        } else if (themeIndex == 2) {
            return {
                :bg => 0x0C0908, :cardBg => 0x1C1613, :cardBd => 0x362B24, :specular => 0x4E3E34,
                :badgeBg => 0x2D241E, :primary => 0xEAB308, :secondary => 0xD97706, :bodyBat => 0x84CC16,
                :crimson => 0xEF4444, :rec => 0xD97706, :text => 0xF5F5F4, :muted => 0xE4E4E7,
                :dim => 0xD4D4D8, :tickMajor => 0x695C50, :tickMinor => 0x302721, :track => 0x28201B,
                :cloud => 0xE7E2DC, :tipDot => 0xFFFFFF, :pillText => 0xFDE68A, :onPrimary => 0x14100C,
                :halo => 0x4A3808, :shadow => 0x3C2C05,
                :zoneCols => [0x786C60, 0x84CC16, 0xEAB308, 0xD97706, 0xEF4444],
                :readyCols => [0xEF4444, 0xEAB308, 0x84CC16, 0xD97706]
            };
        } else if (themeIndex == 3) {
            return {
                :bg => 0xE5E0D8, :cardBg => 0xF5F2EB, :cardBd => 0xC7C0B5, :specular => 0xFFFFFF,
                :badgeBg => 0xD8D2C8, :primary => 0xD97706, :secondary => 0x059669, :bodyBat => 0x059669,
                :crimson => 0xDC2626, :rec => 0xB45309, :text => 0x1C1917, :muted => 0x57534E,
                :dim => 0x78716C, :tickMajor => 0x78716C, :tickMinor => 0xC7C0B5, :track => 0xD0CAC0,
                :cloud => 0x78716C, :tipDot => 0x1C1917, :pillText => 0x1C1917, :onPrimary => 0xFFFFFF,
                :halo => 0xD6C8B8, :shadow => 0xC2B6A6,
                :zoneCols => [0x78716C, 0x059669, 0xD97706, 0xEA580C, 0xDC2626],
                :readyCols => [0xDC2626, 0xD97706, 0x059669, 0x059669]
            };
        }
        // Default 0: Stealth Graphite & Racing Crimson (Zero Blue)
        return {
            :bg => 0x09090B, :cardBg => 0x17171A, :cardBd => 0x2C2C30, :specular => 0x3F3F46,
            :badgeBg => 0x27272A, :primary => 0xEF4444, :secondary => 0xF97316, :bodyBat => 0xE4E4E7,
            :crimson => 0xEF4444, :rec => 0xF97316, :text => 0xFFFFFF, :muted => 0xE4E4E7,
            :dim => 0xD4D4D8, :tickMajor => 0x71717A, :tickMinor => 0x27272A, :track => 0x202024,
            :cloud => 0xE4E4E7, :tipDot => 0xFFFFFF, :pillText => 0xF4F4F5, :onPrimary => 0xFFFFFF,
            :halo => 0x551418, :shadow => 0x4B1215,
            :zoneCols => [0x52525B, 0xE4E4E7, 0xF59E0B, 0xF97316, 0xEF4444],
            :readyCols => [0xEF4444, 0xEF4444, 0xE4E4E7, 0xF97316]
        };
    }

    //! Computes the 7-day running-average step target and daily step array from ActivityMonitor.getHistory().
    private function computeStepTargetInfo(
        actInfo as ActivityMonitor.Info,
        targetMode as Lang.Number
    ) as Lang.Dictionary {
        var fallbackGoal = (actInfo.stepGoal != null && (actInfo.stepGoal as Lang.Number) > 0)
            ? (actInfo.stepGoal as Lang.Number)
            : 10000;

        var historySteps = [] as Lang.Array<Lang.Number>;
        var totalSteps = 0;
        var validDays = 0;
        var isNewestFirst = false;

        if (ActivityMonitor has :getHistory) {
            var historyArr = ActivityMonitor.getHistory();
            if (historyArr != null) {
                var count = historyArr.size();
                if (count > 7) {
                    count = 7;
                }
                if (count >= 2) {
                    var h0 = historyArr[0];
                    var h1 = historyArr[1];
                    if (h0 != null && h1 != null) {
                        var m0 = h0.startOfDay;
                        var m1 = h1.startOfDay;
                        if (m0 != null && m1 != null && (m0 as Time.Moment).value() > (m1 as Time.Moment).value()) {
                            isNewestFirst = true;
                        }
                    }
                }
                for (var i = 0; i < count; i++) {
                    var idx = isNewestFirst ? (count - 1 - i) : i;
                    var item = historyArr[idx];
                    if (item != null && item.steps != null) {
                        var daySteps = item.steps as Lang.Number;
                        historySteps.add(daySteps);
                        totalSteps += daySteps;
                        validDays += 1;
                    }
                }
            }
        }

        var avg7d = (validDays > 0) ? (totalSteps / validDays) : fallbackGoal;
        if (avg7d <= 0) {
            avg7d = fallbackGoal;
        }

        var target = fallbackGoal;
        if (targetMode >= 0 && targetMode <= 2) {
            var pctMultipliers = [100, 105, 110];
            target = (avg7d * pctMultipliers[targetMode]) / 100;
        }
        if (target <= 0) {
            target = fallbackGoal;
        }

        return {
            :target => target,
            :avg7d => avg7d,
            :history => historySteps
        };
    }

    //! Computes a 0-100 readiness estimate from Body Battery (50%), low Stress (25%), and Recovery Time (25%).
    private function computeReadinessScore(
        bodyBattery as Lang.Number?,
        stress as Lang.Number?,
        recoveryHours as Lang.Number?
    ) as Lang.Number? {
        if (bodyBattery == null && stress == null && recoveryHours == null) {
            return null;
        }
        var bbScore = (bodyBattery != null) ? clamp100(bodyBattery as Lang.Number) : 65;
        var stressScore = (stress != null) ? (100 - clamp100(stress as Lang.Number)) : 65;
        var recHrs = (recoveryHours != null) ? (recoveryHours as Lang.Number) : 8;
        var recScore = clamp100(100 - ((recHrs * 100) / 48));

        return ((bbScore * 50) + (stressScore * 25) + (recScore * 25)) / 100;
    }

    //! Shifts content slightly each minute during AMOLED Always-On Display mode.
    private function updateBurnInShift(minute as Lang.Number) as Void {
        var step = minute % 4;
        _burnInOffsetX = (step == 1) ? 3 : ((step == 3) ? -3 : 0);
        _burnInOffsetY = (step == 2) ? 3 : ((step == 0) ? -3 : 0);
    }

    //! Draws a low-pixel-density screen for AMOLED Always-On Display (AOD) mode.
    private function drawAlwaysOnDisplay(
        dc as Graphics.Dc,
        cx as Lang.Number,
        cy as Lang.Number,
        width as Lang.Number,
        clockTime as System.ClockTime,
        worldCityIndex as Lang.Number
    ) as Void {
        var drawX = cx + _burnInOffsetX;
        var drawY = cy + _burnInOffsetY;

        var parts = formatClockParts(clockTime);
        var timeText = (parts[:hour] as Lang.String) + ":" + (parts[:min] as Lang.String);
        var timeFont = selectTimeFont(dc, timeText, (width * 0.72).toNumber());
        var fontH = dc.getFontHeight(timeFont);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            drawX,
            drawY - (fontH / 2) - 10,
            timeFont,
            timeText,
            Graphics.TEXT_JUSTIFY_CENTER
        );

        var worldStr = getFormattedWorldTime(worldCityIndex);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            drawX,
            drawY + (fontH / 2) - 4,
            Graphics.FONT_XTINY,
            worldStr,
            Graphics.TEXT_JUSTIFY_CENTER
        );

        var ev = resolveNextEvent();
        var evTime = ev[:time] as Lang.String;
        var evTitle = ev[:title] as Lang.String;
        var evSummary = !evTime.equals("") ? (evTime + " • " + evTitle) : "No upcoming events";
        var fitted = fitTextToWidth(dc, evSummary, _fSmall, (width * 0.72).toNumber());
        dc.drawText(
            drawX,
            drawY + (fontH / 2) + 20,
            _fSmall,
            fitted,
            Graphics.TEXT_JUSTIFY_CENTER
        );
    }

    //! Draws dual outer side arcs honoring CardStyle (0/2=Notched+Halo, 1=Segmented Tach, 3=Laser).
    private function drawDualProgressArcs(
        dc as Graphics.Dc,
        cx as Lang.Number,
        cy as Lang.Number,
        width as Lang.Number,
        steps as Lang.Number,
        stepTarget as Lang.Number,
        intMins as Lang.Number,
        intGoal as Lang.Number,
        cardStyle as Lang.Number,
        theme as Lang.Dictionary
    ) as Void {
        var primaryCol = theme[:primary] as Lang.Number;
        var secondaryCol = theme[:secondary] as Lang.Number;
        var trackCol = theme[:track] as Lang.Number;
        var guideCol = theme[:tickMinor] as Lang.Number;
        var tipDotCol = theme[:tipDot] as Lang.Number;
        var bgCol = (cardStyle == 3 && (theme[:bg] as Lang.Number) != 0xE5E0D8) ? 0x000000 : (theme[:bg] as Lang.Number);

        var radius = (width / 2) - 11;
        var stepRatio = clampRatio(steps.toFloat() / stepTarget.toFloat());
        var intRatio = clampRatio(intMins.toFloat() / intGoal.toFloat());

        if (cardStyle == 1) {
            // Option 4: 12 Discrete Curved Tachometer Segments per side
            dc.setPenWidth(6);
            var segs = 12;
            var litLeft = ((segs.toFloat() * stepRatio) + 0.5).toNumber();
            var litRight = ((segs.toFloat() * intRatio) + 0.5).toNumber();
            for (var s = 0; s < segs; s++) {
                var aStartL = 235 - ((s * 110) / segs);
                var aEndL = 235 - (((s + 1) * 110) / segs) + 2;
                dc.setColor((s < litLeft) ? primaryCol : trackCol, Graphics.COLOR_TRANSPARENT);
                dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, aStartL, aEndL);

                var aStartR = 305 + ((s * 110) / segs);
                var aEndR = 305 + (((s + 1) * 110) / segs) - 2;
                if (aStartR >= 360) {
                    aStartR -= 360;
                }
                if (aEndR >= 360) {
                    aEndR -= 360;
                }
                dc.setColor((s < litRight) ? secondaryCol : trackCol, Graphics.COLOR_TRANSPARENT);
                dc.drawArc(cx, cy, radius, Graphics.ARC_COUNTER_CLOCKWISE, aStartR, aEndR);
            }
            dc.setPenWidth(1);
            return;
        }

        // Inner hairline parallel guide arcs & radial end-cap brackets
        dc.setPenWidth(1);
        dc.setColor(guideCol, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, radius - 5, Graphics.ARC_CLOCKWISE, 235, 125);
        dc.drawArc(cx, cy, radius - 5, Graphics.ARC_COUNTER_CLOCKWISE, 305, 55);
        drawRadialTickAtDeg(dc, cx, cy, radius - 5, radius + 3, 235);
        drawRadialTickAtDeg(dc, cx, cy, radius - 5, radius + 3, 125);
        drawRadialTickAtDeg(dc, cx, cy, radius - 5, radius + 3, 305);
        drawRadialTickAtDeg(dc, cx, cy, radius - 5, radius + 3, 55);

        var penWidth = (cardStyle == 3) ? 3 : ((width >= 430) ? 5 : 4);
        var stepSweep = (110.0 * stepRatio).toNumber();
        var intSweep = (110.0 * intRatio).toNumber();

        // Left Arc (Steps vs 7D Target)
        dc.setPenWidth(penWidth);
        dc.setColor(trackCol, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, 235, 125);

        if (stepSweep >= 1) {
            var stepTipDeg = 235 - stepSweep;
            if (cardStyle != 3) {
                dc.setPenWidth(penWidth + 3);
                dc.setColor(theme[:halo] as Lang.Number, Graphics.COLOR_TRANSPARENT);
                dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, 235, stepTipDeg);
            }
            dc.setPenWidth(penWidth);
            dc.setColor(primaryCol, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, 235, stepTipDeg);
            if (cardStyle != 3) {
                dc.setPenWidth(2);
                dc.setColor(bgCol, Graphics.COLOR_TRANSPARENT);
                drawRadialTickAtDeg(dc, cx, cy, radius - 3, radius + 3, 208);
                drawRadialTickAtDeg(dc, cx, cy, radius - 3, radius + 3, 180);
                drawRadialTickAtDeg(dc, cx, cy, radius - 3, radius + 3, 153);
            }
            drawArcTipDot(dc, cx, cy, radius, stepTipDeg, primaryCol, tipDotCol);
        }

        // Right Arc (Weekly Intensity Minutes)
        dc.setPenWidth(penWidth);
        dc.setColor(trackCol, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, radius, Graphics.ARC_COUNTER_CLOCKWISE, 305, 55);

        if (intSweep >= 1) {
            var endDeg = 305 + intSweep;
            if (endDeg >= 360) {
                endDeg -= 360;
            }
            if (cardStyle != 3) {
                dc.setPenWidth(penWidth + 3);
                dc.setColor(theme[:halo] as Lang.Number, Graphics.COLOR_TRANSPARENT);
                dc.drawArc(cx, cy, radius, Graphics.ARC_COUNTER_CLOCKWISE, 305, endDeg);
            }
            dc.setPenWidth(penWidth);
            dc.setColor(secondaryCol, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, radius, Graphics.ARC_COUNTER_CLOCKWISE, 305, endDeg);
            if (cardStyle != 3) {
                dc.setPenWidth(2);
                dc.setColor(bgCol, Graphics.COLOR_TRANSPARENT);
                drawRadialTickAtDeg(dc, cx, cy, radius - 3, radius + 3, 332);
                drawRadialTickAtDeg(dc, cx, cy, radius - 3, radius + 3, 0);
                drawRadialTickAtDeg(dc, cx, cy, radius - 3, radius + 3, 27);
            }
            drawArcTipDot(dc, cx, cy, radius, endDeg, secondaryCol, tipDotCol);
        }

        dc.setPenWidth(1);
    }

    //! Draws a single radial line between innerR and outerR at angle deg.
    private function drawRadialTickAtDeg(
        dc as Graphics.Dc,
        cx as Lang.Number,
        cy as Lang.Number,
        innerR as Lang.Number,
        outerR as Lang.Number,
        deg as Lang.Number
    ) as Void {
        var rad = (deg.toFloat() * Math.PI) / 180.0;
        var cosVal = Math.cos(rad);
        var sinVal = Math.sin(rad);
        dc.drawLine(
            cx + (innerR * cosVal).toNumber(),
            cy - (innerR * sinVal).toNumber(),
            cx + (outerR * cosVal).toNumber(),
            cy - (outerR * sinVal).toNumber()
        );
    }

    //! Draws 60 radial minute/second chapter ticks + cardinal hashes + 12 o'clock crimson pip.
    private function drawChronographTicks(
        dc as Graphics.Dc,
        cx as Lang.Number,
        cy as Lang.Number,
        outerR as Lang.Number,
        theme as Lang.Dictionary
    ) as Void {
        var tickMajor = theme[:tickMajor] as Lang.Number;
        var tickMinor = theme[:tickMinor] as Lang.Number;
        for (var i = 0; i < 60; i++) {
            if (i == 15) {
                continue; // 12 o'clock gets crimson chronograph triangle pip
            }
            var isCardinal = (i == 0 || i == 30 || i == 45);
            var isMajor = (i % 5) == 0;
            var tickLen = isCardinal ? 9 : (isMajor ? 7 : 4);
            dc.setPenWidth(isCardinal ? 3 : (isMajor ? 2 : 1));
            dc.setColor(isMajor ? tickMajor : tickMinor, Graphics.COLOR_TRANSPARENT);
            drawRadialTickAtDeg(dc, cx, cy, outerR - tickLen, outerR, i * 6);
        }
        dc.setPenWidth(1);

        // 12-O'Clock Racing Crimson Inverted Triangle Pip
        dc.setColor(theme[:primary] as Lang.Number, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[cx - 5, 2], [cx + 5, 2], [cx, 10]]);
    }

    //! Draws a glowing dot marker at the active tip of a progress arc.
    private function drawArcTipDot(
        dc as Graphics.Dc,
        cx as Lang.Number,
        cy as Lang.Number,
        radius as Lang.Number,
        deg as Lang.Number,
        color as Lang.Number,
        ringCol as Lang.Number
    ) as Void {
        var rad = (deg.toFloat() * Math.PI) / 180.0;
        var dx = cx + (radius * Math.cos(rad)).toNumber();
        var dy = cy - (radius * Math.sin(rad)).toNumber();
        dc.setColor(ringCol, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(dx, dy, 4);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(dx, dy, 3);
    }

    //! Draws Weather & Forecast header honoring WeatherDetailMode (0=Full, 1=Clean, 2=Compact 1-Line).
    private function drawTopWeatherForecastBar(
        dc as Graphics.Dc,
        cx as Lang.Number,
        width as Lang.Number,
        height as Lang.Number,
        weatherDetailMode as Lang.Number,
        theme as Lang.Dictionary
    ) as Void {
        var today = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var mon = (today.month != null) ? (today.month as Lang.String).toUpper() : "";
        var day = (today.day != null) ? (today.day as Lang.Number).format("%d") : "";
        var line1 = mon + " " + day;
        var line2 = "";
        var condCode = null as Weather.Condition?;

        if (Toybox has :Weather) {
            var cond = Weather.getCurrentConditions();
            var dailyArr = (Weather has :getDailyForecast) ? Weather.getDailyForecast() : null;
            var todayFcst = (dailyArr != null && dailyArr.size() > 0) ? dailyArr[0] : null;

            if (cond != null) {
                condCode = cond.condition;
                if (cond.temperature != null) {
                    line1 = line1 + " • " + formatTempShort(cond.temperature as Lang.Number or Lang.Float);
                }

                if (weatherDetailMode != 2) {
                    var fcst = (todayFcst != null) ? (todayFcst as Weather.DailyForecast) : null;
                    var hiVal = (cond.highTemperature != null) ? cond.highTemperature
                        : ((fcst != null) ? fcst.highTemperature : null);
                    var loVal = (cond.lowTemperature != null) ? cond.lowTemperature
                        : ((fcst != null) ? fcst.lowTemperature : null);
                    var condLabel = getConditionLabel(condCode);

                    if (weatherDetailMode == 1) {
                        line2 = condLabel;
                        if (hiVal != null && loVal != null) {
                            line2 = line2 + " • H" + formatTempShort(hiVal as Lang.Number or Lang.Float)
                                + " L" + formatTempShort(loVal as Lang.Number or Lang.Float);
                        }
                    } else {
                        if (hiVal != null && loVal != null) {
                            line2 = "H" + formatTempShort(hiVal as Lang.Number or Lang.Float)
                                + " L" + formatTempShort(loVal as Lang.Number or Lang.Float);
                        } else {
                            line2 = condLabel;
                        }
                        var precip = (cond.precipitationChance != null) ? cond.precipitationChance
                            : ((fcst != null) ? fcst.precipitationChance : null);
                        if (precip != null) {
                            line2 = line2 + " • " + (precip as Lang.Number).format("%d") + "%";
                        }
                    }
                }
            }
        }

        var line1Fitted = fitTextToWidth(dc, line1, _fSmall, (width * 0.64).toNumber());
        var line1W = dc.getTextWidthInPixels(line1Fitted, _fSmall);
        var line1Y = (weatherDetailMode == 2) ? (height * 0.052).toNumber() : (height * 0.031).toNumber();
        var iconW = (condCode != null) ? 24 : 0;
        var start1X = cx - ((line1W + iconW) / 2);

        if (condCode != null) {
            drawWeatherIcon(dc, start1X + 10, line1Y + (dc.getFontHeight(_fSmall) / 2), condCode, theme);
        }

        dc.setColor(theme[:text] as Lang.Number, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            start1X + iconW,
            line1Y,
            _fSmall,
            line1Fitted,
            Graphics.TEXT_JUSTIFY_LEFT
        );

        if (!line2.equals("")) {
            dc.setColor(theme[:muted] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                cx,
                (height * 0.088).toNumber(),
                _fLabel,
                fitTextToWidth(dc, line2, _fLabel, (width * 0.72).toNumber()),
                Graphics.TEXT_JUSTIFY_CENTER
            );
        }
    }

    //! Draws crisp multi-color vector weather iconography using theme accents (zero blue).
    private function drawWeatherIcon(
        dc as Graphics.Dc,
        cx as Lang.Number,
        cy as Lang.Number,
        condCode as Weather.Condition?,
        theme as Lang.Dictionary
    ) as Void {
        if (condCode == null) {
            return;
        }
        var code = condCode as Weather.Condition;
        var sunCol = theme[:primary] as Lang.Number;
        var cloudCol = theme[:cloud] as Lang.Number;
        var rainCol = theme[:secondary] as Lang.Number;
        var mutedCol = theme[:muted] as Lang.Number;

        if (code == Weather.CONDITION_CLEAR || code == Weather.CONDITION_MOSTLY_CLEAR) {
            dc.setColor(sunCol, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx, cy, 5);
            dc.drawLine(cx - 9, cy, cx - 6, cy);
            dc.drawLine(cx + 6, cy, cx + 9, cy);
            dc.drawLine(cx, cy - 9, cx, cy - 6);
            dc.drawLine(cx, cy + 6, cx, cy + 9);
            return;
        }

        if (code == Weather.CONDITION_PARTLY_CLOUDY || code == Weather.CONDITION_PARTLY_CLEAR) {
            dc.setColor(sunCol, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx + 4, cy - 3, 5);
            dc.setColor(cloudCol, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx - 3, cy + 1, 5);
            dc.fillCircle(cx + 3, cy + 2, 4);
            dc.fillRectangle(cx - 6, cy + 1, 11, 5);
            return;
        }

        if (code == Weather.CONDITION_THUNDERSTORMS || code == Weather.CONDITION_SCATTERED_THUNDERSTORMS) {
            dc.setColor(mutedCol, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx - 3, cy - 2, 5);
            dc.fillCircle(cx + 3, cy - 1, 4);
            dc.fillRectangle(cx - 6, cy - 2, 12, 5);
            dc.setColor(sunCol, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[cx, cy + 1], [cx - 4, cy + 6], [cx, cy + 6], [cx - 1, cy + 10], [cx + 4, cy + 5], [cx, cy + 5]]);
            return;
        }

        var isRain = (code == Weather.CONDITION_RAIN || code == Weather.CONDITION_LIGHT_RAIN
            || code == Weather.CONDITION_HEAVY_RAIN || code == Weather.CONDITION_SHOWERS
            || code == Weather.CONDITION_SCATTERED_SHOWERS || code == Weather.CONDITION_CHANCE_OF_SHOWERS
            || code == Weather.CONDITION_LIGHT_SHOWERS || code == Weather.CONDITION_HEAVY_SHOWERS);

        dc.setColor(isRain ? mutedCol : cloudCol, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx - 3, cy - 1, 5);
        dc.fillCircle(cx + 3, cy, 4);
        dc.fillRectangle(cx - 6, cy - 1, 12, 5);

        if (isRain) {
            dc.setColor(rainCol, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(cx - 4, cy + 5, cx - 5, cy + 9);
            dc.drawLine(cx, cy + 5, cx - 1, cy + 9);
            dc.drawLine(cx + 4, cy + 5, cx + 3, cy + 9);
        }
    }

    //! Draws split Hours, muted Colon, Accent Minutes, AM/PM, and machined seconds pill badge.
    private function drawTimeBlock(
        dc as Graphics.Dc,
        cx as Lang.Number,
        width as Lang.Number,
        height as Lang.Number,
        clockTime as System.ClockTime,
        theme as Lang.Dictionary,
        showSeconds as Lang.Boolean
    ) as Lang.Number {
        var primaryCol = theme[:primary] as Lang.Number;
        var textCol = theme[:text] as Lang.Number;
        var dimCol = theme[:dim] as Lang.Number;
        var mutedCol = theme[:muted] as Lang.Number;

        var parts = formatClockParts(clockTime);
        var hourStr = parts[:hour] as Lang.String;
        var minStr = parts[:min] as Lang.String;
        var amPm = parts[:amPm] as Lang.String;

        var fullTime = hourStr + ":" + minStr;
        var maxMainWidth = showSeconds ? (width * 0.64).toNumber() : (width * 0.74).toNumber();
        var font = selectTimeFont(dc, fullTime, maxMainWidth);
        var fontHeight = dc.getFontHeight(font);

        var hourW = dc.getTextWidthInPixels(hourStr, font);
        var colonW = dc.getTextWidthInPixels(":", font);
        var minW = dc.getTextWidthInPixels(minStr, font);
        var totalMainWidth = hourW + colonW + minW;

        var secBadgeW = showSeconds ? 40 : 0;
        var rightColW = showSeconds ? (secBadgeW + 8) : (!amPm.equals("") ? 36 : 0);

        var startX = cx - ((totalMainWidth + rightColW) / 2);
        var timeY = (height * 0.112).toNumber();

        dc.setColor(textCol, Graphics.COLOR_TRANSPARENT);
        dc.drawText(startX, timeY, font, hourStr, Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(dimCol, Graphics.COLOR_TRANSPARENT);
        dc.drawText(startX + hourW, timeY, font, ":", Graphics.TEXT_JUSTIFY_LEFT);

        // Subtle 3D crimson/accent glow shadow behind minutes
        dc.setColor(theme[:shadow] as Lang.Number, Graphics.COLOR_TRANSPARENT);
        dc.drawText(startX + hourW + colonW + 2, timeY + 2, font, minStr, Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(primaryCol, Graphics.COLOR_TRANSPARENT);
        dc.drawText(startX + hourW + colonW, timeY, font, minStr, Graphics.TEXT_JUSTIFY_LEFT);

        var rightX = startX + totalMainWidth + 8;
        if (!amPm.equals("")) {
            dc.setColor(mutedCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(rightX, timeY + (fontHeight * 0.12).toNumber(), _fLabel, amPm, Graphics.TEXT_JUSTIFY_LEFT);
        }
        if (showSeconds) {
            var secStr = clockTime.sec.format("%02d");
            var badgeY = timeY + (fontHeight * 0.45).toNumber();
            var badgeH = 28;
            dc.setColor(theme[:cardBg] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(rightX, badgeY, secBadgeW, badgeH, 14);
            dc.setColor(theme[:cardBd] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.drawRoundedRectangle(rightX, badgeY, secBadgeW, badgeH, 14);
            dc.setColor(primaryCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                rightX + (secBadgeW / 2),
                badgeY + (badgeH / 2),
                _fSmall,
                secStr,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
        }

        return timeY + (fontHeight * 0.84).toNumber();
    }

    //! Draws a sleek World Clock capsule honoring CardStyle.
    private function drawWorldClockPill(
        dc as Graphics.Dc,
        cx as Lang.Number,
        width as Lang.Number,
        prevBottomY as Lang.Number,
        worldCityIndex as Lang.Number,
        cardStyle as Lang.Number,
        theme as Lang.Dictionary
    ) as Lang.Number {
        var cityParts = getWorldCityParts(worldCityIndex);
        var code = cityParts[:code] as Lang.String;
        var timeStr = cityParts[:timeStr] as Lang.String;

        var pillW = (width * 0.48).toNumber();
        var pillH = 30;
        var pillX = cx - (pillW / 2);
        var pillY = prevBottomY + 2;
        var badgeW = 68;

        if (cardStyle == 3) {
            // Option 3 HUD: borderless world clock + laser hairline & diamond node below
            dc.setColor(theme[:primary] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx - 10, pillY + 13, _fSmall, code, Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(theme[:dim] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx, pillY + 13, 2);
            dc.setColor(theme[:pillText] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx + 10, pillY + 13, _fSmall, timeStr, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

            var divY = pillY + 28;
            var halfLine = (width * 0.34).toNumber();
            dc.setColor(theme[:tickMinor] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(cx - halfLine, divY, cx - 8, divY);
            dc.drawLine(cx + 8, divY, cx + halfLine, divY);
            dc.setColor(theme[:primary] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[cx, divY - 3], [cx + 4, divY], [cx, divY + 3], [cx - 4, divY]]);
            return divY + 1;
        }

        dc.setColor(theme[:cardBg] as Lang.Number, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(pillX, pillY, pillW, pillH, 15);
        dc.setColor(theme[:cardBd] as Lang.Number, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(pillX, pillY, pillW, pillH, 15);

        dc.setColor(theme[:primary] as Lang.Number, Graphics.COLOR_TRANSPARENT);
        if (cardStyle == 1) {
            // Option 4: slanted racing parallelogram badge
            dc.fillPolygon([
                [pillX + 4, pillY + 4],
                [pillX + badgeW + 2, pillY + 4],
                [pillX + badgeW - 6, pillY + pillH - 4],
                [pillX + 4, pillY + pillH - 4]
            ]);
        } else {
            // Option 1 / Hybrid: full-round nested stadium badge
            dc.fillRoundedRectangle(pillX + 2, pillY + 2, badgeW, pillH - 4, 13);
        }

        dc.setColor(theme[:onPrimary] as Lang.Number, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            pillX + (badgeW / 2),
            pillY + (pillH / 2),
            _fSmall,
            code,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );

        var rightCenterX = pillX + badgeW + ((pillW - badgeW) / 2);
        dc.setColor(theme[:pillText] as Lang.Number, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            rightCenterX,
            pillY + (pillH / 2),
            _fSmall,
            timeStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );

        return pillY + pillH;
    }

    //! Draws card container with configurable corner radius and top specular highlight.
    private function drawBentoCard(
        dc as Graphics.Dc,
        x as Lang.Number,
        y as Lang.Number,
        w as Lang.Number,
        h as Lang.Number,
        radius as Lang.Number,
        cardStyle as Lang.Number,
        theme as Lang.Dictionary
    ) as Void {
        if (cardStyle == 3) {
            return;
        }
        dc.setColor(theme[:cardBg] as Lang.Number, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, w, h, radius);
        dc.setColor(theme[:cardBd] as Lang.Number, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(x, y, w, h, radius);
        var specPad = (radius > 14) ? radius : 10;
        if (w > (specPad * 2) + 8) {
            dc.setColor(theme[:specular] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(x + specPad, y + 1, x + w - specPad, y + 1);
        }
    }

    //! Draws Next Calendar Event Stadium/Racing Ribbon Card honoring CardStyle.
    private function drawNextEventCard(
        dc as Graphics.Dc,
        cx as Lang.Number,
        width as Lang.Number,
        prevBottomY as Lang.Number,
        cardStyle as Lang.Number,
        theme as Lang.Dictionary
    ) as Lang.Number {
        var primaryCol = theme[:primary] as Lang.Number;
        var cardW = (width * 0.81).toNumber();
        var cardH = 46;
        var cardX = cx - (cardW / 2);
        var cardY = prevBottomY + 5;

        var ev = resolveNextEvent();
        var evTime = ev[:time] as Lang.String;
        var evTitle = ev[:title] as Lang.String;
        var badgeText = !evTime.equals("") ? evTime : "--:--";
        var bodyStr = !evTime.equals("") ? evTitle : "No upcoming events";

        var tpW = 80;
        var textX = cardX + 94;
        var maxBodyW = cardW - 104;

        if (cardStyle == 3) {
            // Option 3 HUD: left glow bar + outlined crimson badge + hairline divider below
            dc.setColor(primaryCol, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(cardX + 4, cardY + 8, 4, cardH - 16, 2);
            dc.setColor(theme[:halo] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(cardX + 14, cardY + 7, 76, 32, 16);
            dc.setColor(primaryCol, Graphics.COLOR_TRANSPARENT);
            dc.drawRoundedRectangle(cardX + 14, cardY + 7, 76, 32, 16);
            dc.drawText(
                cardX + 52,
                cardY + 23,
                _fSmall,
                fitTextToWidth(dc, badgeText, _fSmall, 68),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
            dc.setColor(theme[:text] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                cardX + 98,
                cardY + 23,
                _fEvent,
                fitTextToWidth(dc, bodyStr, _fEvent, cardW - 104),
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
            );
            dc.setColor(theme[:tickMinor] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(cardX + 12, cardY + cardH + 2, cardX + cardW - 12, cardY + cardH + 2);
            return cardY + cardH;
        }

        var ribbonR = (cardStyle == 1) ? 16 : 23;
        drawBentoCard(dc, cardX, cardY, cardW, cardH, ribbonR, cardStyle, theme);

        dc.setColor(primaryCol, Graphics.COLOR_TRANSPARENT);
        if (cardStyle == 1) {
            // Option 4: slanted racing-cut crimson parallelogram
            dc.fillPolygon([
                [cardX + 5, cardY + 5],
                [cardX + 86, cardY + 5],
                [cardX + 76, cardY + cardH - 5],
                [cardX + 5, cardY + cardH - 5]
            ]);
            dc.setColor(theme[:onPrimary] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                cardX + 43,
                cardY + (cardH / 2),
                _fSmall,
                fitTextToWidth(dc, badgeText, _fSmall, 66),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
        } else {
            // Option 1 / Hybrid: full-round nested stadium time capsule
            dc.fillRoundedRectangle(cardX + 4, cardY + 4, tpW, cardH - 8, 19);
            dc.setColor(theme[:onPrimary] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                cardX + 4 + (tpW / 2),
                cardY + (cardH / 2),
                _fSmall,
                fitTextToWidth(dc, badgeText, _fSmall, tpW - 8),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
        }

        dc.setColor(theme[:text] as Lang.Number, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            textX,
            cardY + (cardH / 2),
            _fEvent,
            fitTextToWidth(dc, bodyStr, _fEvent, maxBodyW),
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
        );

        return cardY + cardH;
    }

    //! Draws Data Pod Grid: Opt 1 (Ring+Bay), Opt 4/Hybrid (Panoramic Bay + Ticked Rings), Opt 3 (Seamless HUD).
    private function drawDataPodGrid(
        dc as Graphics.Dc,
        cx as Lang.Number,
        width as Lang.Number,
        height as Lang.Number,
        prevBottomY as Lang.Number,
        actInfo as ActivityMonitor.Info,
        steps as Lang.Number,
        stepTarget as Lang.Number,
        targetMode as Lang.Number,
        stepHistory as Lang.Array<Lang.Number>,
        intMins as Lang.Number,
        intGoal as Lang.Number,
        bodyBattery as Lang.Number?,
        stress as Lang.Number?,
        readinessMode as Lang.Number,
        cardStyle as Lang.Number,
        showSparkline as Lang.Boolean,
        showMicroGauges as Lang.Boolean,
        bottomLeftMetric as Lang.Number,
        bottomRightMetric as Lang.Number,
        theme as Lang.Dictionary
    ) as Void {
        var primaryCol = theme[:primary] as Lang.Number;
        var secondaryCol = theme[:secondary] as Lang.Number;
        var mutedCol = theme[:muted] as Lang.Number;
        var dimCol = theme[:dim] as Lang.Number;
        var textCol = theme[:text] as Lang.Number;

        var gridW1 = (width * 0.81).toNumber();
        var leftX1 = cx - (gridW1 / 2);
        var row1Y = prevBottomY + 6;
        var row1H = (height * 0.172).toNumber();

        var trainVal = "--";
        var trainLabel = "READY";
        var readyScore = computeReadinessScore(bodyBattery, stress, _recoveryHours);
        if (readinessMode == 1) {
            trainLabel = "STAT";
            trainVal = formatTrainingStatusShort(_trainingStatusText);
        } else if (readyScore != null) {
            trainVal = (readyScore as Lang.Number).format("%d");
        }
        var recText = (_recoveryHours != null) ? ((_recoveryHours as Lang.Number).format("%d") + "h") : "--h";
        var readyRatio = (readyScore != null) ? clampRatio((readyScore as Lang.Number).toFloat() / 100.0) : 0.0;

        var targetSummary = formatNumberWithComma(stepTarget);
        var stepStr = formatNumberWithComma(steps);
        var stepRatio = clampRatio(steps.toFloat() / stepTarget.toFloat());

        // --- Row 1 ---
        if (cardStyle == 0) {
            // Option 1: Circular Ring Gauge for READY + REC Capsule + Steps Stadium Bay
            drawCircularRingGauge(
                dc, leftX1 + 39, row1Y + 37, 35, readyRatio,
                primaryCol, primaryCol, trainLabel, trainVal, false, false, showMicroGauges, cardStyle, theme
            );

            var recX = leftX1 + 82;
            var recW = 68;
            drawBentoCard(dc, recX, row1Y + 5, recW, row1H - 10, 18, cardStyle, theme);
            dc.setColor(mutedCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(recX + (recW / 2), row1Y + 19, _fLabel, "REC", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            var recFont1 = selectValueFont(dc, recText, recW - 10);
            dc.setColor(theme[:rec] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.drawText(recX + (recW / 2), row1Y + 46, recFont1, recText, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            var sx2 = leftX1 + 158;
            var sw2 = gridW1 - 158;
            drawBentoCard(dc, sx2, row1Y + 2, sw2, row1H - 4, 22, cardStyle, theme);
            dc.setColor(mutedCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(sx2 + 12, row1Y + 17, _fLabel, "STEPS", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(dimCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                sx2 + sw2 - 12,
                row1Y + 17,
                _fLabel,
                fitTextToWidth(dc, targetSummary, _fLabel, sw2 - 80),
                Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER
            );
            var sMaxW1 = showSparkline ? (sw2 - 74) : (sw2 - 24);
            var sFont1 = selectValueFont(dc, stepStr, sMaxW1);
            dc.setColor(textCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(sx2 + 12, row1Y + 47, sFont1, fitTextToWidth(dc, stepStr, sFont1, sMaxW1), Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            if (showSparkline) {
                drawSevenDaySparkline(dc, sx2 + sw2 - 36, row1Y + row1H - 13, stepHistory, stepTarget, theme);
            }
        } else if (cardStyle == 1 || cardStyle == 2) {
            // Option 4 & Hybrid 1+4: Unified Panoramic Cockpit Bay
            drawBentoCard(dc, leftX1, row1Y, gridW1, row1H, 22, cardStyle, theme);
            var c1X = leftX1 + 42;
            var c2X = leftX1 + 110;
            dc.setColor(theme[:tickMinor] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(leftX1 + 78, row1Y + 14, leftX1 + 78, row1Y + row1H - 14);
            dc.setColor(theme[:cardBd] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(leftX1 + 142, row1Y + 10, leftX1 + 142, row1Y + row1H - 10);

            dc.setColor(mutedCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(c1X, row1Y + 17, _fLabel, trainLabel, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(c2X, row1Y + 17, _fLabel, "REC", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            var rf4 = selectValueFont(dc, trainVal, 64);
            dc.setColor(primaryCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(c1X, row1Y + 47, rf4, fitTextToWidth(dc, trainVal, rf4, 64), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            var recF4 = selectValueFont(dc, recText, 56);
            dc.setColor(theme[:rec] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.drawText(c2X, row1Y + 47, recF4, recText, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            var sxP = leftX1 + 154;
            var swP = gridW1 - 166;
            dc.setColor(mutedCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(sxP, row1Y + 17, _fLabel, "STEPS", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(dimCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                sxP + swP,
                row1Y + 17,
                _fLabel,
                fitTextToWidth(dc, targetSummary, _fLabel, swP - 74),
                Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER
            );
            var sMaxWP = showSparkline ? (swP - 54) : swP;
            var sFontP = selectValueFont(dc, stepStr, sMaxWP);
            dc.setColor(textCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(sxP, row1Y + 47, sFontP, fitTextToWidth(dc, stepStr, sFontP, sMaxWP), Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            if (showSparkline) {
                drawSevenDaySparkline(dc, sxP + swP - 25, row1Y + row1H - 12, stepHistory, stepTarget, theme);
            }
        } else {
            // Option 3 HUD: Borderless floating READY | REC | STEPS + laser hairlines
            var w1H = (gridW1 * 44) / 100;
            var hw1H = w1H / 2;
            dc.setColor(mutedCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(leftX1 + (hw1H / 2), row1Y + 14, _fLabel, trainLabel, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(leftX1 + hw1H + (hw1H / 2), row1Y + 14, _fLabel, "REC", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            var rf3 = selectValueFont(dc, trainVal, hw1H - 6);
            dc.setColor(primaryCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(leftX1 + (hw1H / 2), row1Y + 42, rf3, fitTextToWidth(dc, trainVal, rf3, hw1H - 6), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            var recF3 = selectValueFont(dc, recText, hw1H - 6);
            dc.setColor(theme[:rec] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.drawText(leftX1 + hw1H + (hw1H / 2), row1Y + 42, recF3, recText, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            if (showMicroGauges) {
                drawHorizontalProgressBar(dc, leftX1 + 12, row1Y + row1H - 10, w1H - 22, 4, readyRatio, primaryCol, theme);
            }

            dc.setColor(theme[:cardBd] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(leftX1 + w1H + 4, row1Y + 8, leftX1 + w1H + 4, row1Y + row1H - 8);

            var sx3 = leftX1 + w1H + 14;
            var sw3 = gridW1 - w1H - 14;
            dc.setColor(mutedCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(sx3, row1Y + 14, _fLabel, "STEPS", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(dimCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(sx3 + sw3 - 4, row1Y + 14, _fLabel, fitTextToWidth(dc, targetSummary, _fLabel, sw3 - 74), Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
            var sFont3 = selectValueFont(dc, stepStr, showSparkline ? (sw3 - 56) : sw3);
            dc.setColor(textCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(sx3, row1Y + 42, sFont3, stepStr, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            if (showSparkline) {
                drawSevenDaySparkline(dc, sx3 + sw3 - 26, row1Y + row1H - 13, stepHistory, stepTarget, theme);
            }
            if (showMicroGauges) {
                drawHorizontalProgressBar(dc, sx3, row1Y + row1H - 10, sw3 - 4, 4, stepRatio, primaryCol, theme);
            }
            dc.setColor(theme[:tickMinor] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(leftX1 + 22, row1Y + row1H + 2, leftX1 + gridW1 - 22, row1Y + row1H + 2);
        }

        // --- Row 2 Values (Bottom-Left, Heart Rate, Bottom-Right) ---
        var blLabel = "INTENS";
        var blValue = intMins.format("%d") + "m";
        var blRatio = clampRatio(intMins.toFloat() / intGoal.toFloat());
        if (bottomLeftMetric == 1) {
            blLabel = "KCAL";
            var cals = (actInfo.calories != null) ? (actInfo.calories as Lang.Number) : 0;
            blValue = formatNumberWithComma(cals);
            blRatio = clampRatio(cals.toFloat() / 2500.0);
        } else if (bottomLeftMetric == 2) {
            blLabel = "DIST";
            var distCm = (actInfo.distance != null) ? (actInfo.distance as Lang.Number) : 0;
            var distKm = distCm.toFloat() / 100000.0;
            blValue = (System.getDeviceSettings().distanceUnits == System.UNIT_STATUTE)
                ? ((distCm.toFloat() / 160934.4).format("%.1f") + "mi")
                : (distKm.format("%.1f") + "km");
            blRatio = clampRatio(distKm / 8.0);
        }

        var hr = getHeartRate();
        var hrStr = (hr != null) ? (hr as Lang.Number).format("%d") : "--";
        var hrRatio = (hr != null) ? clampRatio(((hr as Lang.Number) - 40).toFloat() / 140.0) : 0.0;

        var brLabel = "BODY";
        var brValue = (bodyBattery != null) ? ((bodyBattery as Lang.Number).format("%d") + "%") : "--";
        var brRatio = (bodyBattery != null) ? clampRatio((bodyBattery as Lang.Number).toFloat() / 100.0) : 0.0;
        var brCol = theme[:bodyBat] as Lang.Number;
        if (bottomRightMetric == 1) {
            brLabel = "STRESS";
            brValue = (stress != null) ? (stress as Lang.Number).format("%d") : "--";
            brRatio = (stress != null) ? clampRatio((stress as Lang.Number).toFloat() / 100.0) : 0.0;
            brCol = (stress != null && (stress as Lang.Number) >= 60) ? secondaryCol : (theme[:bodyBat] as Lang.Number);
        } else if (bottomRightMetric == 2) {
            brLabel = "KCAL";
            var brCals = (actInfo.calories != null) ? (actInfo.calories as Lang.Number) : 0;
            brValue = formatNumberWithComma(brCals);
            brRatio = clampRatio(brCals.toFloat() / 2500.0);
        } else if (bottomRightMetric == 3) {
            brLabel = "FLOORS";
            var floors = (actInfo has :floorsClimbed && actInfo.floorsClimbed != null)
                ? (actInfo.floorsClimbed as Lang.Number) : 0;
            brValue = floors.format("%d");
            brRatio = clampRatio(floors.toFloat() / 10.0);
        }

        if (cardStyle == 3) {
            // Option 3 HUD: Floating Row 2 with smile-arc meters underneath
            var row2Y = row1Y + row1H + 9;
            var gw2 = (width * 0.72).toNumber();
            var lx2 = cx - (gw2 / 2);
            var pw3 = gw2 / 3;
            var colsX = [lx2 + (pw3 / 2), cx, lx2 + gw2 - (pw3 / 2)];
            dc.setColor(theme[:tickMinor] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(lx2 + pw3, row2Y + 8, lx2 + pw3, row2Y + 56);
            dc.drawLine(lx2 + (2 * pw3), row2Y + 8, lx2 + (2 * pw3), row2Y + 56);

            dc.setColor(mutedCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(colsX[0], row2Y + 10, _fLabel, blLabel, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(colsX[1], row2Y + 10, _fLabel, "HEART", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(colsX[2], row2Y + 10, _fLabel, brLabel, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            var blF3 = selectValueFont(dc, blValue, pw3 - 10);
            dc.setColor(secondaryCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(colsX[0], row2Y + 35, blF3, fitTextToWidth(dc, blValue, blF3, pw3 - 10), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            var hrF3 = selectValueFont(dc, hrStr, pw3 - 22);
            var hrW3 = dc.getTextWidthInPixels(hrStr, hrF3);
            var hrSX3 = colsX[1] - ((hrW3 + 18) / 2);
            drawHeartIcon(dc, hrSX3 + 6, row2Y + 34, theme[:crimson] as Lang.Number);
            dc.setColor(textCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(hrSX3 + 17, row2Y + 35, hrF3, hrStr, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

            var brF3 = selectValueFont(dc, brValue, pw3 - 10);
            dc.setColor(brCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(colsX[2], row2Y + 35, brF3, fitTextToWidth(dc, brValue, brF3, pw3 - 10), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            if (showMicroGauges) {
                var smileR = 38;
                var smileCy = row2Y + 32;
                var smileCols = [secondaryCol, theme[:crimson] as Lang.Number, brCol];
                var smileRats = [blRatio, hrRatio, brRatio];
                dc.setPenWidth(4);
                for (var s = 0; s < 3; s++) {
                    dc.setColor(theme[:track] as Lang.Number, Graphics.COLOR_TRANSPARENT);
                    dc.drawArc(colsX[s], smileCy, smileR, Graphics.ARC_COUNTER_CLOCKWISE, 220, 320);
                    var swp = (100.0 * smileRats[s]).toNumber();
                    if (swp >= 1) {
                        dc.setColor(smileCols[s], Graphics.COLOR_TRANSPARENT);
                        dc.drawArc(colsX[s], smileCy, smileR, Graphics.ARC_COUNTER_CLOCKWISE, 220, 220 + swp);
                    }
                }
                dc.setPenWidth(1);
            }
            return;
        }

        // Options 1, 4, and Hybrid 1+4: Three 270-degree Circular Ring Dials along lower curve
        var r2Cy = row1Y + row1H + 49;
        var r2R = (width * 0.093).toNumber();
        var ringOffset = (width * 0.236).toNumber();
        var isTicked = (cardStyle == 1);

        drawCircularRingGauge(
            dc, cx - ringOffset, r2Cy, r2R, blRatio,
            secondaryCol, secondaryCol, blLabel, blValue, false, isTicked, showMicroGauges, cardStyle, theme
        );
        drawCircularRingGauge(
            dc, cx, r2Cy, r2R, hrRatio,
            theme[:crimson] as Lang.Number, textCol, "HEART", hrStr, true, isTicked, showMicroGauges, cardStyle, theme
        );
        drawCircularRingGauge(
            dc, cx + ringOffset, r2Cy, r2R, brRatio,
            brCol, brCol, brLabel, brValue, false, isTicked, showMicroGauges, cardStyle, theme
        );
    }

    //! Draws a 270-degree circular gauge dial with bottom-gap label and glowing tip dot.
    private function drawCircularRingGauge(
        dc as Graphics.Dc,
        rcx as Lang.Number,
        rcy as Lang.Number,
        r as Lang.Number,
        ratio as Lang.Float,
        arcColor as Lang.Number,
        valColor as Lang.Number,
        labelText as Lang.String,
        valText as Lang.String,
        isHeart as Lang.Boolean,
        tickStyle as Lang.Boolean,
        showGauge as Lang.Boolean,
        cardStyle as Lang.Number,
        theme as Lang.Dictionary
    ) as Void {
        if (showGauge) {
            dc.setPenWidth(6);
            dc.setColor(theme[:track] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(rcx, rcy, r, Graphics.ARC_CLOCKWISE, 225, 315);

            var sweep = (270.0 * clampRatio(ratio)).toNumber();
            if (sweep >= 2) {
                var endDeg = 225 - sweep;
                if (endDeg < 0) {
                    endDeg += 360;
                }
                dc.setColor(arcColor, Graphics.COLOR_TRANSPARENT);
                dc.drawArc(rcx, rcy, r, Graphics.ARC_CLOCKWISE, 225, endDeg);

                if (tickStyle) {
                    var bgCol = (cardStyle == 3 && (theme[:bg] as Lang.Number) != 0xE5E0D8) ? 0x000000 : (theme[:bg] as Lang.Number);
                    dc.setPenWidth(1);
                    dc.setColor(bgCol, Graphics.COLOR_TRANSPARENT);
                    for (var t = 1; t <= 8; t++) {
                        var tDeg = 225 - (t * 30);
                        if (tDeg < 0) {
                            tDeg += 360;
                        }
                        drawRadialTickAtDeg(dc, rcx, rcy, r - 4, r + 4, tDeg);
                    }
                }
                drawArcTipDot(dc, rcx, rcy, r, endDeg, arcColor, theme[:tipDot] as Lang.Number);
            }
            dc.setPenWidth(1);
        }

        if (isHeart) {
            var hFont = selectValueFont(dc, valText, (r * 2) - 22);
            var hW = dc.getTextWidthInPixels(valText, hFont);
            var hSx = rcx - ((hW + 17) / 2);
            drawHeartIcon(dc, hSx + 6, rcy - 3, theme[:crimson] as Lang.Number);
            dc.setColor(valColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(hSx + 17, rcy - 2, hFont, valText, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        } else {
            var maxValW = (r * 2) - 18;
            var vFont = selectValueFont(dc, valText, maxValW);
            dc.setColor(valColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                rcx,
                rcy - 3,
                vFont,
                fitTextToWidth(dc, valText, vFont, maxValW),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
        }

        dc.setColor(theme[:muted] as Lang.Number, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            rcx,
            rcy + r - 3,
            _fLabel,
            labelText,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }

    private function drawHorizontalProgressBar(
        dc as Graphics.Dc,
        x as Lang.Number,
        y as Lang.Number,
        w as Lang.Number,
        h as Lang.Number,
        ratio as Lang.Float,
        color as Lang.Number,
        theme as Lang.Dictionary
    ) as Void {
        dc.setColor(theme[:track] as Lang.Number, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, w, h, 2);
        var fillW = (w.toFloat() * ratio).toNumber();
        if (fillW < 4 && ratio > 0.0) {
            fillW = 4;
        }
        if (fillW > 0) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x, y, fillW, h, 2);
        }
    }

    private function drawSegmentedBar(
        dc as Graphics.Dc,
        x as Lang.Number,
        y as Lang.Number,
        w as Lang.Number,
        h as Lang.Number,
        activeCount as Lang.Number,
        colors as Lang.Array<Lang.Number>,
        theme as Lang.Dictionary
    ) as Void {
        var count = colors.size();
        var segGap = 2;
        var segW = (w - ((count - 1) * segGap)) / count;
        var trackCol = theme[:track] as Lang.Number;
        for (var i = 0; i < count; i++) {
            var sx = x + (i * (segW + segGap));
            dc.setColor((i < activeCount) ? colors[i] : trackCol, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(sx, y, segW, h, 1);
        }
    }

    private function drawHeartIcon(
        dc as Graphics.Dc,
        cx as Lang.Number,
        cy as Lang.Number,
        color as Lang.Number
    ) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx - 3, cy - 2, 4);
        dc.fillCircle(cx + 3, cy - 2, 4);
        dc.fillPolygon([[cx - 7, cy - 1], [cx + 7, cy - 1], [cx, cy + 7]]);
    }

    //! Draws taller 7-bar sparkline with horizontal target threshold line inside Steps hero card.
    private function drawSevenDaySparkline(
        dc as Graphics.Dc,
        centerX as Lang.Number,
        baseY as Lang.Number,
        stepHistory as Lang.Array<Lang.Number>,
        stepTarget as Lang.Number,
        theme as Lang.Dictionary
    ) as Void {
        var count = stepHistory.size();
        if (count == 0) {
            return;
        }

        var maxVal = stepTarget;
        for (var i = 0; i < count; i++) {
            if (stepHistory[i] > maxVal) {
                maxVal = stepHistory[i];
            }
        }
        if (maxVal <= 0) {
            maxVal = 10000;
        }

        var barW = 5;
        var barGap = 2;
        var maxH = 28;
        var totalW = (7 * barW) + (6 * barGap);
        var startX = centerX - (totalW / 2);
        var startSlot = 7 - count;
        var hitCol = theme[:primary] as Lang.Number;
        var missCol = theme[:dim] as Lang.Number;

        for (var d = 0; d < count; d++) {
            var val = stepHistory[d];
            var barH = ((val.toFloat() / maxVal.toFloat()) * maxH).toNumber();
            if (barH < 3 && val > 0) {
                barH = 3;
            }
            var bx = startX + ((startSlot + d) * (barW + barGap));
            dc.setColor((val >= stepTarget) ? hitCol : missCol, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(bx, baseY - barH, barW, barH);
        }

        var threshY = baseY - ((stepTarget.toFloat() / maxVal.toFloat()) * maxH).toNumber();
        dc.setColor(theme[:muted] as Lang.Number, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(startX - 2, threshY, startX + totalW + 2, threshY);
    }

    //! Draws segmented battery gauge honoring BatteryFormat (0=Pct+Days, 1=Days only, 2=Pct only).
    private function drawBottomBatteryBar(
        dc as Graphics.Dc,
        cx as Lang.Number,
        height as Lang.Number,
        width as Lang.Number,
        batteryFormat as Lang.Number,
        theme as Lang.Dictionary
    ) as Void {
        var stats = System.getSystemStats();
        var pct = stats.battery.toNumber();
        if (pct < 0) {
            pct = 0;
        } else if (pct > 100) {
            pct = 100;
        }

        var fillColor = theme[:primary] as Lang.Number;
        if (pct <= 10) {
            fillColor = theme[:crimson] as Lang.Number;
        } else if (pct <= 20) {
            fillColor = theme[:secondary] as Lang.Number;
        }

        var daysStr = "";
        if ((stats has :batteryInDays) && stats.batteryInDays != null) {
            var daysNum = (stats.batteryInDays as Lang.Number or Lang.Float).toNumber();
            if (daysNum >= 0) {
                daysStr = daysNum.format("%d") + "d";
            }
        }

        var labelStr = pct.format("%d") + "%";
        if (batteryFormat == 0 && !daysStr.equals("")) {
            labelStr = labelStr + " • " + daysStr;
        } else if (batteryFormat == 1 && !daysStr.equals("")) {
            labelStr = daysStr;
        }

        var battW = 30;
        var battH = 15;
        var battY = (height * 0.882).toNumber();
        var textW = dc.getTextWidthInPixels(labelStr, _fSmall);
        var totalW = battW + 10 + textW;
        var startX = cx - (totalW / 2);
        var mutedCol = theme[:muted] as Lang.Number;
        var trackCol = theme[:track] as Lang.Number;

        dc.setColor(mutedCol, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(startX, battY, battW, battH, 3);
        dc.fillRectangle(startX + battW, battY + 3, 2, battH - 6);

        var activeBlocks = (pct + 24) / 25;
        var blockW = 5;
        var blockGap = 1;
        for (var b = 0; b < 4; b++) {
            var bx = startX + 2 + (b * (blockW + blockGap));
            dc.setColor((b < activeBlocks) ? fillColor : trackCol, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(bx, battY + 2, blockW, battH - 4);
        }

        dc.setColor(mutedCol, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            startX + battW + 8,
            battY + (battH / 2),
            _fSmall,
            labelStr,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }

    //! Parses Garmin Recovery Time complication value (minutes or seconds across firmware) into hours.
    private function parseRecoveryHours(val as Lang.Object?) as Lang.Number? {
        if (val == null) {
            return null;
        }
        if ((val instanceof Lang.Number) || (val instanceof Lang.Float)) {
            var num = (val as Lang.Number or Lang.Float).toNumber();
            if (num <= 0) {
                return 0;
            }
            if (num > 6000) {
                return (num + 1800) / 3600;
            }
            return (num + 30) / 60;
        }
        return null;
    }

    private function formatTrainingStatusShort(status as Lang.String?) as Lang.String {
        if (status == null || status.equals("")) {
            return "--";
        }
        var upper = (status as Lang.String).toUpper();
        if (TRAINING_STATUS_MAP.hasKey(upper)) {
            return TRAINING_STATUS_MAP.get(upper) as Lang.String;
        }
        if (upper.length() > 5) {
            return upper.substring(0, 5) as Lang.String;
        }
        return upper;
    }

    private function getConditionLabel(condCode as Weather.Condition?) as Lang.String {
        if (condCode != null && CONDITION_LABELS.hasKey(condCode as Weather.Condition)) {
            return CONDITION_LABELS.get(condCode as Weather.Condition) as Lang.String;
        }
        return "FCST";
    }

    private function formatTempShort(tempCVal as Lang.Number or Lang.Float) as Lang.String {
        return formatTempBare(tempCVal) + "°";
    }

    private function formatTempBare(tempCVal as Lang.Number or Lang.Float) as Lang.String {
        var tempC = tempCVal.toFloat();
        if (System.getDeviceSettings().temperatureUnits == System.UNIT_STATUTE) {
            var tempF = ((tempC * 9.0) / 5.0) + 32.0;
            return tempF.format("%d");
        }
        return tempC.format("%d");
    }

    //! Resolves next event start time + title from background JSON storage, with native complication fallback.
    private function resolveNextEvent() as Lang.Dictionary {
        var storedTime = getStorageString("NextEventTime");
        var storedTitle = getStorageString("NextEventTitle");

        if (!storedTime.equals("")) {
            return {
                :time => storedTime,
                :title => !storedTitle.equals("") ? storedTitle : getStringProperty("FallbackEventTitle", "Upcoming Event")
            };
        }

        if (_nextCalendarEvent != null && !(_nextCalendarEvent as Lang.String).equals("")) {
            return {
                :time => _nextCalendarEvent as Lang.String,
                :title => getStringProperty("FallbackEventTitle", "Upcoming Event")
            };
        }

        return {
            :time => "",
            :title => ""
        };
    }

    //! Truncates text with "..." so it never overflows maxWidth pixels.
    private function fitTextToWidth(
        dc as Graphics.Dc,
        text as Lang.String,
        font as Graphics.FontType,
        maxWidth as Lang.Number
    ) as Lang.String {
        if (dc.getTextWidthInPixels(text, font) <= maxWidth) {
            return text;
        }
        var len = text.length();
        while (len > 1) {
            len -= 1;
            var candidate = text.substring(0, len) + "...";
            if (dc.getTextWidthInPixels(candidate, font) <= maxWidth) {
                return candidate;
            }
        }
        return "...";
    }

    //! Resolves city code and UTC minute offset from the WORLD_CITIES lookup table.
    private function getWorldCityData(cityIndex as Lang.Number) as Lang.Dictionary {
        var idx = cityIndex;
        if (idx < 0 || idx >= WORLD_CITIES.size()) {
            idx = 0;
        }
        var entry = WORLD_CITIES[idx] as Lang.Array;
        return {
            :code => entry[0] as Lang.String,
            :offsetMins => entry[1] as Lang.Number
        };
    }

    //! Computes the selected city's code and time parts via UTC offset (supports 45m offsets like Kathmandu).
    private function getWorldCityParts(cityIndex as Lang.Number) as Lang.Dictionary {
        var city = getWorldCityData(cityIndex);
        var code = city[:code] as Lang.String;
        var offsetMins = city[:offsetMins] as Lang.Number;
        var offsetSecs = offsetMins * 60;

        var now = Time.now();
        var localToday = Gregorian.info(now, Time.FORMAT_SHORT);

        var shiftedMoment = now;
        if (offsetSecs > 0) {
            shiftedMoment = now.add(new Time.Duration(offsetSecs));
        } else if (offsetSecs < 0) {
            shiftedMoment = now.subtract(new Time.Duration(-offsetSecs));
        }

        var cityInfo = Gregorian.utcInfo(shiftedMoment, Time.FORMAT_SHORT);
        var localKey = (localToday.year * 10000) + (localToday.month * 100) + localToday.day;
        var cityKey = (cityInfo.year * 10000) + (cityInfo.month * 100) + cityInfo.day;

        var dayTag = "";
        if (cityKey > localKey) {
            dayTag = " +1";
        } else if (cityKey < localKey) {
            dayTag = " -1";
        }

        return {
            :code => code,
            :timeStr => cityInfo.hour.format("%02d") + ":" + cityInfo.min.format("%02d") + dayTag
        };
    }

    private function getFormattedWorldTime(cityIndex as Lang.Number) as Lang.String {
        var parts = getWorldCityParts(cityIndex);
        return (parts[:code] as Lang.String) + " " + (parts[:timeStr] as Lang.String);
    }

    //! Returns current heart rate, falling back to the latest sensor history sample.
    private function getHeartRate() as Lang.Number? {
        var actInfo = Activity.getActivityInfo();
        if (actInfo != null && actInfo.currentHeartRate != null) {
            return actInfo.currentHeartRate;
        }
        if (ActivityMonitor has :getHeartRateHistory) {
            var hrIter = ActivityMonitor.getHeartRateHistory(1, true);
            var sample = hrIter.next();
            if (sample != null && sample.heartRate != null
                && sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE
                && sample.heartRate > 0) {
                return sample.heartRate;
            }
        }
        return null;
    }

    //! Reads newest Body Battery sample (0-100) from Toybox.SensorHistory.
    private function getLatestBodyBattery() as Lang.Number? {
        if ((Toybox has :SensorHistory) && (SensorHistory has :getBodyBatteryHistory)) {
            var iter = SensorHistory.getBodyBatteryHistory({
                :period => 1,
                :order => SensorHistory.ORDER_NEWEST_FIRST
            });
            if (iter != null) {
                var sample = iter.next();
                if (sample != null && sample.data != null) {
                    return (sample.data as Lang.Number or Lang.Float).toNumber();
                }
            }
        }
        return null;
    }

    //! Reads newest Stress level sample (0-100) from Toybox.SensorHistory.
    private function getLatestStress() as Lang.Number? {
        if ((Toybox has :SensorHistory) && (SensorHistory has :getStressHistory)) {
            var iter = SensorHistory.getStressHistory({
                :period => 1,
                :order => SensorHistory.ORDER_NEWEST_FIRST
            });
            if (iter != null) {
                var sample = iter.next();
                if (sample != null && sample.data != null) {
                    return (sample.data as Lang.Number or Lang.Float).toNumber();
                }
            }
        }
        return null;
    }

    private function clamp100(val as Lang.Number) as Lang.Number {
        if (val > 100) {
            return 100;
        } else if (val < 0) {
            return 0;
        }
        return val;
    }

    private function clampRatio(ratio as Lang.Float) as Lang.Float {
        if (ratio > 1.0) {
            return 1.0;
        } else if (ratio < 0.0) {
            return 0.0;
        }
        return ratio;
    }

    //! Formats hours, minutes, and optional AM/PM honoring the watch's 12h/24h setting.
    private function formatClockParts(clockTime as System.ClockTime) as Lang.Dictionary {
        var is24Hour = System.getDeviceSettings().is24Hour;
        var hour = clockTime.hour;
        var amPm = "";

        if (!is24Hour) {
            amPm = (hour >= 12) ? "PM" : "AM";
            hour = hour % 12;
            if (hour == 0) {
                hour = 12;
            }
        }

        var hourStr = is24Hour ? hour.format("%02d") : hour.format("%d");
        return {
            :hour => hourStr,
            :min => clockTime.min.format("%02d"),
            :amPm => amPm
        };
    }

    //! Selects the largest value font (_fValue -> _fMidValue -> _fEvent -> _fSmall) that fits within maxWidth.
    private function selectValueFont(
        dc as Graphics.Dc,
        text as Lang.String,
        maxWidth as Lang.Number
    ) as Graphics.FontType {
        if (dc.getTextWidthInPixels(text, _fValue) <= maxWidth) {
            return _fValue;
        }
        if (dc.getTextWidthInPixels(text, _fMidValue) <= maxWidth) {
            return _fMidValue;
        }
        if (dc.getTextWidthInPixels(text, _fEvent) <= maxWidth) {
            return _fEvent;
        }
        return _fSmall;
    }

    //! Selects the TrueType vector clock font if it fits within maxWidth pixels.
    private function selectTimeFont(
        dc as Graphics.Dc,
        sampleText as Lang.String,
        maxWidth as Lang.Number
    ) as Graphics.FontType {
        if (dc.getTextWidthInPixels(sampleText, _fTime) <= maxWidth) {
            return _fTime;
        }
        if (dc.getTextWidthInPixels(sampleText, Graphics.FONT_NUMBER_MEDIUM) <= maxWidth) {
            return Graphics.FONT_NUMBER_MEDIUM;
        }
        return Graphics.FONT_NUMBER_MILD;
    }

    //! Formats non-negative integers with a thousands comma (e.g., 8420 -> "8,420").
    private function formatNumberWithComma(value as Lang.Number) as Lang.String {
        if (value >= 1000) {
            var thousands = value / 1000;
            var remainder = value % 1000;
            return thousands.format("%d") + "," + remainder.format("%03d");
        }
        return value.format("%d");
    }

    private function getStorageString(key as Lang.String) as Lang.String {
        try {
            var val = Storage.getValue(key);
            if (val instanceof Lang.String) {
                return val as Lang.String;
            }
        } catch (ex) {
        }
        return "";
    }

    private function getStringProperty(key as Lang.String, fallback as Lang.String) as Lang.String {
        try {
            var val = Properties.getValue(key);
            if (val instanceof Lang.String && !(val as Lang.String).equals("")) {
                return val as Lang.String;
            }
        } catch (ex) {
        }
        return fallback;
    }

    private function getNumberProperty(key as Lang.String, fallback as Lang.Number) as Lang.Number {
        try {
            var val = Properties.getValue(key);
            if (val instanceof Lang.Number) {
                return val as Lang.Number;
            }
        } catch (ex) {
        }
        return fallback;
    }

    private function getBooleanProperty(key as Lang.String, fallback as Lang.Boolean) as Lang.Boolean {
        try {
            var val = Properties.getValue(key);
            if (val instanceof Lang.Boolean) {
                return val as Lang.Boolean;
            }
        } catch (ex) {
        }
        return fallback;
    }
}
