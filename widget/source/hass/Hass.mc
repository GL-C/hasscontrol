using Toybox.Application as App;
using Toybox.WatchUi as Ui;
using Toybox.System;
using Toybox.Timer;
using Toybox.Lang;

using Utils;

module Hass {
  const STORAGE_KEY = "Hass/entities";

  var lastRefresh = null;
  var refreshFailed = false;
  var _offQueue = new [0];
  var _offBusy = false;
  var _bulkType = null;
  var _refreshHadError = false;
  var _refreshBusy = false;

  // [total, matching state, unknown/transitional]. Never treat unavailable as off.
  function cancelPendingWork() {
    _entitiesToRefresh = new [0];
    _transitionalEntities = new [0];
    _offQueue = new [0];
    _offBusy = false;
    _refreshTimer.stop();
    _refreshBusy = false;
  }

  function getHomeCounts(type, state) {
    var counts = [0, 0, 0];
    var entities = getEntitiesByTypes([type]);
    for (var i = 0; i < entities.size(); i++) {
      counts[0] += 1;
      var value = entities[i].getState();
      if (value == state) { counts[1] += 1; }
      if (value == null || value == STATE_UNKNOWN || entities[i].isTransitional()) { counts[2] += 1; }
    }
    return counts;
  }

  function getCountText(counts) {
    if (counts[0] == 0) { return "Not configured"; }
    var text = counts[1] + " on";
    if (counts[2] > 0) { text += " / " + counts[2] + " unknown"; }
    return text;
  }

  // Only explicitly imported lights and fans. Excludes switches, locks and automations.
  // Send turn_off even for cached off/unknown states; the cache may be stale.
  function getAllOffTargets() {
    var targets = new [0];
    var entities = getEntitiesByTypes([TYPE_LIGHT, TYPE_FAN]);
    for (var i = 0; i < entities.size(); i++) {
      if (!entities[i].isExternal()) { targets.add(entities[i]); }
    }
    return targets;
  }

  function getDoorText(counts) {
    if (counts[0] == 0) { return "Not configured"; }
    var text = counts[1] == counts[0] ? "All locked" : (counts[0] - counts[1] - counts[2]) + " unlocked";
    if (counts[2] > 0) { text += " / " + counts[2] + " unknown"; }
    return text;
  }

  function getGroupTargets(type) {
    var targets = new [0];
    if (type != TYPE_LIGHT && type != TYPE_FAN && type != TYPE_LOCK) { return targets; }
    var entities = getEntitiesByTypes([type]);
    for (var i = 0; i < entities.size(); i++) {
      if (!entities[i].isExternal()) { targets.add(entities[i]); }
    }
    return targets;
  }

  function turnOffLightsAndFans() { runGroupAction(null); }

  function runGroupAction(type) {
    if (_offBusy || _refreshBusy) {
      App.getApp().viewController.showError("Refreshing status\nTry again shortly");
      return;
    }
    _offQueue = type == null ? getAllOffTargets() : getGroupTargets(type);
    _bulkType = type;
    if (_offQueue.size() == 0) {
      App.getApp().viewController.showError("Import devices\nfrom Settings first");
      return;
    }
    _offBusy = true;
    App.getApp().viewController.showLoader(type == TYPE_LOCK ? "Locking all" : "Turning off");
    _onAllOffCompleted(null, null);
  }

  function _onAllOffCompleted(error, data) {
    if (!_offBusy) { return; }
    if (error != null) {
      _offQueue = new [0];
      _offBusy = false;
      App.getApp().viewController.showError(error);
      refreshAllEntities(true);
      return;
    }
    if (_offQueue.size() > 0) {
      var entity = _offQueue[0];
      _offQueue.remove(entity);
      var domain = entity.getType() == TYPE_LOCK ? "lock" : (entity.getType() == TYPE_LIGHT ? "light" : "fan");
      var action = _bulkType == TYPE_LOCK ? Client.ENTITY_ACTION_LOCK : Client.ENTITY_ACTION_TURN_OFF;
      client.setEntityState(entity.getId(), domain, action, Utils.method(Hass, :_onAllOffCompleted));
      return;
    }
    _offBusy = false;
    // Read back actual states rather than claiming service acceptance means off.
    refreshAllEntities(true);
  }

