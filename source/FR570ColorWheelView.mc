using Toybox.Application.Properties;
using Toybox.Application.Storage;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;
using Toybox.WatchUi;

//! Helper math shared by the on-watch Color Wheel and Customize Menu.
module FR570WheelMath {

    function hsvToRgb24(hueDeg as Lang.Number, satPct as Lang.Number, valPct as Lang.Number) as Lang.Number {
        var h = hueDeg % 360;
        if (h < 0) {
            h += 360;
        }
        var s = satPct.toFloat() / 100.0;
        var v = valPct.toFloat() / 100.0;
        var c = v * s;
        var sector = h / 60;
        var f = (h.toFloat() / 60.0) - sector.toFloat();
        var x = c * (1.0 - (f - 1.0 + 1.0 - 0.0)); // computed properly below per odd/even sector
        if ((sector % 2) == 0) {
            x = c * f;
        } else {
            x = c * (1.0 - f);
        }
        var m = v - c;
        var rf = 0.0;
        var gf = 0.0;
        var bf = 0.0;
        if (sector == 0) {
            rf = c; gf = x; bf = 0.0;
        } else if (sector == 1) {
            rf = x; gf = c; bf = 0.0;
        } else if (sector == 2) {
            rf = 0.0; gf = c; bf = x;
        } else if (sector == 3) {
            rf = 0.0; gf = x; bf = c;
        } else if (sector == 4) {
            rf = x; gf = 0.0; bf = c;
        } else {
            rf = c; gf = 0.0; bf = x;
        }
        var r = ((rf + m) * 255.0 + 0.5).toNumber();
        var g = ((gf + m) * 255.0 + 0.5).toNumber();
        var b = ((bf + m) * 255.0 + 0.5).toNumber();
        if (r > 255) { r = 255; } else if (r < 0) { r = 0; }
        if (g > 255) { g = 255; } else if (g < 0) { g = 0; }
        if (b > 255) { b = 255; } else if (b < 0) { b = 0; }
        return (r << 16) | (g << 8) | b;
    }

    function formatHex24(col as Lang.Number) as Lang.String {
        var r = (col >> 16) & 0xFF;
        var g = (col >> 8) & 0xFF;
        var b = col & 0xFF;
        return "#" + r.format("%02X") + g.format("%02X") + b.format("%02X");
    }

    function getToneLabel(toneIdx as Lang.Number) as Lang.String {
        if (toneIdx == 1) { return "MUTED"; }
        if (toneIdx == 2) { return "DEEP"; }
        if (toneIdx == 3) { return "SILVER"; }
        return "VIVID";
    }

    function getToneSat(toneIdx as Lang.Number) as Lang.Number {
        if (toneIdx == 1) { return 55; }
        if (toneIdx == 2) { return 68; }
        if (toneIdx == 3) { return 12; }
        return 92;
    }

    function getToneVal(toneIdx as Lang.Number) as Lang.Number {
        if (toneIdx == 1) { return 74; }
        if (toneIdx == 2) { return 48; }
        if (toneIdx == 3) { return 84; }
        return 95;
    }

    function approxHueSlice(rgb as Lang.Number) as Lang.Number {
        var r = ((rgb >> 16) & 0xFF).toFloat() / 255.0;
        var g = ((rgb >> 8) & 0xFF).toFloat() / 255.0;
        var b = (rgb & 0xFF).toFloat() / 255.0;
        var maxC = r;
        if (g > maxC) { maxC = g; }
        if (b > maxC) { maxC = b; }
        var minC = r;
        if (g < minC) { minC = g; }
        if (b < minC) { minC = b; }
        var d = maxC - minC;
        if (d < 0.02) {
            return 0;
        }
        var hue = 0.0;
        if (maxC == r) {
            hue = 60.0 * (((g - b) / d));
        } else if (maxC == g) {
            hue = 60.0 * (((b - r) / d) + 2.0);
        } else {
            hue = 60.0 * (((r - g) / d) + 4.0);
        }
        while (hue < 0.0) { hue += 360.0; }
        while (hue >= 360.0) { hue -= 360.0; }
        return ((hue + 5.0) / 10.0).toNumber() % 36;
    }
}

//! Interactive 36-hue Color Wheel View displayed on-watch via Customize.
class FR570ColorWheelView extends WatchUi.View {

