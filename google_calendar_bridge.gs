/**
 * Optional Google Calendar Bridge (Google Apps Script)
 * ----------------------------------------------------
 * Garmin watch faces cannot read meeting titles directly from the watch's
 * system complication (which only provides the next event's start time).
 *
 * Deploy this script at https://script.google.com as a Web App (Execute as: Me,
 * Who has access: Anyone).
 * Optional Security Token: Set EXPECTED_TOKEN below to a random secret string,
 * then append ?key=YOUR_SECRET to the /exec URL you enter in Garmin Connect IQ.
 */
var EXPECTED_TOKEN = "";

function doGet(e) {
  if (EXPECTED_TOKEN && (!e || !e.parameter || e.parameter.key !== EXPECTED_TOKEN)) {
    return ContentService
      .createTextOutput(JSON.stringify({ time: "", title: "" }))
      .setMimeType(ContentService.MimeType.JSON);
  }
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
