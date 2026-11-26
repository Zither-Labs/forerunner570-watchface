using Toybox.Application.Properties;
using Toybox.Application.Storage;
using Toybox.Lang;
using Toybox.WatchUi;

//! Builds the on-watch Customize menu accessible via Hold UP -> Watch Face -> Customize.
class FR570SettingsMenuBuilder {

    static function create() as [WatchUi.Views, WatchUi.InputDelegates] {
        var menu = new WatchUi.Menu2({ :title => "DualTrack" });
        menu.addItem(new WatchUi.MenuItem("Theme Preset", getPresetLabel(), :preset, null));
        menu.addItem(new WatchUi.MenuItem("Watch Layout", getLayoutLabel(), :layout, null));
        menu.addItem(new WatchUi.MenuItem("Arc Labels", getArcLabelModeLabel(), :arcLabels, null));
        menu.addItem(new WatchUi.MenuItem("Wheel: Primary", getHexSublabel("CustomPrimaryColor", 0xEF4444), :wheelPrimary, null));
        menu.addItem(new WatchUi.MenuItem("Wheel: Secondary", getHexSublabel("CustomSecondaryColor", 0x475569), :wheelSecondary, null));
        menu.addItem(new WatchUi.MenuItem("Wheel Background", getBgSublabel(), :bgTone, null));
        menu.addItem(new WatchUi.MenuItem("Reset Custom Colors", "Restore defaults", :resetCustom, null));
        return [menu, new FR570SettingsMenuDelegate(menu)];
    }

    static function getPresetLabel() as Lang.String {
        var names = [
            "0: Red & Orange",
            "1: Gold & Green",
            "2: Stealth Titanium",
            "3: Racing Emerald",
            "4: Petrol Teal",
            "5: Matte Steel",
            "6: Midnight Ceramic",
            "7: Custom Wheel"
        ];
        var idx = getNumProp("AccentColor", 6);
        if (idx < 0 || idx >= names.size()) {
            idx = 6;
        }
        return names[idx];
    }

    static function getLayoutLabel() as Lang.String {
        var names = [
            "#1 Wide Box + Smooth",
            "#2 Pure Black Minimal",
            "#3 Split Screen",
            "#4 Top Banner + Slant",
            "#5 Two-Tone Split",
            "#6 Two-Tone Ring"
        ];
        var idx = getNumProp("CardStyle", 3);
        if (idx < 0 || idx >= names.size()) {
            idx = 3;
        }
        return names[idx];
    }

    static function getArcLabelModeLabel() as Lang.String {
        var names = ["Off", "Label + %", "Label Only", "% Only"];
        var idx = getNumProp("ArcLabelMode", 1);
        if (idx < 0 || idx >= names.size()) {
            idx = 1;
        }
        return names[idx];
    }

    static function getHexSublabel(key as Lang.String, defCol as Lang.Number) as Lang.String {
        return FR570WheelMath.formatHex24(getStoredColor(key, defCol));
    }

    static function getBgSublabel() as Lang.String {
        var col = getStoredColor("CustomBgColor", 0x09090B);
        if (col == 0x0A1628) { return "Midnight Navy"; }
        if (col == 0x091A16) { return "Deep Forest"; }
        if (col == 0x0A191D) { return "Deep Petrol"; }
        if (col == 0x16161A) { return "Charcoal"; }
        return "Pure Black";
    }

    static function getStoredColor(key as Lang.String, defCol as Lang.Number) as Lang.Number {
        try {
            var val = Storage.getValue(key);
            if (val instanceof Lang.Number) {
                return val as Lang.Number;
            }
        } catch (ex) {
        }
        return defCol;
    }

    static function getNumProp(key as Lang.String, fallback as Lang.Number) as Lang.Number {
        try {
            var val = Properties.getValue(key);
            if (val instanceof Lang.Number) {
                return val as Lang.Number;
            }
        } catch (ex) {
        }
        return fallback;
    }
}

