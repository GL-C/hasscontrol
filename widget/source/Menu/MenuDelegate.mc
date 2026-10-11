using Toybox.WatchUi as Ui;
using Toybox.Application as App;
using Toybox.System;
using Hass;

class MenuDelegate extends Ui.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) {
        App.getApp().resetInactivityTimer();
        var itemId = item.getId();

        if (itemId == MenuController.MENU_HOME) {
            Ui.popView(Ui.SLIDE_IMMEDIATE);
            App.getApp().viewController.switchHomeView();
            return true;
        }
        if (itemId == MenuController.MENU_ALL_OFF) {
            Ui.popView(Ui.SLIDE_IMMEDIATE);
            Hass.turnOffLightsAndFans();
            return true;
        }
        if (itemId == MenuController.MENU_REFRESH_STATUS) {
            Ui.popView(Ui.SLIDE_IMMEDIATE);
            Hass.refreshAllEntities(true);
            return true;
        }
        if (itemId == MenuController.MENU_LIGHTS || itemId == MenuController.MENU_FANS || itemId == MenuController.MENU_LOCKS) {
            var type = Hass.TYPE_LIGHT;
            if (itemId == MenuController.MENU_FANS) { type = Hass.TYPE_FAN; }
            if (itemId == MenuController.MENU_LOCKS) { type = Hass.TYPE_LOCK; }
            var controller = new EntityListController([type]);
            Ui.popView(Ui.SLIDE_IMMEDIATE);
            Ui.pushView(new EntityListView(controller), new EntityListDelegate(controller), Ui.SLIDE_IMMEDIATE);
            return true;
        }
        if (itemId == MenuController.MENU_START_HOME) {
            App.getApp().setStartView(HassControlApp.HOME_VIEW);
            Ui.popView(Ui.SLIDE_IMMEDIATE);
            Ui.popView(Ui.SLIDE_IMMEDIATE);
            App.getApp().menu.showSettingsMenu();
            return true;
        }

        if (itemId == MenuController.MENU_SWITCH_TO_ENTITIES) {
            Ui.popView(Ui.SLIDE_IMMEDIATE);

            App.getApp().viewController.switchEntityView();
            return true;
        }
        if (itemId == MenuController.MENU_SWITCH_TO_SCENES) {
            Ui.popView(Ui.SLIDE_IMMEDIATE);

            App.getApp().viewController.switchSceneView();
            return true;
        }
        if (itemId == MenuController.MENU_SWITCH_TO_ENTITIES_SCENES) {
            Ui.popView(Ui.SLIDE_IMMEDIATE);

            App.getApp().viewController.switchEntitySceneView();
            return true;
        }
        if (itemId == MenuController.MENU_LOGOUT) {
            Ui.popView(Ui.SLIDE_IMMEDIATE);
            Ui.popView(Ui.SLIDE_IMMEDIATE);
            App.getApp().logout();
            return true;
        }
        if (itemId == MenuController.MENU_LOGIN) {
            Ui.popView(Ui.SLIDE_IMMEDIATE);
            App.getApp().login();
            return true;
        }
        if (itemId == MenuController.MENU_ENTER_SETTINGS) {
            App.getApp().menu.showSettingsMenu();
            return true;
        }
        if (itemId == MenuController.MENU_SELECT_START_VIEW) {
            App.getApp().menu.showSelectStartViewMenu();
            return true;
        }
        if (itemId == MenuController.MENU_REFRESH_ENTITIES) {
            Hass.importEntities();
            return true;
        }

        if (itemId == MenuController.MENU_SELECT_START_VIEW_ENTITIES) {
            App.getApp().setStartView(HassControlApp.ENTITIES_VIEW);

            // TOTO: This is a dirty hack to get the parent menu to re render
            Ui.popView(Ui.SLIDE_IMMEDIATE);
            Ui.popView(Ui.SLIDE_IMMEDIATE);
            App.getApp().menu.showSettingsMenu();
            return true;
        }
        if (itemId == MenuController.MENU_SELECT_START_VIEW_SCENES) {
            App.getApp().setStartView(HassControlApp.SCENES_VIEW);

            // TOTO: This is a dirty hack to get the parent menu to re render
            Ui.popView(Ui.SLIDE_IMMEDIATE);
            Ui.popView(Ui.SLIDE_IMMEDIATE);
            App.getApp().menu.showSettingsMenu();
            return true;
        }
        if (itemId == MenuController.MENU_SELECT_START_VIEW_ENTITIES_SCENES) {
            App.getApp().setStartView(HassControlApp.ENTITIES_SCENES_VIEW);

            // TOTO: This is a dirty hack to get the parent menu to re render
            Ui.popView(Ui.SLIDE_IMMEDIATE);
            Ui.popView(Ui.SLIDE_IMMEDIATE);
            App.getApp().menu.showSettingsMenu();
            return true;
        }

        /*
         * GLOBAL MENU OPTIONS
        */
        if (itemId == MenuController.MENU_BACK) {
            Ui.popView(Ui.SLIDE_IMMEDIATE);
            return true;
        }

        return false;
    }
}