  var client = null;
  var _entities = new [0];
  var _entitiesToRefresh = new [0];
  var _transitionalEntities =  new [0];
  var _continueRefreshOnError = false;
  var _refreshTimer = new Timer.Timer();

  function initClient() {
    client = new Client();
  }

  function getGroup() {
    var group = App.Properties.getValue("group");

    if (group == null || group.length() == 0) {
      return null;
    }

    if (group.find(".") == null) {
      group = "group." + group;
    }

    return group;
  }

  function getEntities() {
    return _entities;
  }

  function getEntitiesByTypes(types) {
    var entities = new [0];

    for (var eI = 0; eI < _entities.size(); eI++) {
      var match = false;

      for (var tI = 0; tI < types.size(); tI++) {
        if (_entities[eI].getType() == types[tI]) {
          match = true;
          break;
        }
      }

      if (match) {
        entities.add(_entities[eI]);
      }
    }

    return entities;
  }

  function getEntity(id) {
    var entity = null;

    for (var i = 0; i < _entities.size(); i++) {
      if (_entities[i].getId().equals(id)) {
        entity = _entities[i];
        break;
      }
    }

    return entity;
  }

  function storeEntities() {
    var entities = new [0];

    for (var i = 0; i < _entities.size(); i++) {
      if (_entities[i].isExternal()) {
        continue;
      }
      entities.add(_entities[i].toDict());
    }

    App.Storage.setValue(STORAGE_KEY, entities);
  }

  function loadScenesFromSettings() {
    var scenes = Utils.getScenesFromSettings();

    // first remove all external scenes to make sure we are not persisting any old scenes
    var entitiesToRemove = new [0];
    for (var i = 0; i < _entities.size(); i++) {
      if (_entities[i].isExternal()) {
        entitiesToRemove.add(_entities[i]);
      }
    }
    for (var i = 0; i < entitiesToRemove.size(); i++) {
      _entities.remove(entitiesToRemove[i]);
    }
    entitiesToRemove = null;

    for (var i = 0; i < scenes.size(); i++) {
      var entity = getEntity(scenes[i][0]);

      if (entity != null) {
        // We only set the name if it's different than the id
        if (!scenes[i][0].equals(scenes[i][1])) {
          entity.setName(scenes[i][1]);
        }
      } else {
        _entities.add(new Entity({
          :id => scenes[i][0],
          :name => scenes[i][1],
          :state => "scening",
          :ext => true
        }));
      }
    }
  }

  function loadStoredEntities() {
    var entities = App.Storage.getValue(STORAGE_KEY);

    _entities = new [0];

    if (entities == null) {
      System.println("loadStoredEntities: no stored entities found");
      return;
    }

    System.println("loadStoredEntities: loading " + entities.size() + " entities from storage");
    for (var i = 0; i < entities.size(); i++) {
      var entity = Entity.createFromDict(entities[i]);
      // Filter out null entities (from corrupted or invalid data)
      if (entity != null) {
        _entities.add(entity);
      } else {
        System.println("loadStoredEntities: skipped null entity at index " + i);
      }
    }

    loadScenesFromSettings();

    System.println("Loaded entities: " + _entities.size() + " total");
  }

