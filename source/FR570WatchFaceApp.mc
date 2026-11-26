using Toybox.Application;
using Toybox.Application.Properties;
using Toybox.Application.Storage;
using Toybox.Background;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;
using Toybox.WatchUi;

//! Entry point for the FR570 Runner Pro watch face, touch delegate, and background calendar sync.
class FR570WatchFaceApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Lang.Dictionary?) as Void {
    }

    function onStop(state as Lang.Dictionary?) as Void {
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        if (Toybox.System has :ServiceDelegate) {
            try {
                Background.registerForTemporalEvent(new Time.Duration(15 * 60));
            } catch (ex) {
            }
        }
        var view = new FR570WatchFaceView();
        var del = view.createDelegate();
        if (del != null) {
            return [view, del as WatchUi.InputDelegate];
        }
        return [view];
    }

    function getServiceDelegate() as [System.ServiceDelegate] {
        return [new FR570CalendarServiceDelegate()];
    }

    function onBackgroundData(data as Application.PersistableType) as Void {
        if (data instanceof Lang.Dictionary) {
            var dict = data as Lang.Dictionary;
            var timeVal = dict.get("time");
            var titleVal = dict.get("title");
            if (timeVal instanceof Lang.String) {
                Storage.setValue("NextEventTime", timeVal as Lang.String);
            }
            if (titleVal instanceof Lang.String) {
                Storage.setValue("NextEventTitle", titleVal as Lang.String);
            }
            WatchUi.requestUpdate();
        }
    }

    function onSettingsChanged() as Void {
        try {
            var calMode = 0;
            var modeVal = Properties.getValue("CalendarMode");
            if (modeVal instanceof Lang.Number) {
                calMode = modeVal as Lang.Number;
            }
            var url = Properties.getValue("CalendarEndpointUrl");
            if ((calMode != 1 && calMode != 2) || !(url instanceof Lang.String) || (url as Lang.String).equals("")) {
                Storage.setValue("NextEventTime", "");
                Storage.setValue("NextEventTitle", "");
            } else if (Toybox.System has :ServiceDelegate) {
                Background.registerForTemporalEvent(new Time.Duration(5 * 60));
            }
        } catch (ex) {
        }
        WatchUi.requestUpdate();
    }
}
