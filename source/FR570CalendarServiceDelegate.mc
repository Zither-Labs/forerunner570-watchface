using Toybox.Application.Properties;
using Toybox.Background;
using Toybox.Communications;
using Toybox.Lang;
using Toybox.System;

//! Background worker that fetches { "time": "HH:MM", "title": "..." } from the user's calendar bridge.
(:background)
class FR570CalendarServiceDelegate extends System.ServiceDelegate {

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        var calMode = 0;
        var url = "";
        try {
            var modeVal = Properties.getValue("CalendarMode");
            if (modeVal instanceof Lang.Number) {
                calMode = modeVal as Lang.Number;
            }
            var val = Properties.getValue("CalendarEndpointUrl");
            if (val instanceof Lang.String) {
                url = val as Lang.String;
            }
        } catch (ex) {
        }

        if ((calMode != 1 && calMode != 2) || url.equals("")) {
            Background.exit(null);
            return;
        }

        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };

        try {
            Communications.makeWebRequest(
                url,
                {},
                options,
                self.method(:onReceiveCalendarJson)
            );
        } catch (ex) {
            Background.exit(null);
        }
    }

    function onReceiveCalendarJson(
        responseCode as Lang.Number,
        data as Lang.Dictionary or Lang.String or Null
    ) as Void {
        if (responseCode == 200 && data instanceof Lang.Dictionary) {
            var dict = data as Lang.Dictionary;
            var eventTime = dict.get("time");
            var eventTitle = dict.get("title");
            var outTime = (eventTime != null) ? eventTime.toString() : "";
            var outTitle = (eventTitle != null) ? eventTitle.toString() : "";
            Background.exit({
                "time" => outTime,
                "title" => outTitle
            });
            return;
        }
        Background.exit(null);
    }
}