class FR570SettingsMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _menu as WatchUi.Menu2;

    function initialize(menu as WatchUi.Menu2) {
        Menu2InputDelegate.initialize();
        _menu = menu;
    }

    function refreshItems() as Void {
        var item0 = _menu.getItem(0);
        if (item0 != null) { item0.setSubLabel(FR570SettingsMenuBuilder.getPresetLabel()); }
        var item1 = _menu.getItem(1);
        if (item1 != null) { item1.setSubLabel(FR570SettingsMenuBuilder.getLayoutLabel()); }
        var item2 = _menu.getItem(2);
        if (item2 != null) { item2.setSubLabel(FR570SettingsMenuBuilder.getArcLabelModeLabel()); }
        var item3 = _menu.getItem(3);
        if (item3 != null) { item3.setSubLabel(FR570SettingsMenuBuilder.getHexSublabel("CustomPrimaryColor", 0xEF4444)); }
        var item4 = _menu.getItem(4);
        if (item4 != null) { item4.setSubLabel(FR570SettingsMenuBuilder.getHexSublabel("CustomSecondaryColor", 0x475569)); }
        var item5 = _menu.getItem(5);
        if (item5 != null) { item5.setSubLabel(FR570SettingsMenuBuilder.getBgSublabel()); }
        WatchUi.requestUpdate();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :preset) {
            var cur = FR570SettingsMenuBuilder.getNumProp("AccentColor", 6);
            try {
                Properties.setValue("AccentColor", (cur + 1) % 8);
            } catch (ex) {
            }
            refreshItems();
        } else if (id == :layout) {
            var curL = FR570SettingsMenuBuilder.getNumProp("CardStyle", 3);
            try {
                Properties.setValue("CardStyle", (curL + 1) % 6);
            } catch (ex) {
            }
            refreshItems();
        } else if (id == :arcLabels) {
            var curA = FR570SettingsMenuBuilder.getNumProp("ArcLabelMode", 1);
            try {
                Properties.setValue("ArcLabelMode", (curA + 1) % 4);
            } catch (ex) {
            }
            refreshItems();
        } else if (id == :wheelPrimary) {
            var curP = FR570SettingsMenuBuilder.getStoredColor("CustomPrimaryColor", 0xEF4444);
            var view = new FR570ColorWheelView("CustomPrimaryColor", "PRIMARY COLOR", curP, self.method(:refreshItems));
            WatchUi.pushView(view, new FR570ColorWheelDelegate(view), WatchUi.SLIDE_LEFT);
        } else if (id == :wheelSecondary) {
            var curS = FR570SettingsMenuBuilder.getStoredColor("CustomSecondaryColor", 0x475569);
            var view = new FR570ColorWheelView("CustomSecondaryColor", "SECONDARY / RING", curS, self.method(:refreshItems));
            WatchUi.pushView(view, new FR570ColorWheelDelegate(view), WatchUi.SLIDE_LEFT);
        } else if (id == :bgTone) {
            var bgs = [0x09090B, 0x16161A, 0x0A1628, 0x091A16, 0x0A191D];
            var curBg = FR570SettingsMenuBuilder.getStoredColor("CustomBgColor", 0x09090B);
            var nextIdx = 1;
            for (var i = 0; i < bgs.size(); i++) {
                if (bgs[i] == curBg) {
                    nextIdx = (i + 1) % bgs.size();
                    break;
                }
            }
            try {
                Storage.setValue("CustomBgColor", bgs[nextIdx]);
                Properties.setValue("AccentColor", 7);
            } catch (ex) {
            }
            refreshItems();
        } else if (id == :resetCustom) {
            try {
                Storage.setValue("CustomPrimaryColor", 0xEF4444);
                Storage.setValue("CustomSecondaryColor", 0x475569);
                Storage.setValue("CustomBgColor", 0x09090B);
                Properties.setValue("AccentColor", 0);
            } catch (ex) {
            }
            refreshItems();
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
