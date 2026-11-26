using Toybox.Lang;
using Toybox.WatchUi;

//! Stub helper for CIQ 3.3 MIP devices without Complications or touchscreen (e.g. Forerunner 945 / 945 LTE).
class FR570ComplicationsHelper {

    function initialize() {
    }

    function init() as Void {
    }

    function cleanup() as Void {
    }

    function getNextCalendarEvent() as Lang.String? {
        return null;
    }

    function getRecoveryHours() as Lang.Number? {
        return null;
    }

    function getTrainingStatusText() as Lang.String? {
        return null;
    }

    function createDelegate(view as FR570WatchFaceView) as WatchUi.InputDelegate? {
        return null;
    }

    function launchShortcutAt(
        x as Lang.Number,
        y as Lang.Number,
        w as Lang.Number,
        h as Lang.Number,
        cardStyle as Lang.Number,
        blMode as Lang.Number,
        brMode as Lang.Number
    ) as Lang.Boolean {
        return false;
    }
}
