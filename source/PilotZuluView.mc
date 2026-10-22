import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// Pilot Zulu — Minimal Zulu watch face for Forerunner 965 (454x454 AMOLED).
// Rim: 60-minute track, big dot = hour, small dot = minute, red stub = seconds.
// Centre: UTC HH:MM:ss, large local time, date, home-city time (default BKK).
// Below: date, then watch battery + heart/HR flanking a short divider, home-city time, steps.
// Side gauges (7->11 and 5->1, filling upward) show user-selectable data: Body Battery, watch battery, step goal.
// Settings (watch menu or phone app): Theme 0 cream/1 night/2 mono; LeftArc/RightArc 0 BB/1 BAT/2 STEP/3 Off;
// HomeCity (index into CITY_CODES, last = Custom with CustomLabel + CustomOffset hours).
class PilotZuluView extends WatchUi.WatchFace {

    // Home city table (index = HomeCity setting). Offsets are standard-time minutes, used only when
    // Gregorian.localMoment is unavailable; otherwise the watch's own tz database applies DST.
    const CITY_CODES = ["BKK", "HKT", "CNX", "SIN", "KUL", "CGK", "MNL", "HKG", "TPE", "PVG", "PEK", "ICN", "NRT", "KIX", "DEL", "BOM", "DXB", "SYD", "MEL", "PER", "LHR", "CDG", "FRA", "MUC", "ZRH", "CPH", "ARN", "OSL", "IST"];
    const CITY_LAT = [13.69, 8.11, 18.77, 1.36, 2.75, -6.13, 14.51, 22.31, 25.08, 31.14, 40.08, 37.46, 35.77, 34.43, 28.56, 19.09, 25.25, -33.94, -37.67, -31.94, 51.47, 49.01, 50.04, 48.35, 47.46, 55.62, 59.65, 60.19, 41.26];
    const CITY_LON = [100.75, 98.31, 98.96, 103.99, 101.71, 106.66, 121.02, 113.91, 121.23, 121.81, 116.58, 126.44, 140.39, 135.24, 77.1, 72.87, 55.36, 151.18, 144.84, 115.97, -0.45, 2.55, 8.56, 11.79, 8.55, 12.65, 17.92, 11.1, 28.74];
    const CITY_STD_MIN = [420, 420, 420, 480, 480, 420, 480, 480, 480, 480, 480, 540, 540, 540, 330, 330, 240, 600, 600, 480, 0, 60, 60, 60, 60, 60, 60, 60, 180];
    const CITY_CUSTOM = 29;
    const DATA_OFF = 3;                     // LeftArc/RightArc: 0 BB, 1 BAT, 2 STEP, 3 Off
    const DAYS = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
    const MONTHS = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];

    // Palette order: bg, track, tick, tick5, zulu, zsec, local, date, sub, info, arc, sec
    const THEMES = [
        [0x000000, 0x1F1D1A, 0x3A3630, 0xA39A86, 0xEFE6CF, 0xA39A86, 0xF4ECD8, 0xA39A86, 0xD8CFB8, 0xA39A86, 0xA39A86, 0xE0352B], // Vintage cream
        [0x000000, 0x141414, 0x222222, 0x4A4A4A, 0x9A9A9A, 0x5A5A5A, 0xBDBDBD, 0x5A5A5A, 0x7A7A7A, 0x6A6A6A, 0x4A4A4A, 0xFF2D20], // Night dim
        [0x000000, 0x1C1C1E, 0x3A3A3C, 0x8E8E93, 0xE5E5EA, 0x8E8E93, 0xFFFFFF, 0x8E8E93, 0xC7C7CC, 0xAEAEB2, 0x8E8E93, 0xFF3B30]  // Mono
    ];
    const BG = 0; const TRACK = 1; const TICK = 2; const TICK5 = 3; const ZULU = 4; const ZSEC = 5;
    const LOCAL = 6; const DATE = 7; const SUB = 8; const INFO = 9; const ARC = 10; const SEC = 11;

    var _pal;
    var _sleeping = false;
    var _fBig;
    var _fZulu;
    var _fZsec;
    var _fLabel;
    var _fDate;
    var _fRow;
    var _fHome;
    var _leftData = 0;
    var _rightData = 2;
    var _city = 0;
    var _customLabel = "UTC";
    var _customOffSec = 0;
    var _homeOffSec = 7 * 3600;
    var _homeOffMinute = -1;            // minute of the cached _homeOffSec (re-evaluated once a minute)

    function initialize() {
        WatchFace.initialize();
        loadTheme();
    }

    function onLayout(dc as Dc) as Void {
        _fBig = WatchUi.loadResource(Rez.Fonts.BigTime);
        _fZulu = WatchUi.loadResource(Rez.Fonts.ZuluMain);
        _fZsec = WatchUi.loadResource(Rez.Fonts.ZuluSec);
        _fLabel = WatchUi.loadResource(Rez.Fonts.Label);
        _fDate = WatchUi.loadResource(Rez.Fonts.Date);
        _fRow = WatchUi.loadResource(Rez.Fonts.Row);
        _fHome = WatchUi.loadResource(Rez.Fonts.Home);
    }

    function loadTheme() as Void {
        var t = 0;
        try {
            var v = Application.Properties.getValue("Theme");
            if (v != null) { t = v as Number; }
        } catch (e) {
            t = 0;
        }
        if (t < 0 || t >= THEMES.size()) { t = 0; }
        _pal = THEMES[t];
        _leftData = readChoice("LeftArc", 0);
        _rightData = readChoice("RightArc", 2);
        _city = readNumber("HomeCity", 0, CITY_CUSTOM);
        _customLabel = "UTC";
        _customOffSec = 0;
        try {
            var lbl = Application.Properties.getValue("CustomLabel");
            if (lbl != null && (lbl as String).length() > 0) {
                _customLabel = (lbl as String).toUpper();
                if (_customLabel.length() > 4) { _customLabel = _customLabel.substring(0, 4); }
            }
            var off = Application.Properties.getValue("CustomOffset");
            if (off instanceof Number || off instanceof Float) {
                var h = (off as Numeric).toFloat();
                if (h >= -12.0 && h <= 14.0) { _customOffSec = (h * 3600).toNumber(); }
            }
        } catch (e) {
            _customLabel = "UTC";
        }
        _homeOffMinute = -1;
    }

    function readNumber(key, dflt, max) {
        var v = dflt;
        try {
            var p = Application.Properties.getValue(key);
            if (p != null) { v = p as Number; }
        } catch (e) {
            v = dflt;
        }
        if (v < 0 || v > max) { v = dflt; }
        return v;
    }

    function homeLabel() as String {
        return (_city == CITY_CUSTOM) ? _customLabel : CITY_CODES[_city];
    }

    // UTC offset (seconds) of the home city right now, DST included when the device supports localMoment.
    function homeOffset(now as Time.Moment, minute) as Number {
        if (_city == CITY_CUSTOM) { return _customOffSec; }
        if (minute == _homeOffMinute) { return _homeOffSec; }
        var off = CITY_STD_MIN[_city] * 60;
        try {
            if (Gregorian has :localMoment) {
                var loc = new Position.Location({:latitude => CITY_LAT[_city], :longitude => CITY_LON[_city], :format => :degrees});
                var lm = Gregorian.localMoment(loc, now);
                if (lm != null) { off = lm.getOffset(); }
            }
        } catch (e) {
            off = CITY_STD_MIN[_city] * 60;
        }
        _homeOffSec = off;
        _homeOffMinute = minute;
        return off;
    }

    function readChoice(key, dflt) {
        var v = dflt;
        try {
            var p = Application.Properties.getValue(key);
            if (p != null) { v = p as Number; }
        } catch (e) {
            v = dflt;
        }
        if (v < 0 || v > DATA_OFF) { v = dflt; }
        return v;
    }

    // 0..1 fraction for a gauge data source
    function dataFraction(which, batt, stepFrac) {
        if (which == 1) { return batt; }
        if (which == 2) { return stepFrac; }
        if ((Toybox has :SensorHistory) && (SensorHistory has :getBodyBatteryHistory)) {
            var sample = SensorHistory.getBodyBatteryHistory({:period => 1}).next();
            if (sample != null && sample.data != null) { return sample.data / 100.0; }
        }
        return 0.0;
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var cx = w / 2;
        var cy = dc.getHeight() / 2;
        var s = w / 454.0;               // layout was designed at 454 px

        if (dc has :setAntiAlias) { dc.setAntiAlias(true); }
        dc.setColor(_pal[BG], _pal[BG]);
        dc.clear();

        var now = Time.now();
        var clock = System.getClockTime();
        var utc = Gregorian.utcInfo(now, Time.FORMAT_SHORT);
        var home = Gregorian.utcInfo(now.add(new Time.Duration(homeOffset(now, clock.min))), Time.FORMAT_SHORT);
        var date = Gregorian.info(now, Time.FORMAT_SHORT);

        if (_sleeping) {
            drawAlwaysOn(dc, cx, cy, s, clock, utc);
            return;
        }

        // 60-minute rim track
        for (var m = 0; m < 60; m++) {
            var big = (m % 5 == 0);
            dc.setColor(big ? _pal[TICK5] : _pal[TICK], Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(big ? 3 : 1);
            radial(dc, cx, cy, m * 6.0, 218 * s, (big ? 206 : 212) * s);
        }

        // Side gauges: left 7 -> 11 o'clock, right 5 -> 1 o'clock, both fill upward (full = 120 degrees)
        var batt = System.getSystemStats().battery / 100.0;
        var am = ActivityMonitor.getInfo();
        var steps = (am.steps != null) ? am.steps : 0;
        var goal = (am.stepGoal != null && am.stepGoal > 0) ? am.stepGoal : 10000;
        var stepFrac = steps.toFloat() / goal;
        if (stepFrac > 1.0) { stepFrac = 1.0; }
        var lf = (_leftData == DATA_OFF) ? 0.0 : dataFraction(_leftData, batt, stepFrac);
        var rf = (_rightData == DATA_OFF) ? 0.0 : dataFraction(_rightData, batt, stepFrac);
        var r = 180 * s;
        dc.setPenWidth(6);
        if (_leftData != DATA_OFF) {   // 11 -> 7 o'clock
            dc.setColor(_pal[TRACK], Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, r, Graphics.ARC_COUNTER_CLOCKWISE, 120, 240);
            if (lf > 0.02) {
                dc.setColor(_pal[ARC], Graphics.COLOR_TRANSPARENT);
                dc.drawArc(cx, cy, r, Graphics.ARC_COUNTER_CLOCKWISE, 240 - (120 * lf).toNumber(), 240);
            }
        }
        if (_rightData != DATA_OFF) {  // 5 -> 1 o'clock
            dc.setColor(_pal[TRACK], Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, r, Graphics.ARC_COUNTER_CLOCKWISE, 300, 60);
            if (rf > 0.02) {
                dc.setColor(_pal[ARC], Graphics.COLOR_TRANSPARENT);
                dc.drawArc(cx, cy, r, Graphics.ARC_COUNTER_CLOCKWISE, 300, (300 + (120 * rf).toNumber()) % 360);
            }
        }

        // ZULU HH:MM + smaller :SS, baseline-aligned
        drawCentered(dc, cx, 70 * s, _fLabel, "UTC", _pal[ZSEC]);
        var zMain = utc.hour.format("%02d") + ":" + utc.min.format("%02d");
        var zSec = ":" + utc.sec.format("%02d");
        var wMain = dc.getTextWidthInPixels(zMain, _fZulu);
        var wSec = dc.getTextWidthInPixels(zSec, _fZsec);
        var x0 = cx - (wMain + wSec) / 2;
        var base = 124 * s;
        dc.setColor(_pal[ZULU], Graphics.COLOR_TRANSPARENT);
        dc.drawText(x0, base - Graphics.getFontAscent(_fZulu), _fZulu, zMain, Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(_pal[ZSEC], Graphics.COLOR_TRANSPARENT);
        dc.drawText(x0 + wMain, base - Graphics.getFontAscent(_fZsec), _fZsec, zSec, Graphics.TEXT_JUSTIFY_LEFT);

        // Local time, date, home time
        var local = clock.hour.format("%02d") + ":" + clock.min.format("%02d");
        // BigTime lineHeight 180, digits sit 43..151 in the cell, so y=220 puts the digits' centre at 227
        drawCentered(dc, cx, 220 * s, _fBig, local, _pal[LOCAL]);
        drawCentered(dc, cx, 300 * s, _fDate,
            DAYS[date.day_of_week - 1] + " " + date.day.format("%d") + " " + MONTHS[date.month - 1], _pal[SUB]);
        dc.setColor(_pal[TRACK], Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(cx - 37 * s, 328 * s, cx + 37 * s, 328 * s);

        // Battery | divider | heart + HR row (y 318), between date and BKK.
        // Battery is right-aligned and HR left-aligned toward the centre so neither reaches the side gauges.
        var rowY = 318 * s;
        dc.setColor(_pal[INFO], Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - 62 * s, rowY, _fRow, (batt * 100).toNumber().format("%d") + "%",
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        var hr = getHeartRate();
        drawHeart(dc, cx + 66.5 * s, rowY, 19 * s, _pal[SEC]);   // 19 px heart, ~4 px gap to HR
        dc.setColor(_pal[INFO], Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + 81 * s, rowY, _fRow, (hr != null) ? hr.format("%d") : "--",
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        // Home-city time on its own row, then steps
        drawCentered(dc, cx, 355 * s, _fHome,
            homeLabel() + " " + home.hour.format("%02d") + ":" + home.min.format("%02d"), _pal[SUB]);
        drawCentered(dc, cx, 389 * s, _fRow, withCommas(steps), _pal[INFO]);

        // Hour / minute dots and seconds stub on the rim
        var hourAngle = (clock.hour % 12 + clock.min / 60.0) * 30.0;
        var minAngle = clock.min * 6.0;
        rimDot(dc, cx, cy, hourAngle, 202 * s, 7 * s, _pal[LOCAL], 2);
        rimDot(dc, cx, cy, minAngle, 202 * s, 4.5 * s, _pal[LOCAL], 2);
        var secAngle = clock.sec * 6.0;
        dc.setColor(_pal[SEC], Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(4);
        radial(dc, cx, cy, secAngle, 226 * s, 200 * s);
        var p = polar(cx, cy, secAngle, 200 * s);
        dc.fillCircle(p[0], p[1], 4 * s);
    }

    // Always-on (AMOLED): dim, few lit pixels, no seconds, shifted each minute against burn-in.
    function drawAlwaysOn(dc, cx, cy, s, clock, utc) as Void {
        var shift = ((clock.min % 5) - 2) * 3;
        var ox = cx + shift;
        var oy = cy + shift;
        dc.setColor(_pal[TICK], Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        for (var m = 0; m < 60; m += 5) {
            radial(dc, ox, oy, m * 6.0, 218 * s, 208 * s);
        }
        drawCentered(dc, ox, oy + (108 - 227) * s, _fZulu,
            utc.hour.format("%02d") + ":" + utc.min.format("%02d") + "Z", _pal[ZSEC]);
        drawCentered(dc, ox, oy + (220 - 227) * s, _fBig,
            clock.hour.format("%02d") + ":" + clock.min.format("%02d"), _pal[DATE]);
        var hourAngle = (clock.hour % 12 + clock.min / 60.0) * 30.0;
        rimDot(dc, ox, oy, hourAngle, 202 * s, 7 * s, _pal[DATE], 2);
        rimDot(dc, ox, oy, clock.min * 6.0, 202 * s, 4.5 * s, _pal[DATE], 2);
    }

    // ---- helpers -------------------------------------------------------

    // angle in degrees clockwise from 12 o'clock
    function polar(cx, cy, angle, r) {
        var a = Math.toRadians(angle);
        return [cx + r * Math.sin(a), cy - r * Math.cos(a)];
    }

    function radial(dc, cx, cy, angle, r1, r2) as Void {
        var a = polar(cx, cy, angle, r1);
        var b = polar(cx, cy, angle, r2);
        dc.drawLine(a[0], a[1], b[0], b[1]);
    }

    function rimDot(dc, cx, cy, angle, r, rad, color, outline) as Void {
        var p = polar(cx, cy, angle, r);
        dc.setColor(_pal[BG], Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(p[0], p[1], rad + outline);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(p[0], p[1], rad);
    }

    // Heart icon: two circles + a triangle, centred on (x, y), width sz
    function drawHeart(dc, x, y, sz, color) as Void {
        var r = sz * 0.27;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - sz * 0.25, y - sz * 0.12, r);
        dc.fillCircle(x + sz * 0.25, y - sz * 0.12, r);
        dc.fillPolygon([[x - sz * 0.5, y - sz * 0.02], [x + sz * 0.5, y - sz * 0.02], [x, y + sz * 0.45]]);
    }

    function drawCentered(dc, x, y, font, text, color) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, text, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    function withCommas(n) as String {
        var s = n.format("%d");
        var out = "";
        var len = s.length();
        for (var i = 0; i < len; i++) {
            if (i > 0 && (len - i) % 3 == 0) { out += ","; }
            out += s.substring(i, i + 1);
        }
        return out;
    }

    function getHeartRate() {
        var info = Activity.getActivityInfo();
        if (info != null && info.currentHeartRate != null) {
            return info.currentHeartRate;
        }
        var it = ActivityMonitor.getHeartRateHistory(1, true);
        var sample = it.next();
        if (sample != null && sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
            return sample.heartRate;
        }
        return null;
    }

    function onEnterSleep() as Void {
        _sleeping = true;
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        _sleeping = false;
        WatchUi.requestUpdate();
    }
}
