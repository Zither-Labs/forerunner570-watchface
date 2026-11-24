using Toybox.Activity;
using Toybox.ActivityMonitor;
using Toybox.Application.Properties;
using Toybox.Application.Storage;
using Toybox.Complications;
using Toybox.Graphics;
using Toybox.Lang;
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
    private var _isSleeping as Lang.Boolean = false;
    private var _burnInOffsetX as Lang.Number = 0;
    private var _burnInOffsetY as Lang.Number = 0;

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
        var cx = w / 2;
        var colHalf = (w * 0.13).toNumber();
        var compType = null as Complications.Type?;

        if (y < (h * 0.175)) {
            compType = Complications.COMPLICATION_TYPE_CURRENT_WEATHER;
        } else if (y >= (h * 0.40) && y < (h * 0.54)) {
            compType = Complications.COMPLICATION_TYPE_CALENDAR_EVENTS;
        } else if (y >= (h * 0.54) && y < (h * 0.70)) {
            if (x < (cx - colHalf)) {
                compType = Complications.COMPLICATION_TYPE_TRAINING_STATUS;
            } else if (x <= (cx + colHalf)) {
                compType = Complications.COMPLICATION_TYPE_RECOVERY_TIME;
            } else {
                compType = Complications.COMPLICATION_TYPE_STEPS;
            }
        } else if (y >= (h * 0.70) && y < (h * 0.85)) {
            if (x < (cx - colHalf)) {
                compType = Complications.COMPLICATION_TYPE_INTENSITY_MINUTES;
            } else if (x <= (cx + colHalf)) {
                compType = Complications.COMPLICATION_TYPE_HEART_RATE;
            } else {
                compType = Complications.COMPLICATION_TYPE_STEPS;
            }
        } else if (y >= (h * 0.85)) {
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
        var cx = width / 2;
        var cy = height / 2;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var clockTime = System.getClockTime();
        var worldCityIndex = getNumberProperty("WorldCity", 0);
        var stepTargetMode = getNumberProperty("StepTargetMode", 0);
        var readinessMode = getNumberProperty("ReadinessMode", 0);
        var accentColor = getNumberProperty("AccentColor", 0x00FF66);
        var showSeconds = getBooleanProperty("ShowSeconds", true);
        var showRings = getBooleanProperty("ShowStepsArc", true);

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

        if (showRings) {
            drawDualProgressArcs(dc, cx, cy, width, steps, stepTarget, intMins, intGoal, accentColor);
        }

        drawTopWeatherForecastBar(dc, cx, width, height);
        drawTimeBlock(dc, cx, width, height, clockTime, accentColor, showSeconds);
        drawWorldClockPill(dc, cx, width, height, worldCityIndex);
        drawNextEventCard(dc, cx, width, height, accentColor);
        drawDataPodGrid(
            dc, cx, width, height,
            steps, stepTarget, stepTargetMode, stepHistory,
            intMins, intGoal, bodyBattery, stress,
            readinessMode, accentColor
        );
        drawBottomBatteryBar(dc, cx, height, width, accentColor);
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
        var fitted = fitTextToWidth(dc, evSummary, Graphics.FONT_XTINY, (width * 0.72).toNumber());
        dc.drawText(
            drawX,
            drawY + (fontH / 2) + 20,
            Graphics.FONT_XTINY,
            fitted,
            Graphics.TEXT_JUSTIFY_CENTER
        );
    }

    //! Draws dual outer side arcs: Left = Steps vs 7D Target %, Right = Weekly Intensity Minutes %.
    private function drawDualProgressArcs(
        dc as Graphics.Dc,
        cx as Lang.Number,
        cy as Lang.Number,
        width as Lang.Number,
        steps as Lang.Number,
        stepTarget as Lang.Number,
        intMins as Lang.Number,
        intGoal as Lang.Number,
        accentColor as Lang.Number
    ) as Void {
        var penWidth = (width >= 430) ? 8 : 6;
        var radius = (width / 2) - (penWidth / 2) - 4;
        dc.setPenWidth(penWidth);

        // Left Arc (Steps vs 7D Target): 235 deg (bottom-left) clockwise to 125 deg (top-left).
        dc.setColor(0x1B222A, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, 235, 125);

        var stepRatio = clampRatio(steps.toFloat() / stepTarget.toFloat());
        var stepSweep = (110.0 * stepRatio).toNumber();
        if (stepSweep >= 1) {
            dc.setColor(accentColor, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, 235, 235 - stepSweep);
        }

        // Right Arc (Weekly Intensity Minutes): 305 deg (bottom-right) counter-clockwise to 55 deg (top-right).
        dc.setColor(0x1B222A, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, radius, Graphics.ARC_COUNTER_CLOCKWISE, 305, 55);

        var intRatio = clampRatio(intMins.toFloat() / intGoal.toFloat());
        var intSweep = (110.0 * intRatio).toNumber();
        if (intSweep >= 1) {
            var endDeg = 305 + intSweep;
            if (endDeg >= 360) {
                endDeg -= 360;
            }
            dc.setColor(0xF59E0B, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, radius, Graphics.ARC_COUNTER_CLOCKWISE, 305, endDeg);
        }

        dc.setPenWidth(1);
    }

    //! Draws 2-line Weather & Forecast header: Date + Temp (Feels Like), and Forecast + Hi/Lo + Precip + Humidity.
    private function drawTopWeatherForecastBar(
        dc as Graphics.Dc,
        cx as Lang.Number,
        width as Lang.Number,
        height as Lang.Number
    ) as Void {
        var today = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var mon = (today.month != null) ? (today.month as Lang.String).toUpper() : "";
        var day = (today.day != null) ? (today.day as Lang.Number).format("%d") : "";
        var line1 = mon + " " + day;
        var line2 = "";

        if (Toybox has :Weather) {
            var cond = Weather.getCurrentConditions();
            var dailyArr = (Weather has :getDailyForecast) ? Weather.getDailyForecast() : null;
            var todayFcst = (dailyArr != null && dailyArr.size() > 0) ? dailyArr[0] : null;

            if (cond != null) {
                if (cond.temperature != null) {
                    line1 = line1 + " • " + formatTempShort(cond.temperature as Lang.Number or Lang.Float);
                }
                if (cond.feelsLikeTemperature != null) {
                    line1 = line1 + " FL" + formatTempShort(cond.feelsLikeTemperature as Lang.Number or Lang.Float);
                }

                var fcst = (todayFcst != null) ? (todayFcst as Weather.DailyForecast) : null;
                var condCode = cond.condition;
                var condLabel = getConditionLabel(condCode);
                var hiVal = (cond.highTemperature != null) ? cond.highTemperature
                    : ((fcst != null) ? fcst.highTemperature : null);
                var loVal = (cond.lowTemperature != null) ? cond.lowTemperature
                    : ((fcst != null) ? fcst.lowTemperature : null);
                var precip = (cond.precipitationChance != null) ? cond.precipitationChance
                    : ((fcst != null) ? fcst.precipitationChance : null);
                var hum = cond.relativeHumidity;

                line2 = condLabel;
                if (hiVal != null && loVal != null) {
                    line2 = line2 + " H" + formatTempBare(hiVal as Lang.Number or Lang.Float)
                        + "/L" + formatTempBare(loVal as Lang.Number or Lang.Float);
                }
                if (precip != null) {
                    line2 = line2 + " • P" + (precip as Lang.Number).format("%d") + "%";
                }
                if (hum != null) {
                    line2 = line2 + " H" + (hum as Lang.Number).format("%d") + "%";
                }
            }
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            cx,
            (height * 0.075).toNumber(),
            Graphics.FONT_XTINY,
            fitTextToWidth(dc, line1, Graphics.FONT_XTINY, (width * 0.48).toNumber()),
            Graphics.TEXT_JUSTIFY_CENTER
        );

        if (!line2.equals("")) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                cx,
                (height * 0.125).toNumber(),
                Graphics.FONT_XTINY,
                fitTextToWidth(dc, line2, Graphics.FONT_XTINY, (width * 0.62).toNumber()),
                Graphics.TEXT_JUSTIFY_CENTER
            );
        }
    }

    //! Draws split Hours (white) and Minutes (accent), with optional seconds and AM/PM.
    private function drawTimeBlock(
        dc as Graphics.Dc,
        cx as Lang.Number,
        width as Lang.Number,
        height as Lang.Number,
        clockTime as System.ClockTime,
        accentColor as Lang.Number,
        showSeconds as Lang.Boolean
    ) as Void {
        var parts = formatClockParts(clockTime);
        var hourStr = parts[:hour] as Lang.String;
        var minStr = parts[:min] as Lang.String;
        var amPm = parts[:amPm] as Lang.String;

        var fullTime = hourStr + ":" + minStr;
        var maxMainWidth = showSeconds ? (width * 0.64).toNumber() : (width * 0.74).toNumber();
        var font = selectTimeFont(dc, fullTime, maxMainWidth);
        var fontHeight = dc.getFontHeight(font);

        var hourColon = hourStr + ":";
        var hourColonWidth = dc.getTextWidthInPixels(hourColon, font);
        var minWidth = dc.getTextWidthInPixels(minStr, font);
        var totalMainWidth = hourColonWidth + minWidth;

        var secWidth = 0;
        var secStr = clockTime.sec.format("%02d");
        if (showSeconds) {
            secWidth = dc.getTextWidthInPixels(secStr, Graphics.FONT_XTINY) + 6;
        }

        var startX = cx - ((totalMainWidth + secWidth) / 2);
        var timeY = (height * 0.175).toNumber();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(startX, timeY, font, hourColon, Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(accentColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(startX + hourColonWidth, timeY, font, minStr, Graphics.TEXT_JUSTIFY_LEFT);

        var rightX = startX + totalMainWidth + 6;
        if (!amPm.equals("")) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(rightX, timeY + (fontHeight * 0.16).toNumber(), Graphics.FONT_XTINY, amPm, Graphics.TEXT_JUSTIFY_LEFT);
        }
        if (showSeconds) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(rightX, timeY + (fontHeight * 0.50).toNumber(), Graphics.FONT_XTINY, secStr, Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    //! Draws a centered World Clock pill (Kathmandu UTC+5:45 default) beneath the time.
    private function drawWorldClockPill(
        dc as Graphics.Dc,
        cx as Lang.Number,
        width as Lang.Number,
        height as Lang.Number,
        worldCityIndex as Lang.Number
    ) as Void {
        var worldText = getFormattedWorldTime(worldCityIndex);
        var pillW = (width * 0.44).toNumber();
        var pillH = 22;
        var pillX = cx - (pillW / 2);
        var pillY = (height * 0.345).toNumber();

        dc.setColor(0x141B23, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(pillX, pillY, pillW, pillH, 10);
        dc.setColor(0x38BDF8, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(pillX, pillY, pillW, pillH, 10);
        dc.setColor(0x7DD3FC, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            cx,
            pillY + (pillH / 2),
            Graphics.FONT_XTINY,
            worldText,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }

    //! Draws a dedicated Next Calendar Event Card showing Start Time (Line 1) and Event Title (Line 2).
    private function drawNextEventCard(
        dc as Graphics.Dc,
        cx as Lang.Number,
        width as Lang.Number,
        height as Lang.Number,
        accentColor as Lang.Number
    ) as Void {
        var cardW = (width * 0.76).toNumber();
        var cardH = (height * 0.132).toNumber();
        var cardX = cx - (cardW / 2);
        var cardY = (height * 0.41).toNumber();

        dc.setColor(0x131922, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cardX, cardY, cardW, cardH, 12);
        dc.setColor(accentColor, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(cardX, cardY, cardW, cardH, 12);

        var ev = resolveNextEvent();
        var evTime = ev[:time] as Lang.String;
        var evTitle = ev[:title] as Lang.String;

        var headerStr = !evTime.equals("") ? ("NEXT  •  " + evTime) : "CALENDAR";
        var bodyStr = !evTime.equals("") ? evTitle : "No upcoming events";

        var maxTextW = cardW - 20;
        var titleFont = (dc.getFontHeight(Graphics.FONT_XTINY) + dc.getFontHeight(Graphics.FONT_TINY) <= (cardH - 6))
            ? Graphics.FONT_TINY
            : Graphics.FONT_XTINY;

        dc.setColor(accentColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            cx,
            cardY + (cardH * 0.28).toNumber(),
            Graphics.FONT_XTINY,
            fitTextToWidth(dc, headerStr, Graphics.FONT_XTINY, maxTextW),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            cx,
            cardY + (cardH * 0.72).toNumber(),
            titleFont,
            fitTextToWidth(dc, bodyStr, titleFont, maxTextW),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }

    //! Draws 6 pods + 7-day sparkline: Readiness/Status, Recovery, Steps, Intensity, HR/BB, 7D Target.
    private function drawDataPodGrid(
        dc as Graphics.Dc,
        cx as Lang.Number,
        width as Lang.Number,
        height as Lang.Number,
        steps as Lang.Number,
        stepTarget as Lang.Number,
        targetMode as Lang.Number,
        stepHistory as Lang.Array<Lang.Number>,
        intMins as Lang.Number,
        intGoal as Lang.Number,
        bodyBattery as Lang.Number?,
        stress as Lang.Number?,
        readinessMode as Lang.Number,
        accentColor as Lang.Number
    ) as Void {
        var colOffset = (width * 0.23).toNumber();
        var row1Y = (height * 0.575).toNumber();
        var row2Y = (height * 0.735).toNumber();

        // Row 1 Left: Readiness Estimate OR Native Training Status
        var trainVal = "--";
        var trainLabel = "READY";
        if (readinessMode == 1) {
            trainLabel = "STATUS";
            trainVal = formatTrainingStatusShort(_trainingStatusText);
        } else {
            var score = computeReadinessScore(bodyBattery, stress, _recoveryHours);
            trainVal = (score != null) ? (score as Lang.Number).format("%d") : "--";
        }

        // Row 1 Center: Recovery Time Remaining
        var recText = (_recoveryHours != null) ? ((_recoveryHours as Lang.Number).format("%d") + "h") : "--";

        // Row 2 Left: Weekly Intensity Minutes
        var intText = intMins.format("%d") + "/" + intGoal.format("%d");

        // Row 2 Center: Live HR & Body Battery
        var hr = getHeartRate();
        var hrStr = (hr != null) ? (hr as Lang.Number).format("%d") : "--";
        var bbStr = (bodyBattery != null) ? ((bodyBattery as Lang.Number).format("%d") + "%") : "--";
        var hrBbText = hrStr + " / " + bbStr;

        // Row 1 & 2 Right: Steps + 7-Day Sparkline + 7D Target
        var goalMet = (steps >= stepTarget);
        var targetLabel = (targetMode == 3) ? "GOAL" : "7D TARGET";
        var targetColor = goalMet ? accentColor : Graphics.COLOR_LT_GRAY;

        drawPod(dc, cx - colOffset, row1Y, trainVal, trainLabel, accentColor);
        drawPod(dc, cx, row1Y, recText, "RECOVERY", 0xA78BFA);
        drawPod(dc, cx + colOffset, row1Y, formatNumberWithComma(steps), "STEPS", accentColor);

        drawSevenDaySparkline(dc, cx + colOffset, (height * 0.72).toNumber(), width, stepHistory, stepTarget, accentColor);

        drawPod(dc, cx - colOffset, row2Y, intText, "INTENSITY", 0xF59E0B);
        drawPod(dc, cx, row2Y, hrBbText, "HR • BB", 0x38BDF8);
        drawPod(dc, cx + colOffset, row2Y, formatNumberWithComma(stepTarget), targetLabel, targetColor);
    }

    private function drawPod(
        dc as Graphics.Dc,
        x as Lang.Number,
        y as Lang.Number,
        valueText as Lang.String,
        labelText as Lang.String,
        valueColor as Lang.Number
    ) as Void {
        dc.setColor(valueColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_TINY, valueText, Graphics.TEXT_JUSTIFY_CENTER);

        var labelY = y + dc.getFontHeight(Graphics.FONT_TINY) - 4;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, labelY, Graphics.FONT_XTINY, labelText, Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! Draws a compact 7-bar sparkline representing past 7 days against the target line.
    private function drawSevenDaySparkline(
        dc as Graphics.Dc,
        centerX as Lang.Number,
        baseY as Lang.Number,
        width as Lang.Number,
        stepHistory as Lang.Array<Lang.Number>,
        stepTarget as Lang.Number,
        accentColor as Lang.Number
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

        var barW = (width >= 430) ? 6 : 5;
        var barGap = 3;
        var maxH = (width >= 430) ? 14 : 12;
        var totalW = (7 * barW) + (6 * barGap);
        var startX = centerX - (totalW / 2);
        var startSlot = 7 - count;

        for (var d = 0; d < count; d++) {
            var val = stepHistory[d];
            var barH = ((val.toFloat() / maxVal.toFloat()) * maxH).toNumber();
            if (barH < 2 && val > 0) {
                barH = 2;
            }
            var bx = startX + ((startSlot + d) * (barW + barGap));
            dc.setColor((val >= stepTarget) ? accentColor : 0x475569, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(bx, baseY - barH, barW, barH);
        }

        var threshY = baseY - ((stepTarget.toFloat() / maxVal.toFloat()) * maxH).toNumber();
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(startX - 2, threshY, startX + totalW + 2, threshY);
    }

    //! Draws a compact battery gauge, percentage, and estimated days remaining at bottom center.
    private function drawBottomBatteryBar(
        dc as Graphics.Dc,
        cx as Lang.Number,
        height as Lang.Number,
        width as Lang.Number,
        accentColor as Lang.Number
    ) as Void {
        var stats = System.getSystemStats();
        var pct = stats.battery.toNumber();
        if (pct < 0) {
            pct = 0;
        } else if (pct > 100) {
            pct = 100;
        }

        var fillColor = accentColor;
        if (pct <= 10) {
            fillColor = Graphics.COLOR_RED;
        } else if (pct <= 20) {
            fillColor = Graphics.COLOR_YELLOW;
        }

        var daysSuffix = "";
        if ((stats has :batteryInDays) && stats.batteryInDays != null) {
            var daysNum = (stats.batteryInDays as Lang.Number or Lang.Float).toNumber();
            if (daysNum >= 0) {
                daysSuffix = "  •  " + daysNum.format("%d") + "d";
            }
        }

        var battW = (width >= 430) ? 26 : 22;
        var battH = (width >= 430) ? 13 : 11;
        var battY = (height * 0.892).toNumber();
        var labelStr = pct.format("%d") + "%" + daysSuffix;
        var textW = dc.getTextWidthInPixels(labelStr, Graphics.FONT_XTINY);
        var totalW = battW + 8 + textW;
        var startX = cx - (totalW / 2);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(startX, battY, battW, battH);
        dc.fillRectangle(startX + battW, battY + 3, 3, battH - 6);

        var innerMaxW = battW - 4;
        var fillW = ((innerMaxW * pct) / 100);
        if (fillW < 1 && pct > 0) {
            fillW = 1;
        }
        dc.setColor(fillColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(startX + 2, battY + 2, fillW, battH - 4);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            startX + battW + 8,
            battY + (battH / 2),
            Graphics.FONT_XTINY,
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

    //! Computes the selected city's time via UTC offset (supports 45m offsets like Kathmandu).
    private function getFormattedWorldTime(cityIndex as Lang.Number) as Lang.String {
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

        return code + " " + cityInfo.hour.format("%02d") + ":" + cityInfo.min.format("%02d") + dayTag;
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

    //! Selects the largest numeric font that fits within maxWidth pixels.
    private function selectTimeFont(
        dc as Graphics.Dc,
        sampleText as Lang.String,
        maxWidth as Lang.Number
    ) as Graphics.FontType {
        if (dc.getTextWidthInPixels(sampleText, Graphics.FONT_NUMBER_HOT) <= maxWidth) {
            return Graphics.FONT_NUMBER_HOT;
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
