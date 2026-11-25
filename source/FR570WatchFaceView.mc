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
        var compType = null as Complications.Type?;

        if (y < (h * 0.14)) {
            compType = Complications.COMPLICATION_TYPE_CURRENT_WEATHER;
        } else if (y >= (h * 0.34) && y < (h * 0.48)) {
            compType = Complications.COMPLICATION_TYPE_CALENDAR_EVENTS;
        } else if (y >= (h * 0.48) && y < (h * 0.68)) {
            if (x < (w * 0.32)) {
                compType = Complications.COMPLICATION_TYPE_TRAINING_STATUS;
            } else if (x < (w * 0.45)) {
                compType = Complications.COMPLICATION_TYPE_RECOVERY_TIME;
            } else {
                compType = Complications.COMPLICATION_TYPE_STEPS;
            }
        } else if (y >= (h * 0.68) && y < (h * 0.84)) {
            if (x < (w * 0.39)) {
                compType = Complications.COMPLICATION_TYPE_INTENSITY_MINUTES;
            } else if (x <= (w * 0.61)) {
                compType = Complications.COMPLICATION_TYPE_HEART_RATE;
            } else {
                compType = Complications.COMPLICATION_TYPE_BODY_BATTERY;
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
        var cx = width / 2;
        var cy = height / 2;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var clockTime = System.getClockTime();
        var worldCityIndex = getNumberProperty("WorldCity", 0);
        var stepTargetMode = getNumberProperty("StepTargetMode", 0);
        var readinessMode = getNumberProperty("ReadinessMode", 0);
        var accentColor = getNumberProperty("AccentColor", 0x10B981);
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

        var timeBottomY = drawTimeBlock(dc, cx, width, height, clockTime, accentColor, showSeconds);
        var pillBottomY = drawWorldClockPill(dc, cx, width, timeBottomY, worldCityIndex);
        var cardBottomY = drawNextEventCard(dc, cx, width, pillBottomY, accentColor);

        drawDataPodGrid(
            dc, cx, width, height, cardBottomY,
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

    //! Draws 60-tick chronograph chapter ring, dual outer side arcs, and glowing tip dots.
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
        drawChronographTicks(dc, cx, cy, (width / 2) - 2);

        var penWidth = (width >= 430) ? 5 : 4;
        var radius = (width / 2) - 11;
        dc.setPenWidth(penWidth);

        // Left Arc (Steps vs 7D Target): 235 deg (bottom-left) clockwise to 125 deg (top-left).
        dc.setColor(0x162032, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, 235, 125);

        var stepRatio = clampRatio(steps.toFloat() / stepTarget.toFloat());
        var stepSweep = (110.0 * stepRatio).toNumber();
        if (stepSweep >= 1) {
            var stepTipDeg = 235 - stepSweep;
            dc.setColor(accentColor, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, 235, stepTipDeg);
            drawArcTipDot(dc, cx, cy, radius, stepTipDeg, accentColor);
        }

        // Right Arc (Weekly Intensity Minutes): 305 deg (bottom-right) counter-clockwise to 55 deg (top-right).
        dc.setColor(0x162032, Graphics.COLOR_TRANSPARENT);
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
            drawArcTipDot(dc, cx, cy, radius, endDeg, 0xF59E0B);
        }

        dc.setPenWidth(1);
    }

    //! Draws 60 radial minute/second chapter ticks along the outer bezel perimeter.
    private function drawChronographTicks(
        dc as Graphics.Dc,
        cx as Lang.Number,
        cy as Lang.Number,
        outerR as Lang.Number
    ) as Void {
        for (var i = 0; i < 60; i++) {
            var isMajor = (i % 5) == 0;
            var tickLen = isMajor ? 7 : 4;
            var innerR = outerR - tickLen;
            var rad = (i * 6.0 * Math.PI) / 180.0;
            var cosVal = Math.cos(rad);
            var sinVal = Math.sin(rad);

            var x1 = cx + (innerR * cosVal).toNumber();
            var y1 = cy - (innerR * sinVal).toNumber();
            var x2 = cx + (outerR * cosVal).toNumber();
            var y2 = cy - (outerR * sinVal).toNumber();

            dc.setPenWidth(isMajor ? 2 : 1);
            dc.setColor(isMajor ? 0x475569 : 0x1E293B, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(x1, y1, x2, y2);
        }
        dc.setPenWidth(1);
    }

    //! Draws a glowing dot marker at the active tip of a progress arc.
    private function drawArcTipDot(
        dc as Graphics.Dc,
        cx as Lang.Number,
        cy as Lang.Number,
        radius as Lang.Number,
        deg as Lang.Number,
        color as Lang.Number
    ) as Void {
        var rad = (deg.toFloat() * Math.PI) / 180.0;
        var dx = cx + (radius * Math.cos(rad)).toNumber();
        var dy = cy - (radius * Math.sin(rad)).toNumber();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(dx, dy, 4);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(dx, dy, 3);
    }

    //! Draws 2-line Weather & Forecast header with vector weather icon, temp/feels-like, hi/lo, precip, humidity.
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
                if (cond.feelsLikeTemperature != null) {
                    line1 = line1 + " FL " + formatTempShort(cond.feelsLikeTemperature as Lang.Number or Lang.Float);
                }

                var fcst = (todayFcst != null) ? (todayFcst as Weather.DailyForecast) : null;
                var hiVal = (cond.highTemperature != null) ? cond.highTemperature
                    : ((fcst != null) ? fcst.highTemperature : null);
                var loVal = (cond.lowTemperature != null) ? cond.lowTemperature
                    : ((fcst != null) ? fcst.lowTemperature : null);
                var precip = (cond.precipitationChance != null) ? cond.precipitationChance
                    : ((fcst != null) ? fcst.precipitationChance : null);
                var hum = cond.relativeHumidity;

                if (hiVal != null && loVal != null) {
                    line2 = "H" + formatTempShort(hiVal as Lang.Number or Lang.Float)
                        + "/L" + formatTempShort(loVal as Lang.Number or Lang.Float);
                } else {
                    line2 = getConditionLabel(condCode);
                }
                if (precip != null) {
                    line2 = line2 + " • P" + (precip as Lang.Number).format("%d") + "%";
                }
                if (hum != null) {
                    line2 = line2 + " • H" + (hum as Lang.Number).format("%d") + "%";
                }
            }
        }

        var line1Fitted = fitTextToWidth(dc, line1, Graphics.FONT_XTINY, (width * 0.58).toNumber());
        var line1W = dc.getTextWidthInPixels(line1Fitted, Graphics.FONT_XTINY);
        var line1Y = (height * 0.055).toNumber();
        var iconW = (condCode != null) ? 20 : 0;
        var start1X = cx - ((line1W + iconW) / 2);

        if (condCode != null) {
            drawWeatherIcon(dc, start1X + 8, line1Y + (dc.getFontHeight(Graphics.FONT_XTINY) / 2), condCode);
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            start1X + iconW,
            line1Y,
            Graphics.FONT_XTINY,
            line1Fitted,
            Graphics.TEXT_JUSTIFY_LEFT
        );

        if (!line2.equals("")) {
            dc.setColor(0x94A3B8, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                cx,
                (height * 0.102).toNumber(),
                Graphics.FONT_XTINY,
                fitTextToWidth(dc, line2, Graphics.FONT_XTINY, (width * 0.68).toNumber()),
                Graphics.TEXT_JUSTIFY_CENTER
            );
        }
    }

    //! Draws crisp multi-color vector weather iconography (sun, cloud, rain, thunder, snow).
    private function drawWeatherIcon(
        dc as Graphics.Dc,
        cx as Lang.Number,
        cy as Lang.Number,
        condCode as Weather.Condition?
    ) as Void {
        if (condCode == null) {
            return;
        }
        var code = condCode as Weather.Condition;

        if (code == Weather.CONDITION_CLEAR || code == Weather.CONDITION_MOSTLY_CLEAR) {
            dc.setColor(0xF59E0B, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx, cy, 4);
            dc.drawLine(cx - 7, cy, cx - 5, cy);
            dc.drawLine(cx + 5, cy, cx + 7, cy);
            dc.drawLine(cx, cy - 7, cx, cy - 5);
            dc.drawLine(cx, cy + 5, cx, cy + 7);
            return;
        }

        if (code == Weather.CONDITION_PARTLY_CLOUDY || code == Weather.CONDITION_PARTLY_CLEAR) {
            dc.setColor(0xF59E0B, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx + 3, cy - 3, 4);
            dc.setColor(0xE2E8F0, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx - 2, cy + 1, 4);
            dc.fillCircle(cx + 2, cy + 2, 3);
            dc.fillRectangle(cx - 5, cy + 1, 9, 4);
            return;
        }

        if (code == Weather.CONDITION_THUNDERSTORMS || code == Weather.CONDITION_SCATTERED_THUNDERSTORMS) {
            dc.setColor(0x94A3B8, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx - 2, cy - 2, 4);
            dc.fillCircle(cx + 2, cy - 1, 3);
            dc.fillRectangle(cx - 5, cy - 2, 10, 4);
            dc.setColor(0xF59E0B, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[cx, cy + 1], [cx - 3, cy + 5], [cx, cy + 5], [cx - 1, cy + 8], [cx + 3, cy + 4], [cx, cy + 4]]);
            return;
        }

        var isRain = (code == Weather.CONDITION_RAIN || code == Weather.CONDITION_LIGHT_RAIN
            || code == Weather.CONDITION_HEAVY_RAIN || code == Weather.CONDITION_SHOWERS
            || code == Weather.CONDITION_SCATTERED_SHOWERS || code == Weather.CONDITION_CHANCE_OF_SHOWERS
            || code == Weather.CONDITION_LIGHT_SHOWERS || code == Weather.CONDITION_HEAVY_SHOWERS);

        dc.setColor(isRain ? 0x94A3B8 : 0xCBD5E1, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx - 2, cy - 1, 4);
        dc.fillCircle(cx + 2, cy, 3);
        dc.fillRectangle(cx - 5, cy - 1, 10, 4);

        if (isRain) {
            dc.setColor(0x38BDF8, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(cx - 3, cy + 4, cx - 4, cy + 7);
            dc.drawLine(cx, cy + 4, cx - 1, cy + 7);
            dc.drawLine(cx + 3, cy + 4, cx + 2, cy + 7);
        }
    }

    //! Draws split Hours (white), muted Colon, Accent Minutes, AM/PM, and seconds pill badge.
    private function drawTimeBlock(
        dc as Graphics.Dc,
        cx as Lang.Number,
        width as Lang.Number,
        height as Lang.Number,
        clockTime as System.ClockTime,
        accentColor as Lang.Number,
        showSeconds as Lang.Boolean
    ) as Lang.Number {
        var parts = formatClockParts(clockTime);
        var hourStr = parts[:hour] as Lang.String;
        var minStr = parts[:min] as Lang.String;
        var amPm = parts[:amPm] as Lang.String;

        var fullTime = hourStr + ":" + minStr;
        var maxMainWidth = showSeconds ? (width * 0.60).toNumber() : (width * 0.70).toNumber();
        var font = selectTimeFont(dc, fullTime, maxMainWidth);
        var fontHeight = dc.getFontHeight(font);

        var hourW = dc.getTextWidthInPixels(hourStr, font);
        var colonW = dc.getTextWidthInPixels(":", font);
        var minW = dc.getTextWidthInPixels(minStr, font);
        var totalMainWidth = hourW + colonW + minW;

        var secBadgeW = showSeconds ? 26 : 0;
        var rightColW = showSeconds ? (secBadgeW + 8) : (!amPm.equals("") ? 28 : 0);

        var startX = cx - ((totalMainWidth + rightColW) / 2);
        var timeY = (height * 0.138).toNumber();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(startX, timeY, font, hourStr, Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(0x64748B, Graphics.COLOR_TRANSPARENT);
        dc.drawText(startX + hourW, timeY, font, ":", Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(accentColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(startX + hourW + colonW, timeY, font, minStr, Graphics.TEXT_JUSTIFY_LEFT);

        var rightX = startX + totalMainWidth + 8;
        if (!amPm.equals("")) {
            dc.setColor(0x94A3B8, Graphics.COLOR_TRANSPARENT);
            dc.drawText(rightX, timeY + (fontHeight * 0.14).toNumber(), Graphics.FONT_XTINY, amPm, Graphics.TEXT_JUSTIFY_LEFT);
        }
        if (showSeconds) {
            var secStr = clockTime.sec.format("%02d");
            var badgeY = timeY + (fontHeight * 0.50).toNumber();
            var badgeH = 18;
            dc.setColor(0x0F172A, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(rightX, badgeY, secBadgeW, badgeH, 5);
            dc.setColor(0x1E293B, Graphics.COLOR_TRANSPARENT);
            dc.drawRoundedRectangle(rightX, badgeY, secBadgeW, badgeH, 5);
            dc.setColor(accentColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                rightX + (secBadgeW / 2),
                badgeY + (badgeH / 2),
                Graphics.FONT_XTINY,
                secStr,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
        }

        return timeY + fontHeight;
    }

    //! Draws a sleek two-tone World Clock capsule (City badge on left + time on right).
    private function drawWorldClockPill(
        dc as Graphics.Dc,
        cx as Lang.Number,
        width as Lang.Number,
        prevBottomY as Lang.Number,
        worldCityIndex as Lang.Number
    ) as Lang.Number {
        var cityParts = getWorldCityParts(worldCityIndex);
        var code = cityParts[:code] as Lang.String;
        var timeStr = cityParts[:timeStr] as Lang.String;

        var pillW = (width * 0.38).toNumber();
        var pillH = 20;
        var pillX = cx - (pillW / 2);
        var pillY = prevBottomY + 2;
        var badgeW = 46;

        dc.setColor(0x0F172A, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(pillX, pillY, pillW, pillH, 10);

        dc.setColor(0x1E293B, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(pillX, pillY, badgeW, pillH, 10);
        dc.fillRectangle(pillX + badgeW - 6, pillY, 6, pillH);

        dc.setColor(0x1E293B, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(pillX, pillY, pillW, pillH, 10);

        dc.setColor(0xF59E0B, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            pillX + (badgeW / 2),
            pillY + (pillH / 2),
            Graphics.FONT_XTINY,
            code,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );

        var rightCenterX = pillX + badgeW + ((pillW - badgeW) / 2);
        dc.setColor(0x7DD3FC, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            rightCenterX,
            pillY + (pillH / 2),
            Graphics.FONT_XTINY,
            timeStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );

        return pillY + pillH;
    }

    //! Draws a sculpted Next Calendar Event Bento Card with a left glowing accent bar.
    private function drawNextEventCard(
        dc as Graphics.Dc,
        cx as Lang.Number,
        width as Lang.Number,
        prevBottomY as Lang.Number,
        accentColor as Lang.Number
    ) as Lang.Number {
        var cardW = (width * 0.76).toNumber();
        var cardH = 42;
        var cardX = cx - (cardW / 2);
        var cardY = prevBottomY + 6;

        dc.setColor(0x0F172A, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cardX, cardY, cardW, cardH, 9);
        dc.setColor(0x1E293B, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(cardX, cardY, cardW, cardH, 9);

        // Glowing 4px vertical accent bar on the left edge
        dc.setColor(accentColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cardX + 4, cardY + 6, 4, cardH - 12, 2);

        var ev = resolveNextEvent();
        var evTime = ev[:time] as Lang.String;
        var evTitle = ev[:title] as Lang.String;

        var leftLabel = !evTime.equals("") ? "NEXT" : "CALENDAR";
        var rightTime = !evTime.equals("") ? evTime : "--:--";
        var bodyStr = !evTime.equals("") ? evTitle : "No upcoming events";

        var textX = cardX + 14;
        var maxBodyW = cardW - 22;

        dc.setColor(0x94A3B8, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            textX,
            cardY + 11,
            Graphics.FONT_XTINY,
            leftLabel,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
        );

        dc.setColor(accentColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            cardX + cardW - 10,
            cardY + 11,
            Graphics.FONT_XTINY,
            rightTime,
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER
        );

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            textX,
            cardY + 29,
            Graphics.FONT_XTINY,
            fitTextToWidth(dc, bodyStr, Graphics.FONT_XTINY, maxBodyW),
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
        );

        return cardY + cardH;
    }

    //! Draws Bento data grid: Row 1 = Readiness+Rec & Steps+Sparkline Hero; Row 2 = Intensity, Heart, Body Batt.
    private function drawDataPodGrid(
        dc as Graphics.Dc,
        cx as Lang.Number,
        width as Lang.Number,
        height as Lang.Number,
        prevBottomY as Lang.Number,
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
        var gridW = (width * 0.76).toNumber();
        var leftX = cx - (gridW / 2);
        var gap = 8;

        var row1Y = prevBottomY + 7;
        var row1H = (height * 0.162).toNumber();

        // --- Row 1 Left Card (42%): Readiness + Recovery + 4-Segment Gauge ---
        var w1 = ((gridW - gap) * 42) / 100;
        dc.setColor(0x0F172A, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(leftX, row1Y, w1, row1H, 9);
        dc.setColor(0x1E293B, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(leftX, row1Y, w1, row1H, 9);

        var trainVal = "--";
        var trainLabel = "READY";
        var readyScore = computeReadinessScore(bodyBattery, stress, _recoveryHours);
        if (readinessMode == 1) {
            trainLabel = "STATUS";
            trainVal = formatTrainingStatusShort(_trainingStatusText);
        } else if (readyScore != null) {
            trainVal = (readyScore as Lang.Number).format("%d");
        }
        var recText = (_recoveryHours != null) ? ((_recoveryHours as Lang.Number).format("%d") + "h") : "--h";

        dc.setColor(0x94A3B8, Graphics.COLOR_TRANSPARENT);
        dc.drawText(leftX + 9, row1Y + 11, Graphics.FONT_XTINY, trainLabel, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(0xA78BFA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(leftX + w1 - 9, row1Y + 11, Graphics.FONT_XTINY, recText, Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(accentColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            leftX + 10,
            row1Y + (row1H / 2) + 2,
            Graphics.FONT_TINY,
            fitTextToWidth(dc, trainVal, Graphics.FONT_TINY, w1 - 20),
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
        );

        var readySegs = (readyScore != null) ? (((readyScore as Lang.Number) + 24) / 25) : 0;
        drawSegmentedBar(dc, leftX + 9, row1Y + row1H - 9, w1 - 18, 4, readySegs, [0xF43F5E, 0xF59E0B, 0x10B981, 0x38BDF8]);

        // --- Row 1 Right Hero Card (58%): Steps + 7D Target + Sparkline + Progress Bar ---
        var x2 = leftX + w1 + gap;
        var w2 = gridW - w1 - gap;
        dc.setColor(0x0F172A, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x2, row1Y, w2, row1H, 9);
        dc.setColor(0x1E293B, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(x2, row1Y, w2, row1H, 9);

        var targetTag = (targetMode == 3) ? "G " : "7D ";
        dc.setColor(0x94A3B8, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x2 + 9, row1Y + 11, Graphics.FONT_XTINY, "STEPS", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(0x64748B, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            x2 + w2 - 9,
            row1Y + 11,
            Graphics.FONT_XTINY,
            targetTag + formatNumberWithComma(stepTarget),
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER
        );

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            x2 + 9,
            row1Y + (row1H / 2) + 2,
            Graphics.FONT_TINY,
            fitTextToWidth(dc, formatNumberWithComma(steps), Graphics.FONT_TINY, w2 - 66),
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
        );

        drawSevenDaySparkline(dc, x2 + w2 - 33, row1Y + row1H - 15, stepHistory, stepTarget, accentColor);

        var stepRatio = clampRatio(steps.toFloat() / stepTarget.toFloat());
        drawHorizontalProgressBar(dc, x2 + 9, row1Y + row1H - 9, w2 - 18, 4, stepRatio, accentColor);

        // --- Row 2: 3 Equal Mini Bento Pods (Intensity, Heart Rate, Body Battery) ---
        var row2Y = row1Y + row1H + 7;
        var row2H = (height * 0.145).toNumber();
        var podW = (gridW - (2 * gap)) / 3;

        // Pod 1: Intensity Minutes
        var px1 = leftX;
        dc.setColor(0x0F172A, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(px1, row2Y, podW, row2H, 9);
        dc.setColor(0x1E293B, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(px1, row2Y, podW, row2H, 9);

        dc.setColor(0x94A3B8, Graphics.COLOR_TRANSPARENT);
        dc.drawText(px1 + (podW / 2), row2Y + 11, Graphics.FONT_XTINY, "INTENS", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var intText = intMins.format("%d") + "/" + intGoal.format("%d");
        dc.setColor(0xF59E0B, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            px1 + (podW / 2),
            row2Y + (row2H / 2) + 1,
            Graphics.FONT_XTINY,
            fitTextToWidth(dc, intText, Graphics.FONT_XTINY, podW - 10),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
        drawHorizontalProgressBar(dc, px1 + 8, row2Y + row2H - 9, podW - 16, 4, clampRatio(intMins.toFloat() / intGoal.toFloat()), 0xF59E0B);

        // Pod 2: Heart Rate + Vector Heart Icon + 5-Zone Strip
        var px2 = leftX + podW + gap;
        dc.setColor(0x0F172A, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(px2, row2Y, podW, row2H, 9);
        dc.setColor(0x1E293B, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(px2, row2Y, podW, row2H, 9);

        dc.setColor(0x94A3B8, Graphics.COLOR_TRANSPARENT);
        dc.drawText(px2 + (podW / 2), row2Y + 11, Graphics.FONT_XTINY, "HEART", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var hr = getHeartRate();
        var hrStr = (hr != null) ? (hr as Lang.Number).format("%d") : "--";
        var hrTextW = dc.getTextWidthInPixels(hrStr, Graphics.FONT_TINY);
        var hrStartX = px2 + (podW / 2) - ((hrTextW + 16) / 2);
        var hrMidY = row2Y + (row2H / 2) + 1;
        drawHeartIcon(dc, hrStartX + 5, hrMidY - 1, 0xF43F5E);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(hrStartX + 14, hrMidY, Graphics.FONT_TINY, hrStr, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        var hrZone = 1;
        if (hr != null) {
            var hVal = hr as Lang.Number;
            hrZone = (hVal >= 165) ? 5 : ((hVal >= 145) ? 4 : ((hVal >= 125) ? 3 : ((hVal >= 100) ? 2 : 1)));
        }
        drawSegmentedBar(dc, px2 + 8, row2Y + row2H - 9, podW - 16, 4, hrZone, [0x64748B, 0x38BDF8, 0x10B981, 0xF59E0B, 0xF43F5E]);

        // Pod 3: Body Battery + Ice Cyan Charge Bar
        var px3 = leftX + (2 * (podW + gap));
        dc.setColor(0x0F172A, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(px3, row2Y, podW, row2H, 9);
        dc.setColor(0x1E293B, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(px3, row2Y, podW, row2H, 9);

        dc.setColor(0x94A3B8, Graphics.COLOR_TRANSPARENT);
        dc.drawText(px3 + (podW / 2), row2Y + 11, Graphics.FONT_XTINY, "BODY BAT", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var bbStr = (bodyBattery != null) ? ((bodyBattery as Lang.Number).format("%d") + "%") : "--";
        var bbRatio = (bodyBattery != null) ? clampRatio((bodyBattery as Lang.Number).toFloat() / 100.0) : 0.0;
        dc.setColor(0x38BDF8, Graphics.COLOR_TRANSPARENT);
        dc.drawText(px3 + (podW / 2), row2Y + (row2H / 2) + 1, Graphics.FONT_TINY, bbStr, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        drawHorizontalProgressBar(dc, px3 + 8, row2Y + row2H - 9, podW - 16, 4, bbRatio, 0x38BDF8);
    }

    private function drawHorizontalProgressBar(
        dc as Graphics.Dc,
        x as Lang.Number,
        y as Lang.Number,
        w as Lang.Number,
        h as Lang.Number,
        ratio as Lang.Float,
        color as Lang.Number
    ) as Void {
        dc.setColor(0x1E293B, Graphics.COLOR_TRANSPARENT);
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
        colors as Lang.Array<Lang.Number>
    ) as Void {
        var count = colors.size();
        var segGap = 2;
        var segW = (w - ((count - 1) * segGap)) / count;
        for (var i = 0; i < count; i++) {
            var sx = x + (i * (segW + segGap));
            dc.setColor((i < activeCount) ? colors[i] : 0x1E293B, Graphics.COLOR_TRANSPARENT);
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
        dc.fillCircle(cx - 2, cy - 2, 3);
        dc.fillCircle(cx + 2, cy - 2, 3);
        dc.fillPolygon([[cx - 5, cy - 1], [cx + 5, cy - 1], [cx, cy + 5]]);
    }

    //! Draws a compact 7-bar sparkline embedded cleanly inside the Steps hero card.
    private function drawSevenDaySparkline(
        dc as Graphics.Dc,
        centerX as Lang.Number,
        baseY as Lang.Number,
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

        var barW = 4;
        var barGap = 2;
        var maxH = 18;
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
    }

    //! Draws a sleek segmented battery gauge, percentage, and estimated days remaining at 6 o'clock.
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
            fillColor = 0xF43F5E;
        } else if (pct <= 20) {
            fillColor = 0xF59E0B;
        }

        var daysSuffix = "";
        if ((stats has :batteryInDays) && stats.batteryInDays != null) {
            var daysNum = (stats.batteryInDays as Lang.Number or Lang.Float).toNumber();
            if (daysNum >= 0) {
                daysSuffix = " • " + daysNum.format("%d") + "d";
            }
        }

        var battW = 24;
        var battH = 12;
        var battY = (height * 0.865).toNumber();
        var labelStr = pct.format("%d") + "%" + daysSuffix;
        var textW = dc.getTextWidthInPixels(labelStr, Graphics.FONT_XTINY);
        var totalW = battW + 10 + textW;
        var startX = cx - (totalW / 2);

        dc.setColor(0x94A3B8, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(startX, battY, battW, battH, 3);
        dc.fillRectangle(startX + battW, battY + 3, 2, battH - 6);

        var activeBlocks = (pct + 24) / 25;
        var blockW = 4;
        var blockGap = 1;
        for (var b = 0; b < 4; b++) {
            var bx = startX + 2 + (b * (blockW + blockGap));
            dc.setColor((b < activeBlocks) ? fillColor : 0x1E293B, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(bx, battY + 2, blockW, battH - 4);
        }

        dc.setColor(0x94A3B8, Graphics.COLOR_TRANSPARENT);
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

    //! Selects the largest numeric font that fits within maxWidth pixels.
    private function selectTimeFont(
        dc as Graphics.Dc,
        sampleText as Lang.String,
        maxWidth as Lang.Number
    ) as Graphics.FontType {
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