  function _onReceiveEntity(err, data) {
    if (err != null) {
      if (data != null && data[:context] != null && data[:context][:entity] != null) {
        data[:context][:entity].setState(STATE_UNKNOWN);
      }
      if (data != null && data[:context] != null && data[:context][:callback] != null) {
        data[:context][:callback].invoke(err, null);
      } else {
        App.getApp().viewController.showError(err);
      }
      return;
    }

    // Validate data structure before proceeding
    if (data == null || data[:body] == null || data[:body]["entity_id"] == null) {
      System.println("Invalid entity data received");
      if (data != null && data[:context] != null && data[:context][:callback] != null) {
        data[:context][:callback].invoke(new Error(Error.ERROR_UNKNOWN), null);
      }
      return;
    }

    var entity = getEntity(data[:body]["entity_id"]);

    // If entity doesn't exist, skip processing but still invoke callback to continue chain
    if (entity == null) {
      System.println("Entity not found: " + data[:body]["entity_id"]);
      // Always try to invoke callback to prevent breaking the refresh chain
      if (data[:context] != null && data[:context][:callback] != null) {
        data[:context][:callback].invoke(null, null);
      } else {
        // Fallback: continue refreshing remaining entities if we're in a batch refresh
        _refreshPendingEntities(null, null);
      }
      return;
    }

    var name = null;
    var state = null;
    var sensorClass = null;
    var sensorClassStr = null;

    if (data[:body]["attributes"] != null) {
      name = data[:body]["attributes"]["friendly_name"];

      if (data[:body]["attributes"]["unit_of_measurement"] != null) {
        state = data[:body]["state"] + data[:body]["attributes"]["unit_of_measurement"];
      } else {
        state = data[:body]["state"];
      }

      if (data[:body]["attributes"]["device_class"] != null) {
        sensorClassStr = data[:body]["attributes"]["device_class"];
        if (sensorClassStr.find("temperature") != null) {
          sensorClass = SENSOR_TEMPERATURE;
        } else if (sensorClassStr.find("humidity") != null) {
          sensorClass = SENSOR_HUMIDITY;
        } else if (sensorClassStr.find("carbon_dioxide") != null) {
          sensorClass = SENSOR_CO2;
        } else if (sensorClassStr.find("pm25") != null) {
          sensorClass = SENSOR_PM;
        } else if (sensorClassStr.find("pm10") != null) {
          sensorClass = SENSOR_PM;
        } else if (sensorClassStr.find("energy") != null) {
          sensorClass = SENSOR_ENERGY;
        } else if (sensorClassStr.find("water") != null) {
          sensorClass = SENSOR_WATER;
        } else if (sensorClassStr.find("gas") != null) {
          sensorClass = SENSOR_GAS;
        }
      } else {
        sensorClass = SENSOR_OTHER;
      }
    } else {
      state = data[:body]["state"];
      sensorClass = SENSOR_OTHER;
    }

    if (name != null) {
      entity.setName(name);
    }

    if (state != null) {
      entity.setState(state);
    } else {
      entity.setState(Hass.STATE_UNKNOWN);
    }

    if (sensorClass != null) {
      entity.setSensorClass(sensorClass);
    }

    if (data[:context] != null && data[:context][:callback] != null) {
      data[:context][:callback].invoke(null, entity);
    }
  }

  function refreshEntity(entity, callback) {
    client.getEntity(
      entity.getId(),
      {
        :entity => entity,
        :callback => callback
      },
      Utils.method(Hass, :_onReceiveEntity)
    );
  }

  function _refreshPendingEntities(error, noop) {
    if (error != null) { _refreshHadError = true; refreshFailed = true; }
    if (error != null && !_continueRefreshOnError) {
      _refreshBusy = false;
      App.getApp().viewController.removeLoader();
      App.getApp().viewController.showError(error);

      // We need to finalize with reading the scenes from settings again,
      // so that the name config takes precedence
      loadScenesFromSettings();

      storeEntities();

      Ui.requestUpdate();
      return;
    }

    if(noop != null && noop.isTransitional()){
      _transitionalEntities.add(noop);
      _refreshTimer.start(Utils.method(Hass, :_refreshTransitionalEntities), 2000, false);
    }

    if (_entitiesToRefresh.size() > 0) {
      var entity = _entitiesToRefresh[0];

      _entitiesToRefresh.remove(entity);

      // Add null check for entity before refreshing
      if (entity != null) {
        refreshEntity(entity, Utils.method(Hass, :_refreshPendingEntities));
      } else {
        // Skip null entity and continue with next
        _refreshPendingEntities(null, null);
      }
    } else {
      _refreshBusy = false;
      refreshFailed = _refreshHadError;
      if (!_refreshHadError) { lastRefresh = Toybox.Time.now(); }
      // We need to finalize with reading the scenes from settings again,
      // so that the name config takes precedence
      loadScenesFromSettings();

      storeEntities();

      Ui.requestUpdate();

      App.getApp().viewController.removeLoader();
    }
  }

  function refreshAllEntities(continueOnError) {
    if (_refreshBusy) { return; }
    _refreshBusy = true;
    _refreshHadError = false;
    _entitiesToRefresh = new [0];
    _continueRefreshOnError = continueOnError == true;

    for (var i = 0; i < _entities.size(); i++) {
      _entitiesToRefresh.add(_entities[i]);
    }

    _refreshPendingEntities(null, null);
  }