    private var _slotKey as Lang.String;
    private var _slotTitle as Lang.String;
    private var _sliceIdx as Lang.Number = 0;
    private var _toneIdx as Lang.Number = 0;
    private var _onSavedCb as Lang.Method?;
    private var _width as Lang.Number = 454;

    function initialize(
        slotKey as Lang.String,
        slotTitle as Lang.String,
        initialColor as Lang.Number,
        onSavedCb as Lang.Method?
    ) {
        View.initialize();
        _slotKey = slotKey;
        _slotTitle = slotTitle;
        _sliceIdx = FR570WheelMath.approxHueSlice(initialColor);
        var maxChan = (initialColor >> 16) & 0xFF;
        var gC = (initialColor >> 8) & 0xFF;
        var bC = initialColor & 0xFF;
        if (gC > maxChan) { maxChan = gC; }
        if (bC > maxChan) { maxChan = bC; }
        var minChan = (initialColor >> 16) & 0xFF;
        if (gC < minChan) { minChan = gC; }
        if (bC < minChan) { minChan = bC; }
        if ((maxChan - minChan) < 28) {
            _toneIdx = 3;
        } else if (maxChan < 145) {
            _toneIdx = 2;
        } else if (maxChan < 205) {
            _toneIdx = 1;
        }
        _onSavedCb = onSavedCb;
    }

    function getActiveColor() as Lang.Number {
        return FR570WheelMath.hsvToRgb24(
            _sliceIdx * 10,
            FR570WheelMath.getToneSat(_toneIdx),
            FR570WheelMath.getToneVal(_toneIdx)
        );
    }

    function getScreenWidth() as Lang.Number {
        return _width;
    }

    function stepHue(delta as Lang.Number) as Void {
        _sliceIdx = (_sliceIdx + delta + 36) % 36;
        WatchUi.requestUpdate();
    }

    function setHueSlice(idx as Lang.Number) as Void {
        _sliceIdx = (idx + 36) % 36;
        WatchUi.requestUpdate();
    }

    function cycleTone() as Void {
        _toneIdx = (_toneIdx + 1) % 4;
        WatchUi.requestUpdate();
    }

