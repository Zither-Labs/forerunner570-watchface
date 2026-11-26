using Toybox.Complications;
using Toybox.Lang;
using Toybox.WatchUi;

//! Complications subscriber and touch-to-glance dispatcher for CIQ 4.2+ / 5.0+ devices.
class FR570ComplicationsHelper {

    private var _calendarCompId as Complications.Id? = null;
    private var _recoveryCompId as Complications.Id? = null;
    private var _trainingStatusCompId as Complications.Id? = null;

    private var _nextCalendarEvent as Lang.String? = null;
    private var _recoveryHours as Lang.Number? = null;
    private var _trainingStatusText as Lang.String? = null;

    function initialize() {
    }

    function init() as Void {
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

    function cleanup() as Void {
        if (Toybox has :Complications) {
            Complications.registerComplicationChangeCallback(null);
        }
    }

    function getNextCalendarEvent() as Lang.String? {
        return _nextCalendarEvent;
    }

    function getRecoveryHours() as Lang.Number? {
        return _recoveryHours;
    }

    function getTrainingStatusText() as Lang.String? {
        return _trainingStatusText;
    }

    function createDelegate(view as FR570WatchFaceView) as WatchUi.WatchFaceDelegate? {
        if (WatchUi has :WatchFaceDelegate) {
            return new FR570WatchFaceDelegate(view);
        }
        return null;
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
                return num / 3600;
            }
            if (num > 120) {
                return num / 60;
            }
            return num;
        }
        return null;
    }

    //! Launches the matching native Garmin glance when the user touch-and-holds a zone.
    function launchShortcutAt(
        x as Lang.Number,
        y as Lang.Number,
        w as Lang.Number,
        h as Lang.Number,
        cardStyle as Lang.Number,
        blMode as Lang.Number,
        brMode as Lang.Number
    ) as Lang.Boolean {
        if (!(Toybox has :Complications) || !(Complications has :exitTo)) {
            return false;
        }

        var compType = null as Complications.Type?;
        var blComp = (blMode == 1)
            ? Complications.COMPLICATION_TYPE_CALORIES
            : Complications.COMPLICATION_TYPE_INTENSITY_MINUTES;
        var brComp = Complications.COMPLICATION_TYPE_BODY_BATTERY;
        if (brMode == 1) {
            brComp = Complications.COMPLICATION_TYPE_STRESS;
        } else if (brMode == 2) {
            brComp = Complications.COMPLICATION_TYPE_CALORIES;
        } else if (brMode == 3) {
            brComp = Complications.COMPLICATION_TYPE_FLOORS_CLIMBED;
        }

        if (cardStyle == 4) {
            if (y < (h * 0.14)) {
                compType = Complications.COMPLICATION_TYPE_CURRENT_WEATHER;
            } else if (y < (h * 0.56) && x >= (w * 0.50)) {
                if (y < (h * 0.39)) {
                    compType = (x < (w * 0.69))
                        ? Complications.COMPLICATION_TYPE_TRAINING_STATUS
                        : Complications.COMPLICATION_TYPE_RECOVERY_TIME;
                } else {
                    compType = Complications.COMPLICATION_TYPE_STEPS;
                }
            } else if (y >= (h * 0.56) && y < (h * 0.67)) {
                compType = Complications.COMPLICATION_TYPE_CALENDAR_EVENTS;
            } else if (y >= (h * 0.67) && y < (h * 0.87)) {
                compType = (x < (w * 0.39)) ? blComp : ((x <= (w * 0.61)) ? Complications.COMPLICATION_TYPE_HEART_RATE : brComp);
            } else if (y >= (h * 0.87)) {
                compType = Complications.COMPLICATION_TYPE_BATTERY;
            }
        } else if (cardStyle == 5) {
            if (y < (h * 0.09)) {
                compType = Complications.COMPLICATION_TYPE_CURRENT_WEATHER;
            } else if (y < (h * 0.20)) {
                compType = Complications.COMPLICATION_TYPE_CALENDAR_EVENTS;
            } else if (y >= (h * 0.42) && y < (h * 0.61)) {
                if (x < (w * 0.33)) {
                    compType = Complications.COMPLICATION_TYPE_TRAINING_STATUS;
                } else if (x < (w * 0.50)) {
                    compType = Complications.COMPLICATION_TYPE_RECOVERY_TIME;
                } else {
                    compType = Complications.COMPLICATION_TYPE_STEPS;
                }
            } else if (y >= (h * 0.62) && y < (h * 0.85)) {
                compType = (x < (w * 0.39)) ? blComp : ((x <= (w * 0.61)) ? Complications.COMPLICATION_TYPE_HEART_RATE : brComp);
            } else if (y >= (h * 0.85)) {
                compType = Complications.COMPLICATION_TYPE_BATTERY;
            }
        } else {
            var isGmtD = (cardStyle == 6 || cardStyle == 7);
            var calTop = isGmtD ? (h * 0.40) : (h * 0.34);
            var calBot = isGmtD ? (h * 0.51) : (h * 0.48);
            var r1Bot = isGmtD ? (h * 0.64) : (h * 0.655);
            if (y < (h * 0.14)) {
                compType = Complications.COMPLICATION_TYPE_CURRENT_WEATHER;
            } else if (y >= calTop && y < calBot) {
                compType = Complications.COMPLICATION_TYPE_CALENDAR_EVENTS;
            } else if (y >= calBot && y < r1Bot) {
                if (x < (w * 0.32)) {
                    compType = Complications.COMPLICATION_TYPE_TRAINING_STATUS;
                } else if (x < (w * 0.45)) {
                    compType = Complications.COMPLICATION_TYPE_RECOVERY_TIME;
                } else {
                    compType = Complications.COMPLICATION_TYPE_STEPS;
                }
            } else if (y >= r1Bot && y < (h * 0.84)) {
                compType = (x < (w * 0.39)) ? blComp : ((x <= (w * 0.61)) ? Complications.COMPLICATION_TYPE_HEART_RATE : brComp);
            } else if (y >= (h * 0.84)) {
                compType = Complications.COMPLICATION_TYPE_BATTERY;
            }
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
}
