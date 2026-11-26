using Toybox.Activity;
using Toybox.ActivityMonitor;
using Toybox.Application.Properties;
using Toybox.Application.Storage;
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
    private var _fontWeightLoaded as Lang.Number = -1;
    private var _isSleeping as Lang.Boolean = false;
    private var _burnInOffsetX as Lang.Number = 0;
    private var _burnInOffsetY as Lang.Number = 0;

    private var _fLabel as Graphics.FontType = Graphics.FONT_XTINY;
    private var _fSmall as Graphics.FontType = Graphics.FONT_XTINY;
    private var _fEvent as Graphics.FontType = Graphics.FONT_XTINY;
    private var _fMidValue as Graphics.FontType = Graphics.FONT_SMALL;
    private var _fValue as Graphics.FontType = Graphics.FONT_TINY;
    private var _fTime as Graphics.FontType = Graphics.FONT_NUMBER_MEDIUM;

    private var _comp as FR570ComplicationsHelper = new FR570ComplicationsHelper();

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _screenWidth = dc.getWidth();
        _screenHeight = dc.getHeight();
        initVectorFonts(_screenWidth, getNumberProperty("FontWeight", 0));
    }

    //! Loads scaled TrueType vector fonts on CIQ 5+ or crisp native MIP bitmap fonts on <= 260px devices.
    private function initVectorFonts(width as Lang.Number, fontWeight as Lang.Number) as Void {
        if (_fontWidthLoaded == width && _fontWeightLoaded == fontWeight) {
            return;
        }
        _fontWidthLoaded = width;
        _fontWeightLoaded = fontWeight;
        if (width <= 260 || !(Graphics has :getVectorFont)) {
            _fLabel = Graphics.FONT_XTINY;
            _fSmall = Graphics.FONT_XTINY;
            _fEvent = Graphics.FONT_TINY;
            _fMidValue = Graphics.FONT_TINY;
            _fValue = Graphics.FONT_SMALL;
            _fTime = Graphics.FONT_NUMBER_HOT;
            return;
        }
        var scale = width.toFloat() / 454.0;
        var boldFaces = ["RobotoCondensedBold", "RobotoRegular"] as Lang.Array<Lang.String>;
        var regFaces = ["RobotoRegular", "RobotoCondensedRegular"] as Lang.Array<Lang.String>;
        var labelFaces = (fontWeight == 1) ? boldFaces : regFaces;
        var numFaces = (fontWeight == 0) ? regFaces : boldFaces;

        _fLabel = loadVectorFontFace(labelFaces, (22.0 * scale).toNumber(), Graphics.FONT_XTINY);
        _fSmall = loadVectorFontFace(labelFaces, (26.0 * scale).toNumber(), Graphics.FONT_XTINY);
        _fEvent = loadVectorFontFace(labelFaces, (32.0 * scale).toNumber(), Graphics.FONT_TINY);
        _fMidValue = loadVectorFontFace(numFaces, (36.0 * scale).toNumber(), Graphics.FONT_SMALL);
        _fValue = loadVectorFontFace(numFaces, (44.0 * scale).toNumber(), Graphics.FONT_TINY);
        _fTime = loadVectorFontFace(numFaces, (98.0 * scale).toNumber(), Graphics.FONT_NUMBER_MEDIUM);
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
        _comp.init();
    }

    function onHide() as Void {
        _comp.cleanup();
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

    function createDelegate() as WatchUi.InputDelegate? {
        return _comp.createDelegate(self);
    }

    //! Maps the 6 user-facing layout indices (0..5) to internal renderer styles (2..7).
    private function resolveCardStyle() as Lang.Number {
        var raw = getNumberProperty("CardStyle", 0);
        if (raw >= 0 && raw <= 5) {
            return raw + 2;
        }
        return 2;
    }

    //! Launches the matching native Garmin glance when the user touch-and-holds a zone.
    function launchShortcutAt(x as Lang.Number, y as Lang.Number) as Lang.Boolean {
        return _comp.launchShortcutAt(
            x, y, _screenWidth, _screenHeight,
            resolveCardStyle(),
            getNumberProperty("BottomLeftMetric", 0),
            getNumberProperty("BottomRightMetric", 0)
        );
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }

        var width = dc.getWidth();
        var height = dc.getHeight();
        _screenWidth = width;
        _screenHeight = height;
        initVectorFonts(width, getNumberProperty("FontWeight", 0));
        var cx = width / 2;
        var cy = height / 2;
        var isMip = (width <= 260);

        var clockTime = System.getClockTime();
        var worldCityIndex = getNumberProperty("WorldCity", 0);
        var stepTargetMode = getNumberProperty("StepTargetMode", 0);
        var readinessMode = getNumberProperty("ReadinessMode", 0);
        var themeIndex = getNumberProperty("AccentColor", 0);
        var cardStyle = resolveCardStyle();
        var weatherDetailMode = getNumberProperty("WeatherDetailMode", 0);
        var bottomLeftMetric = getNumberProperty("BottomLeftMetric", 0);
        var bottomRightMetric = getNumberProperty("BottomRightMetric", 0);
        var batteryFormat = getNumberProperty("BatteryFormat", 0);
        var theme = getThemePalette(themeIndex, isMip);
        var showSeconds = getBooleanProperty("ShowSeconds", true);
        var showChronoTicks = getBooleanProperty("ShowChronoTicks", true);
        var showRings = getBooleanProperty("ShowStepsArc", true);
        var showSparkline = getBooleanProperty("ShowSparkline", true);
        var showMicroGauges = getBooleanProperty("ShowMicroGauges", true);

        var bgColor = (cardStyle == 3) ? 0x000000 : (theme[:bg] as Lang.Number);
        dc.setColor(bgColor, bgColor);
        dc.clear();

        if (_isSleeping) {
            var devSettings = System.getDeviceSettings();
            var needsBurnIn = (devSettings has :requiresBurnInProtection) && devSettings.requiresBurnInProtection;
            if (needsBurnIn) {
                updateBurnInShift(clockTime.min);
                drawAlwaysOnDisplay(dc, cx, cy, width, clockTime, worldCityIndex);
                return;
            }
            showSeconds = false;
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

        var frame = {
            :worldCity => worldCityIndex,
            :readinessMode => readinessMode,
            :blMetric => bottomLeftMetric,
            :brMetric => bottomRightMetric,
            :battFmt => batteryFormat,
            :showSec => showSeconds,
            :showRings => showRings,
            :showSpark => showSparkline,
            :showMicro => showMicroGauges,
            :wDetail => weatherDetailMode,
            :cardStyle => cardStyle,
            :steps => steps,
            :stepTarget => stepTarget,
            :stepHistory => stepHistory,
            :intMins => intMins,
            :intGoal => intGoal,
            :bb => bodyBattery,
            :stress => stress
        };

        if (cardStyle >= 4) {
            var m = buildMetricsBundle(actInfo, frame, theme);
            if (cardStyle == 4) {
                drawLayoutVerticalSplit(dc, width, height, clockTime, m, frame, theme);
            } else if (cardStyle == 5) {
                drawLayoutF1Telemetry(dc, width, height, clockTime, m, frame, theme);
            } else {
                drawLayoutTwoToneGmt(dc, width, height, clockTime, m, frame, theme);
            }
            return;
        }

        if (showChronoTicks && cardStyle != 1) {
            drawChronographTicks(dc, cx, cy, (width / 2) - 2, theme);
        }
        if (showRings) {
            var sRat = clampRatio(steps.toFloat() / stepTarget.toFloat());
            var iRat = clampRatio(intMins.toFloat() / intGoal.toFloat());
            drawDualProgressArcs(dc, cx, cy, width, sRat, iRat, cardStyle, theme);
        }

        drawTopWeatherForecastBar(dc, cx, width, height, weatherDetailMode, theme);

        var timeBottomY = drawTimeBlock(dc, cx, width, height, clockTime, theme, showSeconds);
        var pillBottomY = drawWorldClockPill(dc, cx, width, timeBottomY, worldCityIndex, cardStyle, theme);
        var cardBottomY = drawNextEventCard(dc, cx, width, pillBottomY, cardStyle, theme);

        drawDataPodGrid(dc, width, height, cardBottomY, actInfo, frame, theme);
        drawBottomBatteryBar(dc, cx, height, width, batteryFormat, theme);
    }

    //! Returns palette colors for themes 0..3 (64-color MIP palette when isMip=true, 16-bit AMOLED otherwise).
    private function getThemePalette(themeIndex as Lang.Number, isMip as Lang.Boolean) as Lang.Dictionary {
        if (isMip) {
            if (themeIndex == 1) {
                return {
                    :bg => 0x000000, :cardBg => 0x000000, :cardBd => 0x555555, :specular => 0xAAAAAA,
                    :badgeBg => 0x555555, :primary => 0xFFAA00, :secondary => 0xFF5500, :bodyBat => 0x00AA00,
                    :crimson => 0xFF0000, :rec => 0xFFAA00, :text => 0xFFFFFF, :muted => 0xFFFFFF,
                    :dim => 0xAAAAAA, :tickMajor => 0xAAAAAA, :tickMinor => 0x555555, :track => 0x555555,
                    :cloud => 0xFFFFFF, :tipDot => 0xFFFFFF, :pillText => 0xFFFF00, :onPrimary => 0x000000,
                    :halo => 0x555500, :shadow => 0x555500,
                    :zoneCols => [0x555555, 0x00AA00, 0xFFAA00, 0xFF5500, 0xFF0000],
                    :readyCols => [0xFF0000, 0xFFAA00, 0x00AA00, 0xFF5500]
                };
            } else if (themeIndex == 2) {
                return {
                    :bg => 0x000000, :cardBg => 0x000000, :cardBd => 0x0055AA, :specular => 0x0055FF,
                    :badgeBg => 0x0055AA, :primary => 0x0055FF, :secondary => 0x00AAFF, :bodyBat => 0xFFFFFF,
                    :crimson => 0xFF0000, :rec => 0x00AAFF, :text => 0xFFFFFF, :muted => 0xFFFFFF,
                    :dim => 0xAAAAAA, :tickMajor => 0xAAAAAA, :tickMinor => 0x0055AA, :track => 0x555555,
                    :cloud => 0xFFFFFF, :tipDot => 0xFFFFFF, :pillText => 0x55AAFF, :onPrimary => 0xFFFFFF,
                    :halo => 0x0000AA, :shadow => 0x000055,
                    :zoneCols => [0xAAAAAA, 0xFFFFFF, 0x00AAFF, 0x0055FF, 0xFF0000],
                    :readyCols => [0xFF0000, 0x00AAFF, 0x0055FF, 0x00AAFF]
                };
            } else if (themeIndex == 3) {
                return {
                    :bg => 0x0000AA, :cardBg => 0x000055, :cardBd => 0x0055FF, :specular => 0x00AAFF,
                    :badgeBg => 0x000055, :primary => 0xFF0000, :secondary => 0xFFFF00, :bodyBat => 0xFFFFFF,
                    :crimson => 0xFF0000, :rec => 0xFFFF00, :text => 0xFFFFFF, :muted => 0xFFFFFF,
                    :dim => 0xAAAAAA, :tickMajor => 0xFFFFFF, :tickMinor => 0x0055FF, :track => 0x0055AA,
                    :cloud => 0xFFFFFF, :tipDot => 0xFFFFFF, :pillText => 0xFFFFFF, :onPrimary => 0xFFFFFF,
                    :halo => 0x550000, :shadow => 0x000055,
                    :zoneCols => [0xAAAAAA, 0xFFFFFF, 0xFFFF00, 0xFF5500, 0xFF0000],
                    :readyCols => [0xFF0000, 0xFFFF00, 0xFFFFFF, 0xFFFF00]
                };
            }
            return {
                :bg => 0x000000, :cardBg => 0x000000, :cardBd => 0x555555, :specular => 0xAAAAAA,
                :badgeBg => 0x555555, :primary => 0xFF0000, :secondary => 0xFF5500, :bodyBat => 0xFFFFFF,
                :crimson => 0xFF0000, :rec => 0xFF5500, :text => 0xFFFFFF, :muted => 0xFFFFFF,
                :dim => 0xAAAAAA, :tickMajor => 0xAAAAAA, :tickMinor => 0x555555, :track => 0x555555,
                :cloud => 0xFFFFFF, :tipDot => 0xFFFFFF, :pillText => 0xFFFFFF, :onPrimary => 0xFFFFFF,
                :halo => 0x550000, :shadow => 0x550000,
                :zoneCols => [0x555555, 0xFFFFFF, 0xFFAA00, 0xFF5500, 0xFF0000],
                :readyCols => [0xFF0000, 0xFF0000, 0xFFFFFF, 0xFF5500]
            };
        }
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
                :bg => 0x09090B, :cardBg => 0x101622, :cardBd => 0x1E3A6E, :specular => 0x2563EB,
                :badgeBg => 0x162440, :primary => 0x0077FF, :secondary => 0x38BDF8, :bodyBat => 0xE2E8F0,
                :crimson => 0xEF4444, :rec => 0x38BDF8, :text => 0xFFFFFF, :muted => 0xE2E8F0,
                :dim => 0x94A3B8, :tickMajor => 0x64748B, :tickMinor => 0x1E3A6E, :track => 0x162440,
                :cloud => 0xE2E8F0, :tipDot => 0xFFFFFF, :pillText => 0x93C5FD, :onPrimary => 0xFFFFFF,
                :halo => 0x0A2E66, :shadow => 0x061B3D,
                :zoneCols => [0x64748B, 0xE2E8F0, 0x38BDF8, 0x0077FF, 0xEF4444],
                :readyCols => [0xEF4444, 0x38BDF8, 0x0077FF, 0x38BDF8]
            };
        } else if (themeIndex == 3) {
            return {
                :bg => 0x0F3882, :cardBg => 0x081E4A, :cardBd => 0x2563EB, :specular => 0x3B82F6,
                :badgeBg => 0x0B2760, :primary => 0xEF4444, :secondary => 0xFACC15, :bodyBat => 0xFFFFFF,
                :crimson => 0xEF4444, :rec => 0xFACC15, :text => 0xFFFFFF, :muted => 0xE2E8F0,
                :dim => 0xCBD5E1, :tickMajor => 0xCBD5E1, :tickMinor => 0x2563EB, :track => 0x0C2A62,
                :cloud => 0xE2E8F0, :tipDot => 0xFFFFFF, :pillText => 0xFFFFFF, :onPrimary => 0xFFFFFF,
                :halo => 0x6E181D, :shadow => 0x061433,
                :zoneCols => [0x94A3B8, 0xFFFFFF, 0xFACC15, 0xF97316, 0xEF4444],
                :readyCols => [0xEF4444, 0xFACC15, 0xFFFFFF, 0xFACC15]
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

        var rib = resolveRibbonContent();
        var rBadge = rib[:badge] as Lang.String;
        var rBody = rib[:body] as Lang.String;
        var evSummary = rBadge.equals("--:--") ? rBody : (rBadge + " • " + rBody);
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
        stepRatioIn as Lang.Float,
        intRatioIn as Lang.Float,
        cardStyle as Lang.Number,
        theme as Lang.Dictionary
    ) as Void {
        var primaryCol = theme[:primary] as Lang.Number;
        var secondaryCol = theme[:secondary] as Lang.Number;
        var trackCol = theme[:track] as Lang.Number;
        var guideCol = theme[:tickMinor] as Lang.Number;
        var tipDotCol = theme[:tipDot] as Lang.Number;
        var bgCol = (cardStyle == 3 && (theme[:bg] as Lang.Number) != 0xE5E0D8) ? 0x000000 : (theme[:bg] as Lang.Number);

        var s = width.toFloat() / 454.0;
        var isMip = (width <= 260);
        var radius = (width / 2) - (11 * s).toNumber();
        var stepRatio = clampRatio(stepRatioIn);
        var intRatio = clampRatio(intRatioIn);

        if (cardStyle == 1) {
            // Option 4: 12 Discrete Curved Tachometer Segments per side
            dc.setPenWidth(isMip ? 3 : 6);
            var segs = 12;
            var litLeft = ((segs.toFloat() * stepRatio) + 0.5).toNumber();
            var litRight = ((segs.toFloat() * intRatio) + 0.5).toNumber();
            for (var sIdx = 0; sIdx < segs; sIdx++) {
                var aStartL = 235 - ((sIdx * 110) / segs);
                var aEndL = 235 - (((sIdx + 1) * 110) / segs) + 2;
                dc.setColor((sIdx < litLeft) ? primaryCol : trackCol, Graphics.COLOR_TRANSPARENT);
                dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, aStartL, aEndL);

                var aStartR = 305 + ((sIdx * 110) / segs);
                var aEndR = 305 + (((sIdx + 1) * 110) / segs) - 2;
                if (aStartR >= 360) {
                    aStartR -= 360;
                }
                if (aEndR >= 360) {
                    aEndR -= 360;
                }
                dc.setColor((sIdx < litRight) ? secondaryCol : trackCol, Graphics.COLOR_TRANSPARENT);
                dc.drawArc(cx, cy, radius, Graphics.ARC_COUNTER_CLOCKWISE, aStartR, aEndR);
            }
            dc.setPenWidth(1);
            return;
        }

        // Inner hairline parallel guide arcs & radial end-cap brackets
        var gOff = isMip ? 3 : 5;
        var tOut = isMip ? 2 : 3;
        dc.setPenWidth(1);
        dc.setColor(guideCol, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, radius - gOff, Graphics.ARC_CLOCKWISE, 235, 125);
        dc.drawArc(cx, cy, radius - gOff, Graphics.ARC_COUNTER_CLOCKWISE, 305, 55);
        drawRadialTickAtDeg(dc, cx, cy, radius - gOff, radius + tOut, 235);
        drawRadialTickAtDeg(dc, cx, cy, radius - gOff, radius + tOut, 125);
        drawRadialTickAtDeg(dc, cx, cy, radius - gOff, radius + tOut, 305);
        drawRadialTickAtDeg(dc, cx, cy, radius - gOff, radius + tOut, 55);

        var penWidth = isMip ? ((cardStyle == 3) ? 2 : 3) : ((cardStyle == 3) ? 3 : ((width >= 430) ? 5 : 4));
        var stepSweep = (110.0 * stepRatio).toNumber();
        var intSweep = (110.0 * intRatio).toNumber();
        var notchSpan = isMip ? 2 : 3;

        // Left Arc (Steps vs 7D Target)
        dc.setPenWidth(penWidth);
        dc.setColor(trackCol, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, 235, 125);

        if (stepSweep >= 1) {
            var stepTipDeg = 235 - stepSweep;
            if (cardStyle != 3 && !isMip) {
                dc.setPenWidth(penWidth + 3);
                dc.setColor(theme[:halo] as Lang.Number, Graphics.COLOR_TRANSPARENT);
                dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, 235, stepTipDeg);
            }
            dc.setPenWidth(penWidth);
            dc.setColor(primaryCol, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, 235, stepTipDeg);
            if (cardStyle != 3) {
                dc.setPenWidth(isMip ? 1 : 2);
                dc.setColor(bgCol, Graphics.COLOR_TRANSPARENT);
                drawRadialTickAtDeg(dc, cx, cy, radius - notchSpan, radius + notchSpan, 208);
                drawRadialTickAtDeg(dc, cx, cy, radius - notchSpan, radius + notchSpan, 180);
                drawRadialTickAtDeg(dc, cx, cy, radius - notchSpan, radius + notchSpan, 153);
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
            if (cardStyle != 3 && !isMip) {
                dc.setPenWidth(penWidth + 3);
                dc.setColor(theme[:halo] as Lang.Number, Graphics.COLOR_TRANSPARENT);
                dc.drawArc(cx, cy, radius, Graphics.ARC_COUNTER_CLOCKWISE, 305, endDeg);
            }
            dc.setPenWidth(penWidth);
            dc.setColor(secondaryCol, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, radius, Graphics.ARC_COUNTER_CLOCKWISE, 305, endDeg);
            if (cardStyle != 3) {
                dc.setPenWidth(isMip ? 1 : 2);
                dc.setColor(bgCol, Graphics.COLOR_TRANSPARENT);
                drawRadialTickAtDeg(dc, cx, cy, radius - notchSpan, radius + notchSpan, 332);
                drawRadialTickAtDeg(dc, cx, cy, radius - notchSpan, radius + notchSpan, 0);
                drawRadialTickAtDeg(dc, cx, cy, radius - notchSpan, radius + notchSpan, 27);
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
        var isMip = (_screenWidth <= 260);
        for (var i = 0; i < 60; i++) {
            if (i == 15) {
                continue; // 12 o'clock gets crimson chronograph triangle pip
            }
            var isCardinal = (i == 0 || i == 30 || i == 45);
            var isMajor = (i % 5) == 0;
            var tickLen = isMip ? (isCardinal ? 5 : (isMajor ? 4 : 2)) : (isCardinal ? 9 : (isMajor ? 7 : 4));
            dc.setPenWidth(isMip ? (isCardinal ? 2 : 1) : (isCardinal ? 3 : (isMajor ? 2 : 1)));
            dc.setColor(isMajor ? tickMajor : tickMinor, Graphics.COLOR_TRANSPARENT);
            drawRadialTickAtDeg(dc, cx, cy, outerR - tickLen, outerR, i * 6);
        }
        dc.setPenWidth(1);

        // 12-O'Clock Racing Crimson Inverted Triangle Pip
        dc.setColor(theme[:primary] as Lang.Number, Graphics.COLOR_TRANSPARENT);
        var triW = isMip ? 3 : 5;
        var triTop = isMip ? 1 : 2;
        var triBot = isMip ? 5 : 10;
        dc.fillPolygon([[cx - triW, triTop], [cx + triW, triTop], [cx, triBot]]);
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
        var isMip = (_screenWidth <= 260);
        var rad = (deg.toFloat() * Math.PI) / 180.0;
        var dx = cx + (radius * Math.cos(rad)).toNumber();
        var dy = cy - (radius * Math.sin(rad)).toNumber();
        dc.setColor(ringCol, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(dx, dy, isMip ? 3 : 4);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(dx, dy, isMip ? 2 : 3);
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

        var isMip = (width <= 260);
        var line1Fitted = fitTextToWidth(dc, line1, _fSmall, (width * 0.64).toNumber());
        var line1W = dc.getTextWidthInPixels(line1Fitted, _fSmall);
        var line1Y = (weatherDetailMode == 2) ? (height * 0.052).toNumber() : (height * 0.031).toNumber();
        var iconW = (condCode != null) ? (isMip ? 14 : 24) : 0;
        var start1X = cx - ((line1W + iconW) / 2);

        if (condCode != null) {
            drawWeatherIcon(dc, start1X + (isMip ? 6 : 10), line1Y + (dc.getFontHeight(_fSmall) / 2), condCode, theme);
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

    //! Draws crisp multi-color vector weather iconography using theme accents.
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
        var isMip = (_screenWidth <= 260);
        var code = condCode as Weather.Condition;
        var sunCol = theme[:primary] as Lang.Number;
        var cloudCol = theme[:cloud] as Lang.Number;
        var rainCol = theme[:secondary] as Lang.Number;
        var mutedCol = theme[:muted] as Lang.Number;

        if (code == Weather.CONDITION_CLEAR || code == Weather.CONDITION_MOSTLY_CLEAR) {
            dc.setColor(sunCol, Graphics.COLOR_TRANSPARENT);
            if (isMip) {
                dc.fillCircle(cx, cy, 3);
                dc.drawLine(cx - 5, cy, cx - 4, cy);
                dc.drawLine(cx + 4, cy, cx + 5, cy);
                dc.drawLine(cx, cy - 5, cx, cy - 4);
                dc.drawLine(cx, cy + 4, cx, cy + 5);
            } else {
                dc.fillCircle(cx, cy, 5);
                dc.drawLine(cx - 9, cy, cx - 6, cy);
                dc.drawLine(cx + 6, cy, cx + 9, cy);
                dc.drawLine(cx, cy - 9, cx, cy - 6);
                dc.drawLine(cx, cy + 6, cx, cy + 9);
            }
            return;
        }

        if (code == Weather.CONDITION_PARTLY_CLOUDY || code == Weather.CONDITION_PARTLY_CLEAR) {
            dc.setColor(sunCol, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx + (isMip ? 2 : 4), cy - (isMip ? 2 : 3), isMip ? 3 : 5);
            dc.setColor(cloudCol, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx - (isMip ? 2 : 3), cy + 1, isMip ? 3 : 5);
            dc.fillCircle(cx + (isMip ? 2 : 3), cy + (isMip ? 1 : 2), isMip ? 2 : 4);
            dc.fillRectangle(cx - (isMip ? 3 : 6), cy + 1, isMip ? 6 : 11, isMip ? 3 : 5);
            return;
        }

        if (code == Weather.CONDITION_THUNDERSTORMS || code == Weather.CONDITION_SCATTERED_THUNDERSTORMS) {
            dc.setColor(mutedCol, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx - (isMip ? 2 : 3), cy - (isMip ? 1 : 2), isMip ? 3 : 5);
            dc.fillCircle(cx + (isMip ? 2 : 3), cy - 1, isMip ? 2 : 4);
            dc.fillRectangle(cx - (isMip ? 3 : 6), cy - (isMip ? 1 : 2), isMip ? 7 : 12, isMip ? 3 : 5);
            dc.setColor(sunCol, Graphics.COLOR_TRANSPARENT);
            if (isMip) {
                dc.drawLine(cx + 1, cy + 2, cx - 2, cy + 6);
            } else {
                dc.fillPolygon([[cx, cy + 1], [cx - 4, cy + 6], [cx, cy + 6], [cx - 1, cy + 10], [cx + 4, cy + 5], [cx, cy + 5]]);
            }
            return;
        }

        var isRain = (code == Weather.CONDITION_RAIN || code == Weather.CONDITION_LIGHT_RAIN
            || code == Weather.CONDITION_HEAVY_RAIN || code == Weather.CONDITION_SHOWERS
            || code == Weather.CONDITION_SCATTERED_SHOWERS || code == Weather.CONDITION_CHANCE_OF_SHOWERS
            || code == Weather.CONDITION_LIGHT_SHOWERS || code == Weather.CONDITION_HEAVY_SHOWERS);

        dc.setColor(isRain ? mutedCol : cloudCol, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx - (isMip ? 2 : 3), cy - 1, isMip ? 3 : 5);
        dc.fillCircle(cx + (isMip ? 2 : 3), cy, isMip ? 2 : 4);
        dc.fillRectangle(cx - (isMip ? 3 : 6), cy - 1, isMip ? 7 : 12, isMip ? 3 : 5);

        if (isRain) {
            dc.setColor(rainCol, Graphics.COLOR_TRANSPARENT);
            if (isMip) {
                dc.drawLine(cx - 2, cy + 3, cx - 3, cy + 5);
                dc.drawLine(cx + 1, cy + 3, cx, cy + 5);
            } else {
                dc.drawLine(cx - 4, cy + 5, cx - 5, cy + 9);
                dc.drawLine(cx, cy + 5, cx - 1, cy + 9);
                dc.drawLine(cx + 4, cy + 5, cx + 3, cy + 9);
            }
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
        var isMip = (width <= 260);
        var s = width.toFloat() / 454.0;

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

        var secBadgeW = showSeconds ? (isMip ? 24 : 40) : 0;
        var colGap = isMip ? 4 : 8;
        var rightColW = showSeconds ? (secBadgeW + colGap) : (!amPm.equals("") ? (36 * s).toNumber() : 0);

        var startX = cx - ((totalMainWidth + rightColW) / 2);
        var timeY = (height * 0.112).toNumber();

        dc.setColor(textCol, Graphics.COLOR_TRANSPARENT);
        dc.drawText(startX, timeY, font, hourStr, Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(dimCol, Graphics.COLOR_TRANSPARENT);
        dc.drawText(startX + hourW, timeY, font, ":", Graphics.TEXT_JUSTIFY_LEFT);

        // Subtle 3D crimson/accent glow shadow behind minutes
        var shadowOff = isMip ? 1 : 2;
        dc.setColor(theme[:shadow] as Lang.Number, Graphics.COLOR_TRANSPARENT);
        dc.drawText(startX + hourW + colonW + shadowOff, timeY + shadowOff, font, minStr, Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(primaryCol, Graphics.COLOR_TRANSPARENT);
        dc.drawText(startX + hourW + colonW, timeY, font, minStr, Graphics.TEXT_JUSTIFY_LEFT);

        var rightX = startX + totalMainWidth + colGap;
        if (!amPm.equals("")) {
            dc.setColor(mutedCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(rightX, timeY + (fontHeight * 0.12).toNumber(), _fLabel, amPm, Graphics.TEXT_JUSTIFY_LEFT);
        }
        if (showSeconds) {
            var secStr = clockTime.sec.format("%02d");
            var badgeY = timeY + (fontHeight * 0.45).toNumber();
            var badgeH = isMip ? 16 : 28;
            var badgeR = badgeH / 2;
            dc.setColor(theme[:cardBg] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(rightX, badgeY, secBadgeW, badgeH, badgeR);
            dc.setColor(theme[:cardBd] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.drawRoundedRectangle(rightX, badgeY, secBadgeW, badgeH, badgeR);
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
        var isMip = (width <= 260);
        var s = width.toFloat() / 454.0;

        var pillW = (width * 0.48).toNumber();
        var pillH = isMip ? 18 : 30;
        var pillX = cx - (pillW / 2);
        var pillY = prevBottomY + (isMip ? 1 : 2);
        var badgeW = isMip ? 36 : 68;

        if (cardStyle == 3) {
            // Option 3 HUD: borderless world clock + laser hairline & diamond node below
            var txtMidY = pillY + (pillH / 2) - 1;
            var divGap = isMip ? 6 : 10;
            dc.setColor(theme[:primary] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx - divGap, txtMidY, _fSmall, code, Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(theme[:dim] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx, txtMidY, isMip ? 1 : 2);
            dc.setColor(theme[:pillText] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx + divGap, txtMidY, _fSmall, timeStr, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

            var divY = pillY + pillH - (isMip ? 1 : 2);
            var halfLine = (width * 0.34).toNumber();
            var nodeSpan = isMip ? 5 : 8;
            var dR = isMip ? 2 : 3;
            var dW = isMip ? 3 : 4;
            dc.setColor(theme[:tickMinor] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(cx - halfLine, divY, cx - nodeSpan, divY);
            dc.drawLine(cx + nodeSpan, divY, cx + halfLine, divY);
            dc.setColor(theme[:primary] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[cx, divY - dR], [cx + dW, divY], [cx, divY + dR], [cx - dW, divY]]);
            return divY + 1;
        }

        dc.setColor(theme[:cardBg] as Lang.Number, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(pillX, pillY, pillW, pillH, pillH / 2);
        dc.setColor(theme[:cardBd] as Lang.Number, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(pillX, pillY, pillW, pillH, pillH / 2);

        dc.setColor(theme[:primary] as Lang.Number, Graphics.COLOR_TRANSPARENT);
        if (cardStyle == 1) {
            // Option 4: slanted racing parallelogram badge
            var pad = isMip ? 2 : 4;
            var slant = (6 * s).toNumber();
            dc.fillPolygon([
                [pillX + pad, pillY + pad],
                [pillX + badgeW + (pad / 2), pillY + pad],
                [pillX + badgeW - slant, pillY + pillH - pad],
                [pillX + pad, pillY + pillH - pad]
            ]);
        } else {
            // Option 1 / Hybrid: full-round nested stadium badge
            var pad = isMip ? 1 : 2;
            dc.fillRoundedRectangle(pillX + pad, pillY + pad, badgeW, pillH - (pad * 2), (pillH - (pad * 2)) / 2);
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
        var maxR = (w < h ? w : h) / 2;
        var cr = (radius > maxR) ? maxR : radius;
        if (cr < 0) {
            cr = 0;
        }
        dc.setColor(theme[:cardBg] as Lang.Number, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, w, h, cr);
        dc.setColor(theme[:cardBd] as Lang.Number, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(x, y, w, h, cr);
        var specPad = (cr > 8) ? cr : 6;
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
        var isMip = (width <= 260);
        var s = width.toFloat() / 454.0;
        var cardW = (width * 0.81).toNumber();
        var cardH = isMip ? 24 : 46;
        var cardX = cx - (cardW / 2);
        var cardY = prevBottomY + (isMip ? 3 : 5);

        var rib = resolveRibbonContent();
        var badgeText = rib[:badge] as Lang.String;
        var bodyStr = rib[:body] as Lang.String;

        var tpW = isMip ? 42 : 80;
        var textGap = isMip ? 8 : 14;
        var textX = cardX + tpW + textGap;
        var maxBodyW = cardW - tpW - textGap - (isMip ? 6 : 10);

        if (cardStyle == 3) {
            // Option 3 HUD: left glow bar + outlined crimson badge + hairline divider below
            var glowX = cardX + (isMip ? 2 : 4);
            var glowY = cardY + (isMip ? 4 : 8);
            var glowH = cardH - (isMip ? 8 : 16);
            var bX = cardX + (isMip ? 8 : 14);
            var bY = cardY + (isMip ? 3 : 7);
            var bW = isMip ? 40 : 76;
            var bH = cardH - (isMip ? 6 : 14);
            dc.setColor(primaryCol, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(glowX, glowY, isMip ? 3 : 4, glowH, 1);
            dc.setColor(theme[:halo] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(bX, bY, bW, bH, bH / 2);
            dc.setColor(primaryCol, Graphics.COLOR_TRANSPARENT);
            dc.drawRoundedRectangle(bX, bY, bW, bH, bH / 2);
            dc.drawText(
                bX + (bW / 2),
                cardY + (cardH / 2),
                _fSmall,
                fitTextToWidth(dc, badgeText, _fSmall, bW - (isMip ? 4 : 8)),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
            dc.setColor(theme[:text] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                bX + bW + (isMip ? 5 : 8),
                cardY + (cardH / 2),
                _fEvent,
                fitTextToWidth(dc, bodyStr, _fEvent, cardW - bW - (isMip ? 16 : 28)),
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
            );
            dc.setColor(theme[:tickMinor] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(cardX + (isMip ? 6 : 12), cardY + cardH + (isMip ? 1 : 2), cardX + cardW - (isMip ? 6 : 12), cardY + cardH + (isMip ? 1 : 2));
            return cardY + cardH;
        }

        var ribbonR = (cardStyle == 1) ? (isMip ? 8 : 16) : (cardH / 2);
        drawBentoCard(dc, cardX, cardY, cardW, cardH, ribbonR, cardStyle, theme);

        dc.setColor(primaryCol, Graphics.COLOR_TRANSPARENT);
        if (cardStyle == 1) {
            // Option 4: slanted racing-cut crimson parallelogram
            var pad = isMip ? 3 : 5;
            var pTopW = (86 * s).toNumber();
            var pBotW = (76 * s).toNumber();
            dc.fillPolygon([
                [cardX + pad, cardY + pad],
                [cardX + pTopW, cardY + pad],
                [cardX + pBotW, cardY + cardH - pad],
                [cardX + pad, cardY + cardH - pad]
            ]);
            dc.setColor(theme[:onPrimary] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                cardX + ((pTopW + pBotW) / 4),
                cardY + (cardH / 2),
                _fSmall,
                fitTextToWidth(dc, badgeText, _fSmall, pBotW - pad - 4),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
        } else {
            // Option 1 / Hybrid: full-round nested stadium time capsule
            var pad = isMip ? 2 : 4;
            dc.fillRoundedRectangle(cardX + pad, cardY + pad, tpW, cardH - (pad * 2), (cardH - (pad * 2)) / 2);
            dc.setColor(theme[:onPrimary] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                cardX + pad + (tpW / 2),
                cardY + (cardH / 2),
                _fSmall,
                fitTextToWidth(dc, badgeText, _fSmall, tpW - (pad * 2)),
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
        width as Lang.Number,
        height as Lang.Number,
        prevBottomY as Lang.Number,
        actInfo as ActivityMonitor.Info,
        frame as Lang.Dictionary,
        theme as Lang.Dictionary
    ) as Void {
        var cx = width / 2;
        var steps = frame[:steps] as Lang.Number;
        var stepTarget = frame[:stepTarget] as Lang.Number;
        var stepHistory = frame[:stepHistory] as Lang.Array<Lang.Number>;
        var intMins = frame[:intMins] as Lang.Number;
        var intGoal = frame[:intGoal] as Lang.Number;
        var bodyBattery = frame[:bb] as Lang.Number?;
        var stress = frame[:stress] as Lang.Number?;
        var readinessMode = frame[:readinessMode] as Lang.Number;
        var cardStyle = frame[:cardStyle] as Lang.Number;
        var showSparkline = frame[:showSpark] as Lang.Boolean;
        var showMicroGauges = frame[:showMicro] as Lang.Boolean;
        var bottomLeftMetric = frame[:blMetric] as Lang.Number;
        var bottomRightMetric = frame[:brMetric] as Lang.Number;

        var primaryCol = theme[:primary] as Lang.Number;
        var secondaryCol = theme[:secondary] as Lang.Number;
        var mutedCol = theme[:muted] as Lang.Number;
        var dimCol = theme[:dim] as Lang.Number;
        var textCol = theme[:text] as Lang.Number;
        var isMip = (width <= 260);
        var s = width.toFloat() / 454.0;

        var gridW1 = (width * 0.81).toNumber();
        var leftX1 = cx - (gridW1 / 2);
        var row1Y = prevBottomY + (isMip ? 3 : 6);
        var row1H = (height * 0.172).toNumber();

        var recHours = _comp.getRecoveryHours();
        var trainVal = "--";
        var trainLabel = "READY";
        var readyScore = computeReadinessScore(bodyBattery, stress, recHours);
        if (readinessMode == 1) {
            trainLabel = "STAT";
            trainVal = formatTrainingStatusShort(_comp.getTrainingStatusText());
        } else if (readyScore != null) {
            trainVal = (readyScore as Lang.Number).format("%d");
        }
        var recText = (recHours != null) ? ((recHours as Lang.Number).format("%d") + "h") : "--h";
        var readyRatio = (readyScore != null) ? clampRatio((readyScore as Lang.Number).toFloat() / 100.0) : 0.0;

        var targetSummary = formatNumberWithComma(stepTarget);
        var stepStr = formatNumberWithComma(steps);
        var stepRatio = clampRatio(steps.toFloat() / stepTarget.toFloat());

        // --- Row 1 ---
        if (cardStyle == 0) {
            // Option 1: Circular Ring Gauge for READY + REC Capsule + Steps Stadium Bay
            drawCircularRingGauge(
                dc, [leftX1 + (39 * s).toNumber(), row1Y + (37 * s).toNumber(), (35 * s).toNumber()], readyRatio,
                trainLabel, trainVal, [primaryCol, primaryCol, false, false, showMicroGauges, cardStyle], theme
            );

            var recX = leftX1 + (82 * s).toNumber();
            var recW = (68 * s).toNumber();
            var recPad = isMip ? 3 : 5;
            drawBentoCard(dc, recX, row1Y + recPad, recW, row1H - (recPad * 2), (18 * s).toNumber(), cardStyle, theme);
            dc.setColor(mutedCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(recX + (recW / 2), row1Y + (19 * s).toNumber(), _fLabel, "REC", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            var recFont1 = selectValueFont(dc, recText, recW - (isMip ? 4 : 10));
            dc.setColor(theme[:rec] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.drawText(recX + (recW / 2), row1Y + (46 * s).toNumber(), recFont1, recText, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            var sx2 = leftX1 + (158 * s).toNumber();
            var sw2 = gridW1 - (158 * s).toNumber();
            var sPad = isMip ? 1 : 2;
            drawBentoCard(dc, sx2, row1Y + sPad, sw2, row1H - (sPad * 2), (22 * s).toNumber(), cardStyle, theme);
            dc.setColor(mutedCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(sx2 + (12 * s).toNumber(), row1Y + (17 * s).toNumber(), _fLabel, "STEPS", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(dimCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                sx2 + sw2 - (12 * s).toNumber(),
                row1Y + (17 * s).toNumber(),
                _fLabel,
                fitTextToWidth(dc, targetSummary, _fLabel, sw2 - (80 * s).toNumber()),
                Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER
            );
            var sMaxW1 = showSparkline ? (sw2 - (74 * s).toNumber()) : (sw2 - (24 * s).toNumber());
            var sFont1 = selectValueFont(dc, stepStr, sMaxW1);
            dc.setColor(textCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(sx2 + (12 * s).toNumber(), row1Y + (47 * s).toNumber(), sFont1, fitTextToWidth(dc, stepStr, sFont1, sMaxW1), Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            if (showSparkline) {
                drawSevenDaySparkline(dc, sx2 + sw2 - (36 * s).toNumber(), row1Y + row1H - (13 * s).toNumber(), stepHistory, stepTarget, theme);
            }
        } else if (cardStyle == 1 || cardStyle == 2) {
            // Option 4 & Hybrid 1+4: Unified Panoramic Cockpit Bay
            drawBentoCard(dc, leftX1, row1Y, gridW1, row1H, (22 * s).toNumber(), cardStyle, theme);
            var c1X = leftX1 + (42 * s).toNumber();
            var c2X = leftX1 + (110 * s).toNumber();
            var dPad1 = (14 * s).toNumber();
            var dPad2 = (10 * s).toNumber();
            dc.setColor(theme[:tickMinor] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(leftX1 + (78 * s).toNumber(), row1Y + dPad1, leftX1 + (78 * s).toNumber(), row1Y + row1H - dPad1);
            dc.setColor(theme[:cardBd] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(leftX1 + (142 * s).toNumber(), row1Y + dPad2, leftX1 + (142 * s).toNumber(), row1Y + row1H - dPad2);

            var lblY = row1Y + (17 * s).toNumber();
            var valY = row1Y + (47 * s).toNumber();
            dc.setColor(mutedCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(c1X, lblY, _fLabel, trainLabel, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(c2X, lblY, _fLabel, "REC", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            var rf4Max = (64 * s).toNumber();
            var rf4 = selectValueFont(dc, trainVal, rf4Max);
            dc.setColor(primaryCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(c1X, valY, rf4, fitTextToWidth(dc, trainVal, rf4, rf4Max), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            var recF4 = selectValueFont(dc, recText, (56 * s).toNumber());
            dc.setColor(theme[:rec] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.drawText(c2X, valY, recF4, recText, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            var sxP = leftX1 + (154 * s).toNumber();
            var swP = gridW1 - (166 * s).toNumber();
            dc.setColor(mutedCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(sxP, lblY, _fLabel, "STEPS", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(dimCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                sxP + swP,
                lblY,
                _fLabel,
                fitTextToWidth(dc, targetSummary, _fLabel, swP - (74 * s).toNumber()),
                Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER
            );
            var sMaxWP = showSparkline ? (swP - (54 * s).toNumber()) : swP;
            var sFontP = selectValueFont(dc, stepStr, sMaxWP);
            dc.setColor(textCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(sxP, valY, sFontP, fitTextToWidth(dc, stepStr, sFontP, sMaxWP), Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            if (showSparkline) {
                drawSevenDaySparkline(dc, sxP + swP - (25 * s).toNumber(), row1Y + row1H - (12 * s).toNumber(), stepHistory, stepTarget, theme);
            }
        } else {
            // Option 3 HUD: Borderless floating READY | REC | STEPS + laser hairlines
            var w1H = (gridW1 * 44) / 100;
            var hw1H = w1H / 2;
            var lblYH = row1Y + (14 * s).toNumber();
            var valYH = row1Y + (42 * s).toNumber();
            dc.setColor(mutedCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(leftX1 + (hw1H / 2), lblYH, _fLabel, trainLabel, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(leftX1 + hw1H + (hw1H / 2), lblYH, _fLabel, "REC", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            var rf3 = selectValueFont(dc, trainVal, hw1H - (isMip ? 2 : 6));
            dc.setColor(primaryCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(leftX1 + (hw1H / 2), valYH, rf3, fitTextToWidth(dc, trainVal, rf3, hw1H - (isMip ? 2 : 6)), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            var recF3 = selectValueFont(dc, recText, hw1H - (isMip ? 2 : 6));
            dc.setColor(theme[:rec] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.drawText(leftX1 + hw1H + (hw1H / 2), valYH, recF3, recText, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            if (showMicroGauges) {
                drawHorizontalProgressBar(dc, leftX1 + (12 * s).toNumber(), row1Y + row1H - (10 * s).toNumber(), w1H - (22 * s).toNumber(), isMip ? 2 : 4, readyRatio, primaryCol, theme);
            }

            dc.setColor(theme[:cardBd] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(leftX1 + w1H + (4 * s).toNumber(), row1Y + (8 * s).toNumber(), leftX1 + w1H + (4 * s).toNumber(), row1Y + row1H - (8 * s).toNumber());

            var sx3 = leftX1 + w1H + (14 * s).toNumber();
            var sw3 = gridW1 - w1H - (14 * s).toNumber();
            dc.setColor(mutedCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(sx3, lblYH, _fLabel, "STEPS", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(dimCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(sx3 + sw3 - (4 * s).toNumber(), lblYH, _fLabel, fitTextToWidth(dc, targetSummary, _fLabel, sw3 - (74 * s).toNumber()), Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
            var sFont3 = selectValueFont(dc, stepStr, showSparkline ? (sw3 - (56 * s).toNumber()) : sw3);
            dc.setColor(textCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(sx3, valYH, sFont3, stepStr, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            if (showSparkline) {
                drawSevenDaySparkline(dc, sx3 + sw3 - (26 * s).toNumber(), row1Y + row1H - (13 * s).toNumber(), stepHistory, stepTarget, theme);
            }
            if (showMicroGauges) {
                drawHorizontalProgressBar(dc, sx3, row1Y + row1H - (10 * s).toNumber(), sw3 - (4 * s).toNumber(), isMip ? 2 : 4, stepRatio, primaryCol, theme);
            }
            dc.setColor(theme[:tickMinor] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(leftX1 + (22 * s).toNumber(), row1Y + row1H + 2, leftX1 + gridW1 - (22 * s).toNumber(), row1Y + row1H + 2);
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
            var row2Y = row1Y + row1H + (9 * s).toNumber();
            var gw2 = (width * 0.72).toNumber();
            var lx2 = cx - (gw2 / 2);
            var pw3 = gw2 / 3;
            var colsX = [lx2 + (pw3 / 2), cx, lx2 + gw2 - (pw3 / 2)];
            dc.setColor(theme[:tickMinor] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(lx2 + pw3, row2Y + (8 * s).toNumber(), lx2 + pw3, row2Y + (56 * s).toNumber());
            dc.drawLine(lx2 + (2 * pw3), row2Y + (8 * s).toNumber(), lx2 + (2 * pw3), row2Y + (56 * s).toNumber());

            dc.setColor(mutedCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(colsX[0], row2Y + (10 * s).toNumber(), _fLabel, blLabel, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(colsX[1], row2Y + (10 * s).toNumber(), _fLabel, "HEART", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(colsX[2], row2Y + (10 * s).toNumber(), _fLabel, brLabel, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            var padRow2 = isMip ? 4 : 10;
            var valY2 = row2Y + (35 * s).toNumber();
            var blF3 = selectValueFont(dc, blValue, pw3 - padRow2);
            dc.setColor(secondaryCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(colsX[0], valY2, blF3, fitTextToWidth(dc, blValue, blF3, pw3 - padRow2), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            var hrIconGap = isMip ? 11 : 17;
            var hrF3 = selectValueFont(dc, hrStr, pw3 - (isMip ? 14 : 22));
            var hrW3 = dc.getTextWidthInPixels(hrStr, hrF3);
            var hrSX3 = colsX[1] - ((hrW3 + hrIconGap) / 2);
            drawHeartIcon(dc, hrSX3 + (isMip ? 4 : 6), valY2 - 1, theme[:crimson] as Lang.Number);
            dc.setColor(textCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(hrSX3 + hrIconGap, valY2, hrF3, hrStr, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

            var brF3 = selectValueFont(dc, brValue, pw3 - padRow2);
            dc.setColor(brCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(colsX[2], valY2, brF3, fitTextToWidth(dc, brValue, brF3, pw3 - padRow2), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            if (showMicroGauges) {
                var smileR = (38 * s).toNumber();
                var smileCy = row2Y + (32 * s).toNumber();
                var smileCols = [secondaryCol, theme[:crimson] as Lang.Number, brCol];
                var smileRats = [blRatio, hrRatio, brRatio];
                dc.setPenWidth(isMip ? 2 : 4);
                for (var sm = 0; sm < 3; sm++) {
                    dc.setColor(theme[:track] as Lang.Number, Graphics.COLOR_TRANSPARENT);
                    dc.drawArc(colsX[sm], smileCy, smileR, Graphics.ARC_COUNTER_CLOCKWISE, 220, 320);
                    var swp = (100.0 * smileRats[sm]).toNumber();
                    if (swp >= 1) {
                        dc.setColor(smileCols[sm], Graphics.COLOR_TRANSPARENT);
                        dc.drawArc(colsX[sm], smileCy, smileR, Graphics.ARC_COUNTER_CLOCKWISE, 220, 220 + swp);
                    }
                }
                dc.setPenWidth(1);
            }
            return;
        }

        // Options 1, 4, and Hybrid 1+4: Three 270-degree Circular Ring Dials along lower curve
        var r2Cy = row1Y + row1H + (49 * s).toNumber();
        var r2R = (width * 0.093).toNumber();
        var ringOffset = (width * 0.236).toNumber();
        var isTicked = (cardStyle == 1);

        drawCircularRingGauge(
            dc, [cx - ringOffset, r2Cy, r2R], blRatio,
            blLabel, blValue, [secondaryCol, secondaryCol, false, isTicked, showMicroGauges, cardStyle], theme
        );
        drawCircularRingGauge(
            dc, [cx, r2Cy, r2R], hrRatio,
            "HEART", hrStr, [theme[:crimson] as Lang.Number, textCol, true, isTicked, showMicroGauges, cardStyle], theme
        );
        drawCircularRingGauge(
            dc, [cx + ringOffset, r2Cy, r2R], brRatio,
            brLabel, brValue, [brCol, brCol, false, isTicked, showMicroGauges, cardStyle], theme
        );
    }

    //! Draws a 270-degree circular gauge dial with bottom-gap label and glowing tip dot.
    private function drawCircularRingGauge(
        dc as Graphics.Dc,
        geom as Lang.Array<Lang.Number>,
        ratio as Lang.Float,
        labelText as Lang.String,
        valText as Lang.String,
        opts as Lang.Array<Lang.Object>,
        theme as Lang.Dictionary
    ) as Void {
        var rcx = geom[0];
        var rcy = geom[1];
        var r = geom[2];
        var arcColor = opts[0] as Lang.Number;
        var valColor = opts[1] as Lang.Number;
        var isHeart = opts[2] as Lang.Boolean;
        var tickStyle = opts[3] as Lang.Boolean;
        var showGauge = opts[4] as Lang.Boolean;
        var cardStyle = opts[5] as Lang.Number;
        var isMip = (_screenWidth <= 260);
        if (showGauge) {
            dc.setPenWidth(isMip ? 3 : 6);
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
                    var th = isMip ? 2 : 4;
                    dc.setPenWidth(1);
                    dc.setColor(bgCol, Graphics.COLOR_TRANSPARENT);
                    for (var t = 1; t <= 8; t++) {
                        var tDeg = 225 - (t * 30);
                        if (tDeg < 0) {
                            tDeg += 360;
                        }
                        drawRadialTickAtDeg(dc, rcx, rcy, r - th, r + th, tDeg);
                    }
                }
                drawArcTipDot(dc, rcx, rcy, r, endDeg, arcColor, theme[:tipDot] as Lang.Number);
            }
            dc.setPenWidth(1);
        }

        if (isHeart) {
            var hPad = isMip ? 8 : 22;
            var hOff = isMip ? 10 : 17;
            var hFont = selectValueFont(dc, valText, (r * 2) - hPad);
            var hW = dc.getTextWidthInPixels(valText, hFont);
            var hSx = rcx - ((hW + hOff) / 2);
            drawHeartIcon(dc, hSx + (isMip ? 3 : 6), rcy - (isMip ? 2 : 3), theme[:crimson] as Lang.Number);
            dc.setColor(valColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(hSx + hOff, rcy - (isMip ? 2 : 2), hFont, valText, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        } else {
            var maxValW = (r * 2) - (isMip ? 4 : 18);
            var vFont = selectValueFont(dc, valText, maxValW);
            dc.setColor(valColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                rcx,
                rcy - (isMip ? 2 : 3),
                vFont,
                fitTextToWidth(dc, valText, vFont, maxValW),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
        }

        dc.setColor(theme[:muted] as Lang.Number, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            rcx,
            rcy + r - (isMip ? 1 : 3),
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
        var isMip = (_screenWidth <= 260);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        if (isMip) {
            dc.fillCircle(cx - 2, cy - 1, 2);
            dc.fillCircle(cx + 2, cy - 1, 2);
            dc.fillPolygon([[cx - 4, cy], [cx + 4, cy], [cx, cy + 4]]);
            return;
        }
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

        var isMip = (_screenWidth <= 260);
        var barW = isMip ? 2 : 5;
        var barGap = isMip ? 1 : 2;
        var maxH = isMip ? 14 : 28;
        var totalW = (7 * barW) + (6 * barGap);
        var startX = centerX - (totalW / 2);
        var startSlot = 7 - count;
        var hitCol = theme[:primary] as Lang.Number;
        var missCol = theme[:dim] as Lang.Number;

        for (var d = 0; d < count; d++) {
            var val = stepHistory[d];
            var barH = ((val.toFloat() / maxVal.toFloat()) * maxH).toNumber();
            if (barH < 2 && val > 0) {
                barH = isMip ? 2 : 3;
            }
            var bx = startX + ((startSlot + d) * (barW + barGap));
            dc.setColor((val >= stepTarget) ? hitCol : missCol, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(bx, baseY - barH, barW, barH);
        }

        var threshY = baseY - ((stepTarget.toFloat() / maxVal.toFloat()) * maxH).toNumber();
        dc.setColor(theme[:muted] as Lang.Number, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(startX - 1, threshY, startX + totalW + 1, threshY);
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
        var battY = (height * 0.882).toNumber();
        drawBottomBatteryBarAt(dc, cx, battY, batteryFormat, theme);
    }

    //! Draws segmented battery gauge at a specific Y position.
    private function drawBottomBatteryBarAt(
        dc as Graphics.Dc,
        cx as Lang.Number,
        battY as Lang.Number,
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

        var isMip = (_screenWidth <= 260);
        var battW = isMip ? 18 : 30;
        var battH = isMip ? 10 : 15;
        var textGap = isMip ? 5 : 10;
        var textW = dc.getTextWidthInPixels(labelStr, _fSmall);
        var totalW = battW + textGap + textW;
        var startX = cx - (totalW / 2);
        var mutedCol = theme[:muted] as Lang.Number;
        var trackCol = theme[:track] as Lang.Number;

        dc.setColor(mutedCol, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(startX, battY, battW, battH, isMip ? 2 : 3);
        dc.fillRectangle(startX + battW, battY + (isMip ? 2 : 3), isMip ? 1 : 2, battH - (isMip ? 4 : 6));

        var activeBlocks = (pct + 24) / 25;
        var blockW = isMip ? 3 : 5;
        var blockGap = 1;
        for (var b = 0; b < 4; b++) {
            var bx = startX + (isMip ? 1 : 2) + (b * (blockW + blockGap));
            dc.setColor((b < activeBlocks) ? fillColor : trackCol, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(bx, battY + (isMip ? 1 : 2), blockW, battH - (isMip ? 2 : 4));
        }

        dc.setColor(mutedCol, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            startX + battW + (isMip ? 4 : 8),
            battY + (battH / 2),
            _fSmall,
            labelStr,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }

    //! Resolves all telemetry and weather strings once for radical layouts (CardStyle 4..7).
    private function buildMetricsBundle(
        actInfo as ActivityMonitor.Info,
        frame as Lang.Dictionary,
        theme as Lang.Dictionary
    ) as Lang.Dictionary {
        var steps = frame[:steps] as Lang.Number;
        var stepTarget = frame[:stepTarget] as Lang.Number;
        var stepHistory = frame[:stepHistory] as Lang.Array<Lang.Number>;
        var intMins = frame[:intMins] as Lang.Number;
        var intGoal = frame[:intGoal] as Lang.Number;
        var bodyBattery = frame[:bb] as Lang.Number?;
        var stress = frame[:stress] as Lang.Number?;
        var readinessMode = frame[:readinessMode] as Lang.Number;
        var bottomLeftMetric = frame[:blMetric] as Lang.Number;
        var bottomRightMetric = frame[:brMetric] as Lang.Number;
        var weatherDetailMode = frame[:wDetail] as Lang.Number;
        var recHours = _comp.getRecoveryHours();
        var trainVal = "--";
        var trainLabel = "READY";
        var readyScore = computeReadinessScore(bodyBattery, stress, recHours);
        if (readinessMode == 1) {
            trainLabel = "STAT";
            trainVal = formatTrainingStatusShort(_comp.getTrainingStatusText());
        } else if (readyScore != null) {
            trainVal = (readyScore as Lang.Number).format("%d");
        }
        var recText = (recHours != null) ? ((recHours as Lang.Number).format("%d") + "h") : "--h";
        var readyRatio = (readyScore != null) ? clampRatio((readyScore as Lang.Number).toFloat() / 100.0) : 0.0;

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
            brCol = (stress != null && (stress as Lang.Number) >= 60) ? (theme[:secondary] as Lang.Number) : (theme[:bodyBat] as Lang.Number);
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

        var today = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var mon = (today.month != null) ? (today.month as Lang.String).toUpper() : "";
        var day = (today.day != null) ? (today.day as Lang.Number).format("%d") : "";
        var wLine1 = mon + " " + day;
        var wLine2 = "";
        if (Toybox has :Weather) {
            var cond = Weather.getCurrentConditions();
            var dailyArr = (Weather has :getDailyForecast) ? Weather.getDailyForecast() : null;
            var todayFcst = (dailyArr != null && dailyArr.size() > 0) ? dailyArr[0] : null;
            if (cond != null) {
                if (cond.temperature != null) {
                    wLine1 = wLine1 + " • " + formatTempShort(cond.temperature as Lang.Number or Lang.Float);
                }
                if (weatherDetailMode != 2) {
                    var fcst = (todayFcst != null) ? (todayFcst as Weather.DailyForecast) : null;
                    var hiVal = (cond.highTemperature != null) ? cond.highTemperature : ((fcst != null) ? fcst.highTemperature : null);
                    var loVal = (cond.lowTemperature != null) ? cond.lowTemperature : ((fcst != null) ? fcst.lowTemperature : null);
                    if (hiVal != null && loVal != null) {
                        wLine2 = "H" + formatTempShort(hiVal as Lang.Number or Lang.Float)
                            + " L" + formatTempShort(loVal as Lang.Number or Lang.Float);
                    }
                    var precip = (cond.precipitationChance != null) ? cond.precipitationChance : ((fcst != null) ? fcst.precipitationChance : null);
                    if (precip != null && weatherDetailMode == 0) {
                        wLine2 = (!wLine2.equals("") ? (wLine2 + " • ") : "") + (precip as Lang.Number).format("%d") + "%";
                    }
                }
            }
        }

        return {
            :trainLabel => trainLabel,
            :trainVal => trainVal,
            :readyRatio => readyRatio,
            :recText => recText,
            :stepStr => formatNumberWithComma(steps),
            :targetSummary => formatNumberWithComma(stepTarget),
            :stepRatio => clampRatio(steps.toFloat() / stepTarget.toFloat()),
            :stepHistory => stepHistory,
            :stepTarget => stepTarget,
            :intRatio => clampRatio(intMins.toFloat() / intGoal.toFloat()),
            :blLabel => blLabel,
            :blValue => blValue,
            :blRatio => blRatio,
            :hrStr => hrStr,
            :hrRatio => hrRatio,
            :brLabel => brLabel,
            :brValue => brValue,
            :brRatio => brRatio,
            :brCol => brCol,
            :wLine1 => wLine1,
            :wLine2 => wLine2
        };
    }

    //! Concept A (CardStyle 4): Asymmetric Vertical-Stack Split Chronograph (06 / 48 left + telemetry right).
    private function drawLayoutVerticalSplit(
        dc as Graphics.Dc,
        width as Lang.Number,
        height as Lang.Number,
        clockTime as System.ClockTime,
        m as Lang.Dictionary,
        frame as Lang.Dictionary,
        theme as Lang.Dictionary
    ) as Void {
        var cx = width / 2;
        var cy = height / 2;
        var worldCityIndex = frame[:worldCity] as Lang.Number;
        var showSeconds = frame[:showSec] as Lang.Boolean;
        var showRings = frame[:showRings] as Lang.Boolean;
        var showSparkline = frame[:showSpark] as Lang.Boolean;
        var showMicroGauges = frame[:showMicro] as Lang.Boolean;
        var batteryFormat = frame[:battFmt] as Lang.Number;

        var s = width.toFloat() / 454.0;
        var isMip = (width <= 260);
        var primaryCol = theme[:primary] as Lang.Number;
        var secondaryCol = theme[:secondary] as Lang.Number;
        var mutedCol = theme[:muted] as Lang.Number;
        var dimCol = theme[:dim] as Lang.Number;
        var textCol = theme[:text] as Lang.Number;

        if (showRings) {
            drawDualProgressArcs(
                dc, cx, cy, width,
                m[:stepRatio] as Lang.Float,
                m[:intRatio] as Lang.Float,
                3, theme
            );
        }

        // Weather header
        dc.setColor(textCol, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (24 * s).toNumber(), _fSmall, m[:wLine1] as Lang.String, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        var wLine2 = m[:wLine2] as Lang.String;
        if (!wLine2.equals("")) {
            dc.setColor(dimCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (46 * s).toNumber(), _fLabel, wLine2, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // Left Hemisphere: Vertical stacked Hours over Minutes
        var parts = formatClockParts(clockTime);
        var hStr = parts[:hour] as Lang.String;
        if (hStr.length() == 1) {
            hStr = "0" + hStr;
        }
        var minStr = parts[:min] as Lang.String;
        var amPm = parts[:amPm] as Lang.String;
        var lx = (130 * s).toNumber();
        dc.setColor(textCol, Graphics.COLOR_TRANSPARENT);
        dc.drawText(lx, (112 * s).toNumber(), _fTime, hStr, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        var shOff = isMip ? 1 : 2;
        dc.setColor(theme[:shadow] as Lang.Number, Graphics.COLOR_TRANSPARENT);
        dc.drawText(lx + shOff, (192 * s).toNumber() + shOff, _fTime, minStr, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(primaryCol, Graphics.COLOR_TRANSPARENT);
        dc.drawText(lx, (192 * s).toNumber(), _fTime, minStr, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        if (!amPm.equals("")) {
            dc.setColor(dimCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText((196 * s).toNumber(), (95 * s).toNumber(), _fLabel, amPm, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        if (showSeconds) {
            var sx = (196 * s).toNumber();
            var sy = (124 * s).toNumber();
            var secW = isMip ? 20 : 32;
            var secH = isMip ? 14 : 22;
            dc.setColor(theme[:cardBg] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(sx - (secW / 2), sy - (secH / 2), secW, secH, secH / 2);
            dc.setColor(theme[:cardBd] as Lang.Number, Graphics.COLOR_TRANSPARENT);
            dc.drawRoundedRectangle(sx - (secW / 2), sy - (secH / 2), secW, secH, secH / 2);
            dc.setColor(primaryCol, Graphics.COLOR_TRANSPARENT);
            dc.drawText(sx, sy, _fLabel, clockTime.sec.format("%02d"), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // Center Divider
        dc.setColor(theme[:cardBd] as Lang.Number, Graphics.COLOR_TRANSPARENT);
        dc.drawLine((220 * s).toNumber(), (64 * s).toNumber(), (220 * s).toNumber(), (246 * s).toNumber());

        // Right Hemisphere: KTM Pill, READY Ring + REC, Steps Bay
        var rx = (232 * s).toNumber();
        var rw = (170 * s).toNumber();
        var ktmH = isMip ? 17 : 28;
        var cityParts = getWorldCityParts(worldCityIndex);
        drawBentoCard(dc, rx, (66 * s).toNumber(), rw, ktmH, ktmH / 2, 0, theme);
        dc.setColor(primaryCol, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(rx + (isMip ? 1 : 2), (66 * s).toNumber() + (isMip ? 1 : 2), (56 * s).toNumber(), ktmH - (isMip ? 2 : 4), (ktmH - (isMip ? 2 : 4)) / 2);
        dc.setColor(theme[:onPrimary] as Lang.Number, Graphics.COLOR_TRANSPARENT);
        dc.drawText(rx + (30 * s).toNumber(), (66 * s).toNumber() + (ktmH / 2), _fLabel, cityParts[:code] as Lang.String, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(theme[:pillText] as Lang.Number, Graphics.COLOR_TRANSPARENT);
        dc.drawText(rx + (114 * s).toNumber(), (66 * s).toNumber() + (ktmH / 2), _fLabel, cityParts[:timeStr] as Lang.String, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        drawCircularRingGauge(
            dc, [(268 * s).toNumber(), (138 * s).toNumber(), (31 * s).toNumber()], m[:readyRatio] as Lang.Float,
            m[:trainLabel] as Lang.String, m[:trainVal] as Lang.String,
            [primaryCol, primaryCol, false, false, showMicroGauges, 0], theme
        );

        var recX = (312 * s).toNumber();
        var recW = (88 * s).toNumber();
        drawBentoCard(dc, recX, (108 * s).toNumber(), recW, (58 * s).toNumber(), (16 * s).toNumber(), 0, theme);
        dc.setColor(mutedCol, Graphics.COLOR_TRANSPARENT);
        dc.drawText(recX + (recW / 2), (122 * s).toNumber(), _fLabel, "REC", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(theme[:rec] as Lang.Number, Graphics.COLOR_TRANSPARENT);
        dc.drawText(recX + (recW / 2), (147 * s).toNumber(), _fMidValue, m[:recText] as Lang.String, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var stY = (176 * s).toNumber();
        var stH = (70 * s).toNumber();
        drawBentoCard(dc, rx, stY, rw, stH, (16 * s).toNumber(), 0, theme);
        var stPad = isMip ? 5 : 10;
        dc.setColor(mutedCol, Graphics.COLOR_TRANSPARENT);
        dc.drawText(rx + stPad, stY + (15 * s).toNumber(), _fLabel, "STEPS", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(dimCol, Graphics.COLOR_TRANSPARENT);
        dc.drawText(rx + rw - stPad, stY + (15 * s).toNumber(), _fLabel, m[:targetSummary] as Lang.String, Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        var sf = selectValueFont(dc, m[:stepStr] as Lang.String, showSparkline ? (rw - (66 * s).toNumber()) : (rw - (stPad * 2)));
        dc.setColor(textCol, Graphics.COLOR_TRANSPARENT);
        dc.drawText(rx + stPad, stY + (46 * s).toNumber(), sf, m[:stepStr] as Lang.String, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        if (showSparkline) {
            drawSevenDaySparkline(dc, rx + rw - (30 * s).toNumber(), stY + stH - (isMip ? 5 : 8), m[:stepHistory] as Lang.Array<Lang.Number>, m[:stepTarget] as Lang.Number, theme);
        }

        // Mid-Lower Calendar Stadium Ribbon
        var rib = resolveRibbonContent();
        var badge = rib[:badge] as Lang.String;
        var evTitle = rib[:body] as Lang.String;
        var calX = (48 * s).toNumber();
        var calW = width - (96 * s).toNumber();
        var calY = (256 * s).toNumber();
        var calH = isMip ? 24 : 42;
        drawBentoCard(dc, calX, calY, calW, calH, calH / 2, 0, theme);
        var cPad = isMip ? 2 : 4;
        var capW = (74 * s).toNumber();
        dc.setColor(primaryCol, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(calX + cPad, calY + cPad, capW, calH - (cPad * 2), (calH - (cPad * 2)) / 2);
        dc.setColor(theme[:onPrimary] as Lang.Number, Graphics.COLOR_TRANSPARENT);
        dc.drawText(calX + cPad + (capW / 2), calY + (calH / 2), _fSmall, badge, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(textCol, Graphics.COLOR_TRANSPARENT);
        dc.drawText(calX + (86 * s).toNumber(), calY + (calH / 2), _fEvent, fitTextToWidth(dc, evTitle, _fEvent, calW - (96 * s).toNumber()), Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        // Bottom 3 Circular Ring Dials
        var r2Cy = (348 * s).toNumber();
        var r2R = (39 * s).toNumber();
        var rOff = (102 * s).toNumber();
        drawCircularRingGauge(dc, [cx - rOff, r2Cy, r2R], m[:blRatio] as Lang.Float, m[:blLabel] as Lang.String, m[:blValue] as Lang.String, [secondaryCol, secondaryCol, false, false, showMicroGauges, 0], theme);
        drawCircularRingGauge(dc, [cx, r2Cy, r2R], m[:hrRatio] as Lang.Float, "HEART", m[:hrStr] as Lang.String, [theme[:crimson] as Lang.Number, textCol, true, false, showMicroGauges, 0], theme);
        drawCircularRingGauge(dc, [cx + rOff, r2Cy, r2R], m[:brRatio] as Lang.Float, m[:brLabel] as Lang.String, m[:brValue] as Lang.String, [m[:brCol] as Lang.Number, m[:brCol] as Lang.Number, false, false, showMicroGauges, 0], theme);

        drawBottomBatteryBarAt(dc, cx, (height * 0.892).toNumber(), batteryFormat, theme);
    }

    //! Concept C (CardStyle 5 / Menu #6): F1 Pit-Wall Telemetry Deck.
    private function drawLayoutF1Telemetry(
        dc as Graphics.Dc,
        width as Lang.Number,
        height as Lang.Number,
        clockTime as System.ClockTime,
        m as Lang.Dictionary,
        frame as Lang.Dictionary,
        theme as Lang.Dictionary
    ) as Void {
        var cx = width / 2;
        var cy = height / 2;
        var worldCityIndex = frame[:worldCity] as Lang.Number;
        var showSeconds = frame[:showSec] as Lang.Boolean;
        var showRings = frame[:showRings] as Lang.Boolean;
        var showSparkline = frame[:showSpark] as Lang.Boolean;
        var showMicroGauges = frame[:showMicro] as Lang.Boolean;
        var batteryFormat = frame[:battFmt] as Lang.Number;

        var s = width.toFloat() / 454.0;
        var isMip = (width <= 260);
        var primaryCol = theme[:primary] as Lang.Number;
        var secondaryCol = theme[:secondary] as Lang.Number;
        var mutedCol = theme[:muted] as Lang.Number;
        var dimCol = theme[:dim] as Lang.Number;
        var textCol = theme[:text] as Lang.Number;

        if (showRings) {
            drawDualProgressArcs(
                dc, cx, cy, width,
                m[:stepRatio] as Lang.Float,
                m[:intRatio] as Lang.Float,
                2, theme
            );
        }

        dc.setColor(mutedCol, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (24 * s).toNumber(), _fSmall, m[:wLine1] as Lang.String, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Top Racing Pit-Board Calendar Banner
        var rib = resolveRibbonContent();
        var badge = rib[:badge] as Lang.String;
        var evTitle = rib[:body] as Lang.String;
        var bx = (80 * s).toNumber();
        var by = (42 * s).toNumber();
        var bw = width - (160 * s).toNumber();
        var bh = isMip ? 23 : 40;
        var bRad = isMip ? 8 : 14;
        dc.setColor(primaryCol, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(bx, by, bw, bh, bRad);
        dc.setColor(theme[:cardBg] as Lang.Number, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(bx, by, (84 * s).toNumber(), bh, bRad);
        dc.fillPolygon([[bx + (66 * s).toNumber(), by], [bx + (88 * s).toNumber(), by], [bx + (74 * s).toNumber(), by + bh], [bx + (58 * s).toNumber(), by + bh]]);
        dc.setColor(textCol, Graphics.COLOR_TRANSPARENT);
        dc.drawText(bx + (38 * s).toNumber(), by + (bh / 2), _fSmall, badge, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(theme[:onPrimary] as Lang.Number, Graphics.COLOR_TRANSPARENT);
        dc.drawText(bx + (92 * s).toNumber(), by + (bh / 2), _fEvent, fitTextToWidth(dc, evTitle, _fEvent, bw - (100 * s).toNumber()), Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        // Center Motorsport Clock + Right KTM/Weather/Sec stack
        var parts = formatClockParts(clockTime);
        var hStr = parts[:hour] as Lang.String;
        var minStr = parts[:min] as Lang.String;
        var cFont = selectTimeFont(dc, hStr + ":" + minStr, (206 * s).toNumber());
        var hw = dc.getTextWidthInPixels(hStr, cFont);
        var cw = dc.getTextWidthInPixels(":", cFont);
        var cx0 = (54 * s).toNumber();
        var cyClock = (136 * s).toNumber();
        dc.setColor(textCol, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx0, cyClock, cFont, hStr, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(secondaryCol, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx0 + hw, cyClock - (isMip ? 1 : 3), cFont, ":", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(primaryCol, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx0 + hw + cw, cyClock, cFont, minStr, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        var rx = (274 * s).toNumber();
        var rw = (122 * s).toNumber();
        var kH = isMip ? 17 : 30;
        var cityParts = getWorldCityParts(worldCityIndex);
        dc.setColor(theme[:cardBg] as Lang.Number, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(rx, (96 * s).toNumber(), rw, kH, isMip ? 5 : 8);
        dc.setColor(secondaryCol, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(rx, (96 * s).toNumber(), rw, kH, isMip ? 5 : 8);
        dc.drawText(rx + (rw / 2), (96 * s).toNumber() + (kH / 2), _fSmall, (cityParts[:code] as Lang.String) + " " + (cityParts[:timeStr] as Lang.String), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var secLine = parts[:amPm] as Lang.String;
        if (showSeconds) {
            secLine = (!secLine.equals("") ? (secLine + " ") : "") + clockTime.sec.format("%02d");
        }
        dc.setColor(textCol, Graphics.COLOR_TRANSPARENT);
        dc.drawText(rx + 2, (146 * s).toNumber(), _fSmall, secLine, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(dimCol, Graphics.COLOR_TRANSPARENT);
        dc.drawText(rx + 2, (170 * s).toNumber(), _fLabel, m[:wLine2] as Lang.String, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        // Angled Parallelogram Telemetry Row 1
        var r1T = (196 * s).toNumber();
        var r1B = (270 * s).toNumber();
        dc.setColor(primaryCol, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[(46 * s).toNumber(), r1T], [(144 * s).toNumber(), r1T], [(132 * s).toNumber(), r1B], [(34 * s).toNumber(), r1B]]);
        dc.setColor(theme[:onPrimary] as Lang.Number, Graphics.COLOR_TRANSPARENT);
        dc.drawText((91 * s).toNumber(), (213 * s).toNumber(), _fLabel, m[:trainLabel] as Lang.String, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText((87 * s).toNumber(), (245 * s).toNumber(), _fValue, m[:trainVal] as Lang.String, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(theme[:cardBg] as Lang.Number, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[(152 * s).toNumber(), r1T], [(226 * s).toNumber(), r1T], [(214 * s).toNumber(), r1B], [(140 * s).toNumber(), r1B]]);
        dc.setColor(secondaryCol, Graphics.COLOR_TRANSPARENT);
        dc.drawLine((152 * s).toNumber(), r1T, (226 * s).toNumber(), r1T);
        dc.drawLine((140 * s).toNumber(), r1B, (214 * s).toNumber(), r1B);
        dc.drawText((186 * s).toNumber(), (213 * s).toNumber(), _fLabel, "REC", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(textCol, Graphics.COLOR_TRANSPARENT);
        dc.drawText((181 * s).toNumber(), (245 * s).toNumber(), _fValue, m[:recText] as Lang.String, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(theme[:cardBg] as Lang.Number, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[(234 * s).toNumber(), r1T], [(412 * s).toNumber(), r1T], [(400 * s).toNumber(), r1B], [(222 * s).toNumber(), r1B]]);
        dc.setColor(theme[:cardBd] as Lang.Number, Graphics.COLOR_TRANSPARENT);
        dc.drawLine((234 * s).toNumber(), r1T, (412 * s).toNumber(), r1T);
        dc.drawLine((222 * s).toNumber(), r1B, (400 * s).toNumber(), r1B);
        dc.setColor(mutedCol, Graphics.COLOR_TRANSPARENT);
        dc.drawText((244 * s).toNumber(), (213 * s).toNumber(), _fLabel, "STEPS", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(secondaryCol, Graphics.COLOR_TRANSPARENT);
        dc.drawText((396 * s).toNumber(), (213 * s).toNumber(), _fLabel, m[:targetSummary] as Lang.String, Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        var sf = selectValueFont(dc, m[:stepStr] as Lang.String, showSparkline ? (98 * s).toNumber() : (156 * s).toNumber());
        dc.setColor(textCol, Graphics.COLOR_TRANSPARENT);
        dc.drawText((238 * s).toNumber(), (245 * s).toNumber(), sf, m[:stepStr] as Lang.String, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        if (showSparkline) {
            drawSevenDaySparkline(dc, (368 * s).toNumber(), r1B - 8, m[:stepHistory] as Lang.Array<Lang.Number>, m[:stepTarget] as Lang.Number, theme);
        }

        // Bottom 3 Ticked Tachometer Rings
        var r2Cy = (336 * s).toNumber();
        var r2R = (40 * s).toNumber();
        var rOff = (102 * s).toNumber();
        drawCircularRingGauge(dc, [cx - rOff, r2Cy, r2R], m[:blRatio] as Lang.Float, m[:blLabel] as Lang.String, m[:blValue] as Lang.String, [secondaryCol, secondaryCol, false, true, showMicroGauges, 1], theme);
        drawCircularRingGauge(dc, [cx, r2Cy, r2R], m[:hrRatio] as Lang.Float, "HEART", m[:hrStr] as Lang.String, [primaryCol, textCol, true, true, showMicroGauges, 1], theme);
        drawCircularRingGauge(dc, [cx + rOff, r2Cy, r2R], m[:brRatio] as Lang.Float, m[:brLabel] as Lang.String, m[:brValue] as Lang.String, [m[:brCol] as Lang.Number, m[:brCol] as Lang.Number, false, true, showMicroGauges, 1], theme);

        drawBottomBatteryBarAt(dc, cx, (height * 0.876).toNumber(), batteryFormat, theme);
    }

    //! Concept D1/D3 (CardStyle 6/7): Red & Blue GMT Chrono (Two-Tone or Outer Ring).
    private function drawLayoutTwoToneGmt(
        dc as Graphics.Dc,
        width as Lang.Number,
        height as Lang.Number,
        clockTime as System.ClockTime,
        m as Lang.Dictionary,
        frame as Lang.Dictionary,
        theme as Lang.Dictionary
    ) as Void {
        var cx = width / 2;
        var cy = height / 2;
        var worldCityIndex = frame[:worldCity] as Lang.Number;
        var showSeconds = frame[:showSec] as Lang.Boolean;
        var showSparkline = frame[:showSpark] as Lang.Boolean;
        var showMicroGauges = frame[:showMicro] as Lang.Boolean;
        var batteryFormat = frame[:battFmt] as Lang.Number;
        var bezelOnly = ((frame[:cardStyle] as Lang.Number) == 7);
        var s = width.toFloat() / 454.0;
        var isMip = (width <= 260);
        var eqY = (206 * s).toNumber();
        var crimsonTop = isMip ? (bezelOnly ? 0xFF0000 : 0xAA0000) : (bezelOnly ? 0xEF4444 : 0xC82829);
        var slateBlue = isMip ? 0x0055FF : (bezelOnly ? 0x0077FF : 0x2563EB);
        var navyBot = isMip ? (bezelOnly ? 0x000000 : 0x0000AA) : (bezelOnly ? 0x0B0D10 : 0x0F3882);
        var navyCard = isMip ? (bezelOnly ? 0x000000 : 0x000055) : (bezelOnly ? 0x0C1018 : 0x081E4A);
        var navyBd = isMip ? 0x0055FF : 0x2563EB;
        var navyTrack = isMip ? 0x555555 : (bezelOnly ? 0x142036 : 0x0C2A62);
        var primaryCol = crimsonTop;
        var secondaryCol = isMip ? 0xFFFF00 : 0xFACC15;
        var minCol = bezelOnly ? primaryCol : (isMip ? 0xFFFFAA : 0xFEF3C7);
        var ktmTagCol = bezelOnly ? primaryCol : (isMip ? 0x55AAFF : 0x60A5FA);
        var readyValCol = bezelOnly ? primaryCol : (isMip ? 0xFF5555 : 0xFF7676);

        if (bezelOnly) {
            // D3: Pitch-Black Center Dial + Thick Dual-Tone GMT Outer Bezel Ring (50/50 Red Top / Blue Bottom)
            dc.setColor(navyBot, navyBot);
            dc.fillRectangle(0, 0, width, height);
            var bezelPen = isMip ? 8 : (14 * s).toNumber();
            var ringR = (width / 2) - (isMip ? 5 : (9 * s).toNumber());
            dc.setPenWidth(bezelPen);
            dc.setColor(crimsonTop, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, ringR, Graphics.ARC_CLOCKWISE, 180, 0);
            dc.setColor(slateBlue, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, ringR, Graphics.ARC_CLOCKWISE, 0, 180);
            dc.setPenWidth(1);
            dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
            for (var hrIdx = 0; hrIdx < 24; hrIdx++) {
                if (hrIdx == 6) {
                    var triW = isMip ? 3 : 6;
                    dc.fillPolygon([[cx - triW, isMip ? 2 : 3], [cx + triW, isMip ? 2 : 3], [cx, isMip ? 8 : 13]]);
                    continue;
                }
                if (isMip && (hrIdx % 2) != 0) {
                    continue;
                }
                var hrRad = (hrIdx.toFloat() * 15.0 * Math.PI) / 180.0;
                var dx = cx + (ringR * Math.cos(hrRad)).toNumber();
                var dy = cy - (ringR * Math.sin(hrRad)).toNumber();
                dc.fillCircle(dx, dy, isMip ? 1 : (((hrIdx % 2) == 0) ? 2 : 1));
            }
        } else {
            // D1: Upper Matte Terracotta Red Hemisphere + Lower Slate-Navy Blue Hemisphere
            dc.setColor(crimsonTop, crimsonTop);
            dc.fillRectangle(0, 0, width, eqY);
            dc.setColor(navyBot, navyBot);
            dc.fillRectangle(0, eqY, width, height - eqY);

            // Two-Tone Dual-Tone GMT Outer Bezel Ring (50/50 Red Top / Blue Bottom)
            var ringR = (width / 2) - (isMip ? 2 : 4);
            dc.setPenWidth(isMip ? 4 : 7);
            dc.setColor(crimsonTop, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, ringR, Graphics.ARC_CLOCKWISE, 180, 0);
            dc.setColor(slateBlue, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, ringR, Graphics.ARC_CLOCKWISE, 0, 180);
            dc.setPenWidth(1);
            dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
            var hDot = isMip ? 1 : 2;
            var hOff = isMip ? 3 : 6;
            dc.fillCircle(hOff, cy, hDot);
            dc.fillCircle(width - hOff, cy, hDot);
            dc.fillRectangle(cx - (isMip ? 2 : 3), isMip ? 3 : 6, isMip ? 4 : 6, isMip ? 6 : 11);
        }

        // Top Weather
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (32 * s).toNumber(), _fSmall, m[:wLine1] as Lang.String, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        var wLine2 = m[:wLine2] as Lang.String;
        if (!wLine2.equals("")) {
            dc.setColor(isMip ? 0xAAAAAA : 0xE2E8F0, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (54 * s).toNumber(), _fLabel, wLine2, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // Hero Digital Clock + Seconds Badge
        var parts = formatClockParts(clockTime);
        var hStr = parts[:hour] as Lang.String;
        var minStr = parts[:min] as Lang.String;
        var amPm = parts[:amPm] as Lang.String;
        var cFont = selectTimeFont(dc, hStr + ":" + minStr, (width * 0.66).toNumber());
        var hw = dc.getTextWidthInPixels(hStr, cFont);
        var cw = dc.getTextWidthInPixels(":", cFont);
        var mw = dc.getTextWidthInPixels(minStr, cFont);
        var rightColW = showSeconds ? (isMip ? 26 : 44) : (isMip ? 18 : 32);
        var tx0 = cx - ((hw + cw + mw + rightColW) / 2);
        var cyClock = (102 * s).toNumber();

        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(tx0, cyClock, cFont, hStr, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(isMip ? 0xAAAAAA : 0xCBD5E1, Graphics.COLOR_TRANSPARENT);
        dc.drawText(tx0 + hw, cyClock - (isMip ? 1 : 3), cFont, ":", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(minCol, Graphics.COLOR_TRANSPARENT);
        dc.drawText(tx0 + hw + cw, cyClock, cFont, minStr, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        var rx = tx0 + hw + cw + mw + (isMip ? 4 : 8);
        if (!amPm.equals("")) {
            dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
            dc.drawText(rx, (84 * s).toNumber(), _fLabel, amPm, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        if (showSeconds) {
            var sW = isMip ? 22 : 38;
            var sH = isMip ? 15 : 26;
            var sY = (100 * s).toNumber();
            dc.setColor(navyCard, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(rx, sY, sW, sH, sH / 2);
            dc.setColor(navyBd, Graphics.COLOR_TRANSPARENT);
            dc.drawRoundedRectangle(rx, sY, sW, sH, sH / 2);
            dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
            dc.drawText(rx + (sW / 2), sY + (sH / 2), _fSmall, clockTime.sec.format("%02d"), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // Deep Slate KTM capsule
        var cityParts = getWorldCityParts(worldCityIndex);
        var ktmW = (188 * s).toNumber();
        var ktmX = cx - (ktmW / 2);
        var ktmY = (148 * s).toNumber();
        var ktmH = isMip ? 16 : 26;
        dc.setColor(navyCard, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(ktmX, ktmY, ktmW, ktmH, ktmH / 2);
        dc.setColor(navyBd, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(ktmX, ktmY, ktmW, ktmH, ktmH / 2);
        dc.setColor(ktmTagCol, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - (50 * s).toNumber(), ktmY + (ktmH / 2), _fSmall, cityParts[:code] as Lang.String, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + (26 * s).toNumber(), ktmY + (ktmH / 2), _fSmall, cityParts[:timeStr] as Lang.String, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Equator Horizon Calendar Ribbon
        var rib = resolveRibbonContent();
        var badge = rib[:badge] as Lang.String;
        var evTitle = rib[:body] as Lang.String;
        var calX = (40 * s).toNumber();
        var calW = width - (80 * s).toNumber();
        var calY = (184 * s).toNumber();
        var calH = isMip ? 24 : 42;
        dc.setColor(navyCard, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(calX, calY, calW, calH, calH / 2);
        dc.setPenWidth(isMip ? 1 : 2);
        dc.setColor(bezelOnly ? navyBd : primaryCol, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(calX, calY, calW, calH, calH / 2);
        dc.setPenWidth(1);
        var cPad = isMip ? 2 : 4;
        var cBadgeW = (78 * s).toNumber();
        dc.setColor(primaryCol, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(calX + cPad, calY + cPad, cBadgeW, calH - (cPad * 2), (calH - (cPad * 2)) / 2);
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(calX + cPad + (cBadgeW / 2), calY + (calH / 2), _fSmall, badge, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(calX + (94 * s).toNumber(), calY + (calH / 2), _fEvent, fitTextToWidth(dc, evTitle, _fEvent, calW - (104 * s).toNumber()), Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        // Lower Navy Chronograph Sub-Dial Deck
        dc.setColor(isMip ? 0xFFFFFF : 0xE2E8F0, Graphics.COLOR_TRANSPARENT);
        dc.drawText((78 * s).toNumber(), (246 * s).toNumber(), _fLabel, m[:trainLabel] as Lang.String, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText((150 * s).toNumber(), (246 * s).toNumber(), _fLabel, "REC", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText((202 * s).toNumber(), (246 * s).toNumber(), _fLabel, "STEPS", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(isMip ? 0xAAAAAA : 0xCBD5E1, Graphics.COLOR_TRANSPARENT);
        dc.drawText((396 * s).toNumber(), (246 * s).toNumber(), _fLabel, m[:targetSummary] as Lang.String, Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(readyValCol, Graphics.COLOR_TRANSPARENT);
        dc.drawText((78 * s).toNumber(), (274 * s).toNumber(), _fValue, m[:trainVal] as Lang.String, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(secondaryCol, Graphics.COLOR_TRANSPARENT);
        dc.drawText((150 * s).toNumber(), (274 * s).toNumber(), _fValue, m[:recText] as Lang.String, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(navyBd, Graphics.COLOR_TRANSPARENT);
        dc.drawLine((116 * s).toNumber(), (238 * s).toNumber(), (116 * s).toNumber(), (286 * s).toNumber());
        dc.setPenWidth(isMip ? 1 : 2);
        dc.setColor(primaryCol, Graphics.COLOR_TRANSPARENT);
        dc.drawLine((186 * s).toNumber(), (236 * s).toNumber(), (186 * s).toNumber(), (288 * s).toNumber());
        dc.setPenWidth(1);

        var sf = selectValueFont(dc, m[:stepStr] as Lang.String, showSparkline ? (122 * s).toNumber() : (190 * s).toNumber());
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText((202 * s).toNumber(), (274 * s).toNumber(), sf, m[:stepStr] as Lang.String, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        var gmtTheme = {
            :bg => navyBot, :track => navyTrack, :muted => 0xFFFFFF, :dim => isMip ? 0xAAAAAA : 0x94A3B8,
            :primary => primaryCol, :crimson => primaryCol, :tipDot => 0xFFFFFF
        };
        if (showSparkline) {
            drawSevenDaySparkline(dc, (368 * s).toNumber(), (286 * s).toNumber(), m[:stepHistory] as Lang.Array<Lang.Number>, m[:stepTarget] as Lang.Number, gmtTheme);
        }

        // Bottom 3 Circular Sub-Dials on Navy Deck
        var r2Cy = (344 * s).toNumber();
        var r2R = (39 * s).toNumber();
        var rOff = (102 * s).toNumber();
        drawCircularRingGauge(dc, [cx - rOff, r2Cy, r2R], m[:blRatio] as Lang.Float, m[:blLabel] as Lang.String, m[:blValue] as Lang.String, [secondaryCol, secondaryCol, false, false, showMicroGauges, 0], gmtTheme);
        drawCircularRingGauge(dc, [cx, r2Cy, r2R], m[:hrRatio] as Lang.Float, "HEART", m[:hrStr] as Lang.String, [primaryCol, 0xFFFFFF, true, false, showMicroGauges, 0], gmtTheme);
        drawCircularRingGauge(dc, [cx + rOff, r2Cy, r2R], m[:brRatio] as Lang.Float, m[:brLabel] as Lang.String, m[:brValue] as Lang.String, [isMip ? 0xFFFFFF : 0xE2E8F0, isMip ? 0xFFFFFF : 0xE2E8F0, false, false, showMicroGauges, 0], gmtTheme);

        drawBottomBatteryBarAt(dc, cx, (height * 0.881).toNumber(), batteryFormat, gmtTheme);
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

    //! Builds the default no-calendar daily summary pill showing Today's Distance and Calories.
    private function buildDailySummaryRibbon() as Lang.Dictionary {
        var actInfo = ActivityMonitor.getInfo();
        var distCm = (actInfo.distance != null) ? (actInfo.distance as Lang.Number) : 0;
        var distStr = (System.getDeviceSettings().distanceUnits == System.UNIT_STATUTE)
            ? ((distCm.toFloat() / 160934.4).format("%.1f") + " mi")
            : ((distCm.toFloat() / 100000.0).format("%.1f") + " km");
        var cals = (actInfo.calories != null) ? (actInfo.calories as Lang.Number) : 0;
        return {
            :badge => "TODAY",
            :body => distStr + " • " + formatNumberWithComma(cals) + " kcal"
        };
    }

    //! Resolves center ribbon content according to CalendarMode (0=Daily Summary, 1=Cal+Fallback, 2=Always Cal, 3=Custom Note).
    private function resolveRibbonContent() as Lang.Dictionary {
        var calMode = getNumberProperty("CalendarMode", 0);
        if (calMode == 3) {
            return {
                :badge => "NOTE",
                :body => getStringProperty("FallbackEventTitle", "Stay Active")
            };
        }
        if (calMode == 1 || calMode == 2) {
            var ev = resolveNextEvent();
            var evTime = ev[:time] as Lang.String;
            if (!evTime.equals("")) {
                return {
                    :badge => evTime,
                    :body => ev[:title] as Lang.String
                };
            }
            if (calMode == 2) {
                return {
                    :badge => "--:--",
                    :body => "No upcoming events"
                };
            }
        }
        return buildDailySummaryRibbon();
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

        var nextEv = _comp.getNextCalendarEvent();
        if (nextEv != null && !(nextEv as Lang.String).equals("")) {
            return {
                :time => nextEv as Lang.String,
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
