using Toybox.Lang;
using Toybox.WatchUi;

//! Handles touch-and-hold gestures on the Forerunner 570 watch face to open native glances.
class FR570WatchFaceDelegate extends WatchUi.WatchFaceDelegate {

    private var _view as FR570WatchFaceView;

    function initialize(view as FR570WatchFaceView) {
        WatchFaceDelegate.initialize();
        _view = view;
    }

    function onPress(clickEvent as WatchUi.ClickEvent) as Lang.Boolean {
        var coords = clickEvent.getCoordinates();
        if (coords != null && coords.size() >= 2) {
            return _view.launchShortcutAt(coords[0], coords[1]);
        }
        return false;
    }
}