  function _refreshTransitionalEntities(){
    _entitiesToRefresh.addAll(_transitionalEntities);
    _transitionalEntities = new [0];
    _refreshPendingEntities(null, null);
  }

  function _onReceiveEntities(err, data) {
    if (err != null) {
      App.getApp().viewController.removeLoader();
      App.getApp().viewController.showError(err);
      return;
    }

    // Validate data structure
    if (data == null || data[:body] == null || data[:body]["attributes"] == null || data[:body]["attributes"]["entity_id"] == null) {
      System.println("Invalid entities data received");
      App.getApp().viewController.removeLoader();
      App.getApp().viewController.showError("Invalid\ngroup\nresponse");
      return;
    }

    var entities = data[:body]["attributes"]["entity_id"];

    _entities = new [0];

    for (var i = 0; i < entities.size(); i++) {
      var entity = getEntity(entities[i]);

      if (entity == null) {
        _entities.add(new Entity({
          :id => entities[i],
          :name => entities[i],
          :state => null,
          :sensorClass => null
        }));
      } else {
        entity.setExternal(false);
      }
    }

    loadScenesFromSettings();

    refreshAllEntities(false);
  }

  function importEntities() {
    var group = getGroup();

    if (group == null) {
      App.getApp().viewController.showError("Group\nnot\nconfigured");
      return;
    }

    App.getApp().viewController.showLoader("Refreshing");

    client.getEntity(group, null, Utils.method(Hass, :_onReceiveEntities));
  }

  function _onBatteryUpdate(err, data) {
      if (err != null) {
        System.println("Battery update error: " + err.toShortString());
      }
  }

  function reportBatteryValue(entity_id) {
    client.reportBatteryValue(entity_id, Utils.method(Hass, :_onBatteryUpdate));
  }

  function onToggleEntityStateCompleted(error, data) {
    if (error != null) {
      App.getApp().viewController.removeLoaderImmediate();
      App.getApp().viewController.showError(error);
      return;
    }

    // Validate data structure
    if (data == null || data[:context] == null || data[:context][:entityId] == null) {
      System.println("Invalid toggle entity response");
      App.getApp().viewController.removeLoader();
      return;
    }

    var entity = getEntity(data[:context][:entityId]);
    if (entity != null) {
      refreshEntity(entity, Utils.method(Hass, :_onActionReadback));
      return;
    }

    App.getApp().viewController.removeLoader();

    // Check if we should exit after action
    if (App.Properties.getValue("closeAfterAction")) {
      // Small delay before exiting to ensure UI updates are seen by user
      var exitTimer = new Timer.Timer();
      exitTimer.start(Utils.method(Hass, :exitApplication), 2000, false);
    }
  }

  function _onActionReadback(error, entity) {
    if (error != null) {
      storeEntities();
      refreshFailed = true;
      App.getApp().viewController.showError(error);
      Ui.requestUpdate();
      return;
    }
    if (entity != null && entity.isTransitional()) {
      _transitionalEntities.add(entity);
      _refreshTimer.start(Utils.method(Hass, :_refreshTransitionalEntities), 2000, false);
    }
    storeEntities();
    App.getApp().viewController.removeLoader();
    Ui.requestUpdate();
    if (App.Properties.getValue("closeAfterAction") && (entity == null || !entity.isTransitional())) {
      _refreshTimer.start(Utils.method(Hass, :exitApplication), 2000, false);
    }
  }

  function exitApplication() {
    System.exit();
  }

