/**
 * Optional Google Calendar Bridge (Google Apps Script)
 * ----------------------------------------------------
 * Garmin watch faces cannot read meeting titles directly from the watch's
 * system complication (which only provides the next event's start time).
 *
 * Deploy this script at https://script.google.com as a Web App (Execute as: Me,
 * Who has access: Anyone) and paste the resulting /exec URL into your watch
 * face's "Calendar JSON Bridge URL" setting in the Garmin Connect IQ app.
 */
function doGet() {
  var now = new Date();
  var end = new Date(now.getTime() + (7 * 24 * 60 * 60 * 1000));
  var events = CalendarApp.getDefaultCalendar().getEvents(now, end);

  var result = { time: "", title: "" };
  for (var i = 0; i < events.length; i++) {
    var ev = events[i];
    if (ev.getEndTime().getTime() <= now.getTime()) {
      continue;
    }
    var timeStr = ev.isAllDayEvent()
      ? "ALL DAY"
      : Utilities.formatDate(ev.getStartTime(), Session.getScriptTimeZone(), "HH:mm");
    result = {
      time: timeStr,
      title: ev.getTitle() || "Untitled Event"
    };
    break;
  }

  return ContentService
    .createTextOutput(JSON.stringify(result))
    .setMimeType(ContentService.MimeType.JSON);
}
