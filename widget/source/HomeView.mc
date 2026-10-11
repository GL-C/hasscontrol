using Toybox.Application as App;
using Toybox.WatchUi as Ui;
using Toybox.Graphics;
using Toybox.Time;
using Hass;

class HomeDelegate extends Ui.BehaviorDelegate {
  hidden var _view;
  function initialize(view) { BehaviorDelegate.initialize(); _view = view; }
  function onSelect() {
    App.getApp().resetInactivityTimer();
    if (!App.getApp().isLoggedIn()) { App.getApp().login(); return true; }
    var controller = new EntityListController([_view.getSelectedType()]);
    Ui.pushView(new EntityListView(controller), new EntityListDelegate(controller), Ui.SLIDE_IMMEDIATE);
    return true;
  }
  function onTap(event) {
    if (!App.getApp().isLoggedIn()) { return onSelect(); }
    var row = _view.getTappedRow(event.getCoordinates()[1]);
    if (row == -1) { return onMenu(); }
    if (row == null) { return true; }
    _view.setSelected(row);
    return onSelect();
  }
  function onNextPage() { _view.moveSelection(1); return true; }
  function onPreviousPage() { _view.moveSelection(-1); return true; }
  function onMenu() {
    App.getApp().resetInactivityTimer();
    App.getApp().menu.showRootMenu();
    return true;
  }
  function onHold(event) { return onMenu(); }
}

class HomeView extends Ui.View {
  hidden var _selected;
  hidden var _height;
  function initialize() { View.initialize(); _selected = 0; _height = 0; }
  function onShow() {
    if (App.Properties.getValue("refresh") && App.getApp().isLoggedIn()) { Hass.refreshAllEntities(true); }
  }
  function getSelectedType() { return [Hass.TYPE_LOCK, Hass.TYPE_LIGHT, Hass.TYPE_FAN][_selected]; }
  function setSelected(index) { _selected = index; Ui.requestUpdate(); }
  function moveSelection(step) {
    App.getApp().resetInactivityTimer();
    _selected = (_selected + step + 3) % 3;
    Ui.requestUpdate();
  }
  function getTappedRow(y) {
    if (_height == 0) { return null; }
    if (y >= _height * 0.81) { return -1; }
    for (var i = 0; i < 3; i++) {
      var top = _height * (0.19 + i * 0.20);
      if (y >= top && y < top + _height * 0.20) { return i; }
    }
    return null;
  }
  function isDark() { return App.Properties.getValue("darkTheme") == true; }
  function foreground() { return isDark() ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK; }
  function background() { return isDark() ? Graphics.COLOR_BLACK : Graphics.COLOR_WHITE; }
  function drawGroup(dc, index, label, text, attention) {
    var w = dc.getWidth();
    var h = dc.getHeight();
    var top = h * (0.19 + index * 0.20);
    var fill = index == _selected ? (isDark() ? Graphics.COLOR_DK_GRAY : Graphics.COLOR_LT_GRAY) : background();
    dc.setColor(fill, background());
    dc.fillRoundedRectangle(w * 0.15, top, w * 0.70, h * 0.18, 12);
    dc.setColor(foreground(), fill);
    dc.drawText(w / 2, top + h * 0.005, Graphics.FONT_SMALL, label, Graphics.TEXT_JUSTIFY_CENTER);
    dc.setColor(attention ? (isDark() ? Graphics.COLOR_YELLOW : Graphics.COLOR_DK_RED) : foreground(), fill);
    var summary = Graphics.fitTextToArea(text, Graphics.FONT_XTINY, w * 0.65, h * 0.07, true);
    dc.drawText(w / 2, top + h * 0.09, Graphics.FONT_XTINY, summary, Graphics.TEXT_JUSTIFY_CENTER);
  }
  function onUpdate(dc) {
    var w = dc.getWidth();
    var h = dc.getHeight();
    _height = h;
    dc.setColor(foreground(), background());
    dc.clear();
    if (!App.getApp().isLoggedIn()) {
      dc.drawText(w / 2, h * 0.4, Graphics.FONT_XTINY, "Sign in on your phone", Graphics.TEXT_JUSTIFY_CENTER);
      dc.drawText(w / 2, h * 0.68, Graphics.FONT_XTINY, "Tap / Select to sign in", Graphics.TEXT_JUSTIFY_CENTER);
      return;
    }
    var stamp = "Cached";
    if (Hass.lastRefresh != null) { stamp = "Updated " + (Time.now().value() - Hass.lastRefresh.value()) + "s ago"; }
    if (Hass.refreshFailed) { stamp = "Refresh failed - cached"; }
    dc.drawText(w / 2, h * 0.07, Graphics.FONT_XTINY, stamp, Graphics.TEXT_JUSTIFY_CENTER);
    var locks = Hass.getHomeCounts(Hass.TYPE_LOCK, Hass.STATE_LOCKED);
    var lights = Hass.getHomeCounts(Hass.TYPE_LIGHT, Hass.STATE_ON);
    var fans = Hass.getHomeCounts(Hass.TYPE_FAN, Hass.STATE_ON);
    drawGroup(dc, 0, "Doors", Hass.getDoorText(locks), locks[0] == 0 || locks[1] != locks[0]);
    drawGroup(dc, 1, "Lights", Hass.getCountText(lights), lights[1] > 0 || lights[2] > 0);
    drawGroup(dc, 2, "Fans", Hass.getCountText(fans), fans[1] > 0 || fans[2] > 0);
    dc.setColor(foreground(), background());
    dc.drawText(w / 2, h * 0.83, Graphics.FONT_XTINY, "Menu / hold: settings", Graphics.TEXT_JUSTIFY_CENTER);
  }
}
