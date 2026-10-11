using Toybox.Test;
using Toybox.Application as App;
using Hass;

(:test)
function testDomainMustBePrefix(logger) {
  var light = new Hass.Entity({ :id => "light.porch", :name => "Porch", :state => "on" });
  var misleading = new Hass.Entity({ :id => "sensor.light.fake", :name => "Sensor", :state => "off" });
  Test.assertEqual(light.getType(), Hass.TYPE_LIGHT);
  Test.assertEqual(misleading.getType(), Hass.TYPE_SENSOR);
  return true;
}

(:test)
function testUnavailableIsNeverOff(logger) {
  var saved = Hass._entities;
  Hass._entities = [
    new Hass.Entity({ :id => "light.a", :state => "on" }),
    new Hass.Entity({ :id => "light.b", :state => "off" }),
    new Hass.Entity({ :id => "light.c", :state => "unavailable" })
  ];
  var counts = Hass.getHomeCounts(Hass.TYPE_LIGHT, Hass.STATE_ON);
  Hass._entities = saved;
  Test.assertEqual(counts[0], 3);
  Test.assertEqual(counts[1], 1);
  Test.assertEqual(counts[2], 1);
  return true;
}

(:test)
function testMovingLockIsNotLocked(logger) {
  var saved = Hass._entities;
  Hass._entities = [new Hass.Entity({ :id => "lock.front", :state => "locking" })];
  var counts = Hass.getHomeCounts(Hass.TYPE_LOCK, Hass.STATE_LOCKED);
  Hass._entities = saved;
  Test.assertEqual(counts[1], 0);
  Test.assertEqual(counts[2], 1);
  return true;
}

(:test)
class CallbackHarness extends Hass.OAuthClient {
  var calls;
  function initialize() {
    _tokenCallbacks = new [0];
    _oauthState = "current-login";
    calls = 0;
  }
  function record(error, context) { calls += 1; }
  function enqueueDuringCallback(error, context) {
    calls += 1;
    addTokenCallback(method(:record), {});
  }
}

(:test)
function testAllTokenWaitersComplete(logger) {
  var client = new CallbackHarness();
  client.addTokenCallback(client.method(:record), {});
  client.addTokenCallback(client.method(:record), {});
  client.addTokenCallback(client.method(:record), {});
  client.fireTokenCallbacks(null);
  Test.assertEqual(client.calls, 3);
  client.fireTokenCallbacks(null);
  Test.assertEqual(client.calls, 3);
  return true;
}

(:test)
function testReentrantCallbacksWaitForNextCycle(logger) {
  var client = new CallbackHarness();
  client.addTokenCallback(client.method(:enqueueDuringCallback), {});
  client.fireTokenCallbacks(null);
  Test.assertEqual(client.calls, 1);
  client.fireTokenCallbacks(null);
  Test.assertEqual(client.calls, 2);
  return true;
}

(:test)
function testOAuthCallbackMustMatchCurrentLogin(logger) {
  var client = new CallbackHarness();
  Test.assert(client.matchesOAuthState("current-login"));
  Test.assert(!client.matchesOAuthState(null));
  Test.assert(!client.matchesOAuthState("previous-login"));
  return true;
}

(:test)
function testAllOffOnlyTargetsImportedLightsAndFans(logger) {
  var saved = Hass._entities;
  Hass._entities = [
    new Hass.Entity({ :id => "light.off", :state => "off" }),
    new Hass.Entity({ :id => "fan.unknown", :state => "unavailable" }),
    new Hass.Entity({ :id => "switch.fridge", :state => "on" }),
    new Hass.Entity({ :id => "lock.front", :state => "unlocked" }),
    new Hass.Entity({ :id => "light.external", :state => "on", :ext => true })
  ];
  var targets = Hass.getAllOffTargets();
  Hass._entities = saved;
  Test.assertEqual(targets.size(), 2);
  Test.assertEqual(targets[0].getId(), "light.off");
  Test.assertEqual(targets[1].getId(), "fan.unknown");
  return true;
}