  function toggleEntityState(entity) {
    var entityId = entity.getId();
    var currentState = entity.getState();
    var entityType = null;
    var action = null;
    var loadingText = "Loading";

    if (entity.getType() == Hass.TYPE_BINARY_SENSOR) {
        // binary_sensor cannot be set, only read
        return;
    }
    if (entity.getType() == Hass.TYPE_SENSOR) {
      // binary_sensor cannot be set, only read
      return;
    }

    if (entity.getType() == Hass.TYPE_SCRIPT) {
      action = Client.ENTITY_ACTION_TURN_ON;
      loadingText = "Running";
    } else if (entity.getType() == Hass.TYPE_LOCK) {
      if (currentState == Hass.STATE_UNLOCKED) {
        action = Client.ENTITY_ACTION_LOCK;
        loadingText = "Locking";
      } else if (currentState == Hass.STATE_LOCKED) {
        action = Client.ENTITY_ACTION_UNLOCK;
        loadingText = "Unlocking";
      }
    } else if (entity.getType() == Hass.TYPE_VALVE) {
      if (currentState == Hass.STATE_OPEN) {
        action = Client.ENTITY_ACTION_CLOSE;
        loadingText = "Closing";
      } else if (currentState == Hass.STATE_CLOSED) {
        action = Client.ENTITY_ACTION_OPEN;
        loadingText = "Opening";
      }
    } else if (entity.getType() == Hass.TYPE_COVER) {
      action = Client.ENTITY_ACTION_COVER_TOGGLE;
      loadingText = "Toggling";
    } else if (entity.getType() == Hass.TYPE_BUTTON || entity.getType() == Hass.TYPE_INPUT_BUTTON) {
      action = Client.ENTITY_ACTION_PRESS;
      loadingText = "Pressing";
    } else {
      if (currentState == Hass.STATE_ON) {
        action = Client.ENTITY_ACTION_TURN_OFF;
        loadingText = "Turning off";
      } else if (currentState == Hass.STATE_OFF) {
        action = Client.ENTITY_ACTION_TURN_ON;
        loadingText = "Turning on";
      }
    }

    if (entity.getType() == Hass.TYPE_SCENE) {
      entityType = "scene";
      action = null;
    } else if (entity.getType() == Hass.TYPE_LIGHT) {
      entityType = "light";
    } else if (entity.getType() == Hass.TYPE_SWITCH) {
      entityType = "switch";
    } else if (entity.getType() == Hass.TYPE_VALVE) {
      entityType = "valve";
    } else if (entity.getType() == Hass.TYPE_AUTOMATION) {
      entityType = "automation";
    } else if (entity.getType() == Hass.TYPE_SCRIPT) {
      entityType = "script";
    } else if (entity.getType() == Hass.TYPE_LOCK) {
      entityType = "lock";
    } else if (entity.getType() == Hass.TYPE_COVER) {
      entityType = "cover";
    } else if (entity.getType() == Hass.TYPE_FAN) {
      entityType = "fan";
    } else if (entity.getType() == Hass.TYPE_INPUT_BOOLEAN) {
      entityType = "input_boolean";
    } else if (entity.getType() == Hass.TYPE_BUTTON) {
      entityType = "button";
    } else if (entity.getType() == Hass.TYPE_INPUT_BUTTON) {
      entityType = "input_button";
    }

    if (action == null && entityType != "scene") {
      App.getApp().viewController.showError("State unknown / moving\nRefresh before controlling");
      return;
    }

    App.getApp().viewController.showLoader(loadingText);

    if (entityType == "scene") {
      client.activateScene(entityId, Utils.method(Hass, :onToggleEntityStateCompleted));
    } else {
      client.setEntityState(entityId, entityType, action, Utils.method(Hass, :onToggleEntityStateCompleted));
    }
  }
}

class HassController {



  // function _refreshPendingEntities() {
  //   var entity = null;

  //   for (var i = 0; i < _entities.size(); i++) {
  //     if (_entities[i].getState() == null) {
  //       entity = _entities[i];
  //       break;
  //     }
  //   }

  //   if (entity != null) {
  //     client.getEntity(entity.getId(), method(:onReceiveRefreshedEntity));
  //   } else {
  //     System.println(_entities);
  //     storeEntities();
  //     App.getApp().viewController.removeLoader();
  //   }
  // }

  // function onReceiveEntities(err, data) {
  //   if (err == null) {
  //     var entities = data[:body]["attributes"]["entity_id"];

  //     _entities = new [0];

  //     for (var i = 0; i < entities.size(); i++) {
  //       _entities.add(new Entity({
  //         :id => entities[i],
  //         :name => "",
  //         :state => null
  //       }));
  //     }

  //     _refreshPendingEntities();
  //   } else {
  //     App.getApp().viewController.showError(err);
  //   }
  // }

  // function refreshAllEntityStates() {
  //     for (var i = 0; i < _entities.size(); i++) {
  //       _entities[i].setState(null);
  //     }

  //     _refreshPendingEntities();
  // }
}