    function commitSelection() as Void {
        var chosen = getActiveColor();
        try {
            Storage.setValue(_slotKey, chosen);
            Properties.setValue("AccentColor", 7);
        } catch (ex) {
        }
        if (_onSavedCb != null) {
            (_onSavedCb as Lang.Method).invoke();
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        var w = dc.getWidth();
        var h = dc.getHeight();
        _width = w;
        var cx = w / 2;
        var cy = h / 2;
        var s = w.toFloat() / 454.0;
        var isMip = (w <= 260);

        dc.setColor(0x000000, 0x000000);
        dc.clear();

        var sat = FR570WheelMath.getToneSat(_toneIdx);
        var val = FR570WheelMath.getToneVal(_toneIdx);
        var ringR = (w / 2) - (isMip ? 14 : (26 * s).toNumber());
        var ringW = isMip ? 18 : (34 * s).toNumber();

        dc.setPenWidth(ringW);
        for (var i = 0; i < 36; i++) {
            var c = FR570WheelMath.hsvToRgb24(i * 10, sat, val);
            var startDeg = 90 - (i * 10);
            var endDeg = 90 - ((i + 1) * 10);
            while (startDeg < 0) { startDeg += 360; }
            while (endDeg < 0) { endDeg += 360; }
            dc.setColor(c, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, ringR, Graphics.ARC_CLOCKWISE, startDeg, endDeg);
        }

        // Highlight active hue wedge on the ring
        var selAngleDeg = 90.0 - ((_sliceIdx.toFloat() + 0.5) * 10.0);
        var selRad = (selAngleDeg * Math.PI) / 180.0;
        var mx = cx + (ringR * Math.cos(selRad)).toNumber();
        var my = cy - (ringR * Math.sin(selRad)).toNumber();
        var activeCol = getActiveColor();
        dc.setPenWidth(isMip ? 2 : 4);
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(mx, my, isMip ? 11 : (19 * s).toNumber());
        dc.setColor(activeCol, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(mx, my, isMip ? 8 : (14 * s).toNumber());
        dc.setPenWidth(1);

        // Center Live Preview
        dc.setColor(0xD4D4D8, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (108 * s).toNumber(), Graphics.FONT_XTINY, _slotTitle, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var timeFont = isMip ? Graphics.FONT_NUMBER_MILD : Graphics.FONT_NUMBER_HOT;
        var hw = dc.getTextWidthInPixels("6:", timeFont);
        var mw = dc.getTextWidthInPixels("48", timeFont);
        var tx0 = cx - ((hw + mw) / 2);
        var ty = (166 * s).toNumber();
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(tx0, ty, timeFont, "6:", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(activeCol, Graphics.COLOR_TRANSPARENT);
        dc.drawText(tx0 + hw, ty, timeFont, "48", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        // Tone pill (Tap center or UP/DOWN helper)
        var pw = isMip ? 112 : (190 * s).toNumber();
        var ph = isMip ? 24 : (40 * s).toNumber();
        var px = cx - (pw / 2);
        var py = (218 * s).toNumber();
        dc.setColor(activeCol, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(px, py, pw, ph, ph / 2);
        var luma = (((activeCol >> 16) & 0xFF) * 299 + ((activeCol >> 8) & 0xFF) * 587 + (activeCol & 0xFF) * 114) / 1000;
        dc.setColor((luma > 150) ? 0x000000 : 0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            cx, py + (ph / 2),
            Graphics.FONT_XTINY,
            "TONE: " + FR570WheelMath.getToneLabel(_toneIdx),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );

        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (278 * s).toNumber(), Graphics.FONT_TINY, FR570WheelMath.formatHex24(activeCol), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(0xA1A1AA, Graphics.COLOR_TRANSPARENT);
        var hint1 = isMip ? "UP/DN HUE  START SAVE" : "TAP RING: PICK HUE";
        var hint2 = isMip ? "LIGHT: TONE  BACK: ESC" : "TAP TONE • START SAVE";
        dc.drawText(cx, (316 * s).toNumber(), Graphics.FONT_XTINY, hint1, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, (342 * s).toNumber(), Graphics.FONT_XTINY, hint2, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

//! Handles both touchscreen ring taps/swipes (FR570) and hardware buttons (FR945 & FR570).
class FR570ColorWheelDelegate extends WatchUi.InputDelegate {

    private var _view as FR570ColorWheelView;

    function initialize(view as FR570ColorWheelView) {
        InputDelegate.initialize();
        _view = view;
    }

    function onTap(clickEvent as WatchUi.ClickEvent) as Lang.Boolean {
        var coords = clickEvent.getCoordinates();
        if (coords == null || coords.size() < 2) {
            return false;
        }
        var w = _view.getScreenWidth();
        var cx = w / 2;
        var cy = w / 2;
        var dx = coords[0] - cx;
        var dy = coords[1] - cy;
        var dist = Math.sqrt((dx * dx) + (dy * dy));
        if (dist >= (w * 0.28)) {
            var rad = Math.atan2(-dy.toFloat(), dx.toFloat());
            var deg = 90.0 - ((rad * 180.0) / Math.PI);
            while (deg < 0.0) { deg += 360.0; }
            while (deg >= 360.0) { deg -= 360.0; }
            var slice = (deg / 10.0).toNumber() % 36;
            _view.setHueSlice(slice);
            return true;
        }
        _view.cycleTone();
        return true;
    }

    function onSwipe(swipeEvent as WatchUi.SwipeEvent) as Lang.Boolean {
        var dir = swipeEvent.getDirection();
        if (dir == WatchUi.SWIPE_LEFT || dir == WatchUi.SWIPE_UP) {
            _view.stepHue(1);
            return true;
        }
        if (dir == WatchUi.SWIPE_RIGHT || dir == WatchUi.SWIPE_DOWN) {
            _view.stepHue(-1);
            return true;
        }
        return false;
    }

    function onKey(keyEvent as WatchUi.KeyEvent) as Lang.Boolean {
        var k = keyEvent.getKey();
        if (k == WatchUi.KEY_UP) {
            _view.stepHue(1);
            return true;
        } else if (k == WatchUi.KEY_DOWN) {
            _view.stepHue(-1);
            return true;
        } else if (k == WatchUi.KEY_LIGHT || k == WatchUi.KEY_MENU) {
            _view.cycleTone();
            return true;
        } else if (k == WatchUi.KEY_ENTER) {
            _view.commitSelection();
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
            return true;
        } else if (k == WatchUi.KEY_ESC) {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
            return true;
        }
        return false;
    }
}
