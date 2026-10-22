import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class PilotZuluApp extends Application.AppBase {
    var _view;

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        _view = new PilotZuluView();
        return [_view];
    }

    // On-watch settings: long-press the face -> Watch Face -> Pilot Zulu -> Customize/Settings
    function getSettingsView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] or Null {
        return [buildMainMenu(), new MainMenuDelegate(_view)];
    }

    // Called when settings are changed in the Garmin Connect / Connect IQ phone app
    function onSettingsChanged() as Void {
        if (_view != null) {
            _view.loadTheme();
        }
        WatchUi.requestUpdate();
    }
}

// ---- on-watch settings menus ------------------------------------------

const THEME_NAMES = [Rez.Strings.ThemeCream, Rez.Strings.ThemeNight, Rez.Strings.ThemeMono];
const CITY_NAMES = [
    Rez.Strings.CityBKK, Rez.Strings.CityHKT, Rez.Strings.CityCNX, Rez.Strings.CitySIN, Rez.Strings.CityKUL,
    Rez.Strings.CityCGK, Rez.Strings.CityMNL, Rez.Strings.CityHKG, Rez.Strings.CityTPE, Rez.Strings.CityPVG,
    Rez.Strings.CityPEK, Rez.Strings.CityICN, Rez.Strings.CityNRT, Rez.Strings.CityKIX, Rez.Strings.CityDEL,
    Rez.Strings.CityBOM, Rez.Strings.CityDXB, Rez.Strings.CitySYD, Rez.Strings.CityMEL, Rez.Strings.CityPER,
    Rez.Strings.CityLHR, Rez.Strings.CityCDG, Rez.Strings.CityFRA, Rez.Strings.CityMUC, Rez.Strings.CityZRH,
    Rez.Strings.CityCPH, Rez.Strings.CityARN, Rez.Strings.CityOSL, Rez.Strings.CityIST,
    Rez.Strings.CityCustom];
const DATA_NAMES = [Rez.Strings.DataBB, Rez.Strings.DataBat, Rez.Strings.DataSteps, Rez.Strings.DataOff];

function currentChoice(key as String, dflt as Number) as Number {
    var v = Application.Properties.getValue(key);
    var n = (v != null) ? (v as Number) : dflt;
    var max = key.equals("HomeCity") ? CITY_NAMES.size() : (key.equals("Theme") ? THEME_NAMES.size() : DATA_NAMES.size());
    return (n >= 0 && n < max) ? n : dflt;
}

function buildMainMenu() as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => WatchUi.loadResource(Rez.Strings.SettingsTitle)});
    menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.ThemeTitle),
        WatchUi.loadResource(THEME_NAMES[currentChoice("Theme", 0)]), "Theme", null));
    menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.LeftArcTitle),
        WatchUi.loadResource(DATA_NAMES[currentChoice("LeftArc", 0)]), "LeftArc", null));
    menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.RightArcTitle),
        WatchUi.loadResource(DATA_NAMES[currentChoice("RightArc", 2)]), "RightArc", null));
    menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.HomeCityTitle),
        WatchUi.loadResource(CITY_NAMES[currentChoice("HomeCity", 0)]), "HomeCity", null));
    return menu;
}

function buildChoiceMenu(key as String, titleRez, names as Array, dflt as Number) as WatchUi.Menu2 {
    var current = currentChoice(key, dflt);
    var menu = new WatchUi.Menu2({:title => WatchUi.loadResource(titleRez)});
    for (var i = 0; i < names.size(); i++) {
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(names[i]),
            (i == current) ? "Selected" : null, i, null));
    }
    menu.setFocus(current);
    return menu;
}

class MainMenuDelegate extends WatchUi.Menu2InputDelegate {
    var _view;

    function initialize(view) {
        Menu2InputDelegate.initialize();
        _view = view;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var key = item.getId() as String;
        var menu;
        if (key.equals("Theme")) {
            menu = buildChoiceMenu(key, Rez.Strings.ThemeTitle, THEME_NAMES, 0);
        } else if (key.equals("LeftArc")) {
            menu = buildChoiceMenu(key, Rez.Strings.LeftArcTitle, DATA_NAMES, 0);
        } else if (key.equals("HomeCity")) {
            menu = buildChoiceMenu(key, Rez.Strings.HomeCityTitle, CITY_NAMES, 0);
        } else {
            menu = buildChoiceMenu(key, Rez.Strings.RightArcTitle, DATA_NAMES, 2);
        }
        WatchUi.pushView(menu, new ChoiceMenuDelegate(_view, key, item), WatchUi.SLIDE_LEFT);
    }
}

class ChoiceMenuDelegate extends WatchUi.Menu2InputDelegate {
    var _view;
    var _key;
    var _parentItem;

    function initialize(view, key as String, parentItem as WatchUi.MenuItem) {
        Menu2InputDelegate.initialize();
        _view = view;
        _key = key;
        _parentItem = parentItem;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        Application.Properties.setValue(_key, item.getId() as Number);
        _parentItem.setSubLabel(item.getLabel());
        if (_view != null) {
            _view.loadTheme();
        }
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        WatchUi.requestUpdate();
    }
}
