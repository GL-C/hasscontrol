using Toybox.WatchUi as Ui;
using Toybox.Application as App;
using Toybox.Graphics;

(:glance)
class AppGlance extends Ui.GlanceView {
  function initialize() { GlanceView.initialize(); }
  function getLayout() { setLayout([]); }
  function onUpdate(dc) {
    var entities = App.Storage.getValue("Hass/entities");
    var lights = 0;
    var fans = 0;
    var locks = 0;
    var unlocked = 0;
    var unknown = 0;
    if (entities != null) {
      for (var i = 0; i < entities.size(); i++) {
        var entity = entities[i];
        if (entity == null || entity["id"] == null) { continue; }
        var id = entity["id"];
        var state = entity["state"];
        if (id.find("lock.") == 0) {
          locks += 1;
          if (state == "unlocked") { unlocked += 1; }
          else if (state != "locked") { unknown += 1; }
        } else if (id.find("light.") == 0 || id.find("fan.") == 0) {
          if (state == "on") {
            if (id.find("light.") == 0) { lights += 1; } else { fans += 1; }
          } else if (state != "off") { unknown += 1; }
        }
      }
    }
    var doors = "Doors: ?";
    if (locks > 0) { doors = unlocked > 0 ? unlocked + " unlocked" : "Doors locked"; }
    if (unknown > 0) { doors = "Unknown states: " + unknown; }
    dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
    dc.clear();
    dc.drawText(dc.getWidth() / 2, 0, Graphics.FONT_XTINY, "HOME (cached) " + doors, Graphics.TEXT_JUSTIFY_CENTER);
    dc.drawText(dc.getWidth() / 2, dc.getHeight() / 2, Graphics.FONT_XTINY,
      lights + " lights / " + fans + " fans on", Graphics.TEXT_JUSTIFY_CENTER);
  }
}
