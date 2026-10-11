using Toybox.Application as App;
using Toybox.WatchUi as Ui;
using Toybox.Graphics;
using Toybox.Time;
using Hass;

// Button select and touchscreen tap both open the same quick-action menu.
class HomeDelegate extends Ui.BehaviorDelegate {
  function initialize() { BehaviorDelegate.initialize(); }
  function onSelect() {
    App.getApp().resetInactivityTimer();
    App.getApp().menu.showRootMenu();
    return true;
  }
  function onTap(event) { return onSelect(); }
  function onMenu() { return onSelect(); }
  function onHold(event) { return onSelect(); }
}

class HomeView extends Ui.View {
  function initialize() { View.initialize(); }
  function onShow() {
    if (App.Properties.getValue("refresh") && App.getApp().isLoggedIn()) {
      Hass.refreshAllEntities(true);
    }
  }

  function isDark() { return App.Properties.getValue("darkTheme") == true; }
  function foreground() { return isDark() ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK; }
  function background() { return isDark() ? Graphics.COLOR_BLACK : Graphics.COLOR_WHITE; }

  function drawRow(dc, y, label, text, attention) {
    var w = dc.getWidth();
    dc.setColor(attention ? (isDark() ? Graphics.COLOR_YELLOW : Graphics.COLOR_DK_RED) : foreground(), background());
    var row = Graphics.fitTextToArea(label + "  " + text, Graphics.FONT_XTINY,
      w * 0.82, dc.getHeight() * 0.13, true);
    dc.drawText(w / 2, y, Graphics.FONT_XTINY, row, Graphics.TEXT_JUSTIFY_CENTER);
  }

  function onUpdate(dc) {
    var w = dc.getWidth();
    var h = dc.getHeight();
    dc.setColor(foreground(), background());
    dc.clear();
    dc.drawText(w / 2, h * 0.14, Graphics.FONT_SMALL, "HOME", Graphics.TEXT_JUSTIFY_CENTER);
    if (!App.getApp().isLoggedIn()) {
      dc.drawText(w / 2, h * 0.4, Graphics.FONT_XTINY, "Sign in on your phone", Graphics.TEXT_JUSTIFY_CENTER);
      dc.drawText(w / 2, h * 0.68, Graphics.FONT_XTINY, "Tap / Select to sign in", Graphics.TEXT_JUSTIFY_CENTER);
      return;
    }
    var locks = Hass.getHomeCounts(Hass.TYPE_LOCK, Hass.STATE_LOCKED);
    var lights = Hass.getHomeCounts(Hass.TYPE_LIGHT, Hass.STATE_ON);
    var fans = Hass.getHomeCounts(Hass.TYPE_FAN, Hass.STATE_ON);
    var doorText = "Not configured";
    if (locks[0] > 0) {
      doorText = locks[1] == locks[0] ? "All locked" : (locks[0] - locks[1] - locks[2]) + " unlocked";
      if (locks[2] > 0) { doorText = (locks[0] - locks[1] - locks[2]) + " unlocked / " + locks[2] + " ?"; }
    }
    drawRow(dc, h * 0.32, "Doors", doorText, locks[0] == 0 || locks[1] != locks[0]);
    drawRow(dc, h * 0.45, "Lights", Hass.getCountText(lights), lights[1] > 0 || lights[2] > 0);
    drawRow(dc, h * 0.58, "Fans", Hass.getCountText(fans), fans[1] > 0 || fans[2] > 0);
    dc.setColor(isDark() ? Graphics.COLOR_LT_GRAY : Graphics.COLOR_DK_GRAY, background());
    var stamp = "Cached - refresh";
    if (Hass.lastRefresh != null) {
      stamp = "Updated " + (Time.now().value() - Hass.lastRefresh.value()) + "s ago";
    }
    if (Hass.refreshFailed) { stamp = "Refresh failed - cached"; }
    dc.drawText(w / 2, h * 0.72, Graphics.FONT_XTINY, stamp, Graphics.TEXT_JUSTIFY_CENTER);
    dc.drawText(w / 2, h * 0.82, Graphics.FONT_XTINY, "Tap / Select: controls", Graphics.TEXT_JUSTIFY_CENTER);
  }
}
