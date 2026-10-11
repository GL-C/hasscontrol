using Toybox.Communications as Comm;
using Toybox.Application as App;
using Toybox.StringUtil;
using Hass;
using Utils;

(:glance)
module Hass {
    const AUTH_ENDPOINT = "/auth/authorize";
    const TOKEN_ENDPOINT = "/auth/token";

    class Client extends Hass.OAuthClient {
        static enum {
            ENTITY_ACTION_TURN_ON,
            ENTITY_ACTION_TURN_OFF,
            ENTITY_ACTION_LOCK,
            ENTITY_ACTION_UNLOCK,
            ENTITY_ACTION_CLOSE,
            ENTITY_ACTION_OPEN,
            ENTITY_ACTION_COVER_TOGGLE,
            ENTITY_ACTION_PRESS
        }

        hidden var _baseUrl;
        hidden var _baseUrlIsValid;

        function initialize() {
            refreshBaseUrl();

            var savedHost = App.Storage.getValue("auth_host");
            // Existing unbound credentials also require re-login during migration.
            if ((savedHost != null && !savedHost.equals(_baseUrl))
                || (savedHost == null && App.Storage.getValue("refresh_token") != null)) {
                new OauthCredentials().clear();
                App.Storage.deleteValue("Hass/entities");
            }
            App.Storage.setValue("auth_host", _baseUrl);

            OAuthClient.initialize({
                :authUrl => _baseUrl + AUTH_ENDPOINT,
                :tokenUrl => _baseUrl + TOKEN_ENDPOINT,
                :clientId => "https://hasscontrol",
                :redirectUrl => "https://hasscontrol/hass/auth_callback"
            });
        }

        function refreshBaseUrl() {
            var newUrl = App.Properties.getValue("host");
            _baseUrl = "";
            _baseUrlIsValid = false;
            if (newUrl == null) { return; }
            var chars = newUrl.toCharArray();

            if (chars.size() < 8) {
                _baseUrlIsValid = false;
                return;
            }

            // strip potential trailing slash
            if (chars[chars.size() - 1] == '/') {
                chars = chars.slice(0, chars.size() - 1);
            }

            // verify that host is starting with "https://"
            if (StringUtil.charArrayToString(chars.slice(0, 8)).equals("https://")) {
                _baseUrlIsValid = true;
            } else {
                _baseUrlIsValid = false;
            }

            _baseUrl = StringUtil.charArrayToString(chars);
            // Credentials are for a single HA origin. Reject userinfo, paths and query strings.
            var authority = StringUtil.charArrayToString(chars.slice(8, chars.size()));
            if (authority.length() == 0 || authority.find("/") != null || authority.find("@") != null
                || authority.find("?") != null || authority.find("#") != null || authority.find(" ") != null) {
                _baseUrlIsValid = false;
            }
        }

        function onSettingsChanged() {
            var oldUrl = _baseUrl;
            refreshBaseUrl();
            if (!oldUrl.equals(_baseUrl)) {
                logout();
                App.Storage.deleteValue("Hass/entities");
                Hass.loadStoredEntities();
                Hass.lastRefresh = null;
                Hass.refreshFailed = false;
            }
            setAuthUrl(_baseUrl + AUTH_ENDPOINT);
            setTokenUrl(_baseUrl + TOKEN_ENDPOINT);
            App.Storage.setValue("auth_host", _baseUrl);
            OAuthClient.onSettingsChanged();
        }

        function validateSettings(errorCallback) {
            var error = null;

            if (!System.getDeviceSettings().phoneConnected) {
                error = new Error(OAuthError.ERROR_PHONE_NOT_CONNECTED);
            }

            if (!_baseUrlIsValid) {
                error = new RequestError(ERROR_INVALID_URL);
            }

            if (error != null && errorCallback != null) {
                errorCallback.invoke(error, null);
            }

            return error;
        }


        function activateScene(sceneId, callback) {
            if (validateSettings(callback) != null) {
                return;
            }

            System.println("Send activate scene request");

            makeAuthenticatedWebRequest(
                _baseUrl + "/api/services/scene/turn_on",
                {
                    "entity_id" => sceneId
                },
                {
                    :method => Comm.HTTP_REQUEST_METHOD_POST,
                    :context => { :entityId => sceneId }
                },
                callback
            );
        }

        function getEntity(entityId, context, callback) {
            if (validateSettings(callback) != null) {
                return;
            }

            if (context == null) {
                context = {};
            }

            if (context[:resource] == null) {
                context[:resource] = entityId;
            }

            makeAuthenticatedWebRequest(
                _baseUrl + "/api/states/" + entityId,
                {},
                {
                    :context => context
                },
                callback
            );
        }

        function setEntityState(entityId, entityType, action, callback) {
            if (validateSettings(callback) != null) {
                return;
            }

            var serviceAction = "turn_on";
            var newState = null;

            if (action == Client.ENTITY_ACTION_TURN_ON) {
                serviceAction = "turn_on";
                newState = "on";
            } else if (action == Client.ENTITY_ACTION_TURN_OFF) {
                serviceAction = "turn_off";
                newState = "off";
            } else if (action == Client.ENTITY_ACTION_CLOSE) {
                serviceAction = "close";
                newState = "closed";
            } else if (action == Client.ENTITY_ACTION_COVER_TOGGLE) {
                serviceAction = "toggle";
            } else if (action == Client.ENTITY_ACTION_OPEN) {
                serviceAction = "open";
                newState = "open";
            } else if (action == Client.ENTITY_ACTION_LOCK) {
                serviceAction = "lock";
                newState = "locked";
            } else if (action == Client.ENTITY_ACTION_UNLOCK) {
                serviceAction = "unlock";
                newState = "unlocked";
            } else if (action == Client.ENTITY_ACTION_PRESS) {
                serviceAction = "press";
                newState = "timestamp"; // button doesn't have a real state - the state is the time stamp of it's last triggering
            }

            makeAuthenticatedWebRequest(
                _baseUrl + "/api/services/" + entityType + "/" + serviceAction,
                {
                    "entity_id" => entityId
                },
                {
                    :method => Comm.HTTP_REQUEST_METHOD_POST,
                    :context => {
                        :entityId => entityId,
                        :state => newState,
                    }
                },
                callback
            );
        }

        function reportBatteryValue(entity_id, callback) {
            var state = System.getSystemStats().battery.toNumber();
            makeAuthenticatedWebRequest(
                _baseUrl + "/api/states/sensor." + entity_id,
                {
                    "state" => state,
                    "attributes" => {
                        "unit_of_measurement" => "%",
                        "device_class" => "battery",
                        "state_class" => "measurement"
                    }
                },
                {
                    :method => Comm.HTTP_REQUEST_METHOD_POST,
                    :context => {
                        :entityId => entity_id,
                        :state => state,
                    }
                },
                callback
            );
        }
    }
}
