using Toybox.Communications as Comm;
using Toybox.Application as App;
using Toybox.StringUtil;
using Toybox.Time;
using Toybox.Cryptography;

(:glance)
module Hass {
    class OAuthClient {
        hidden var _authUrl;
        hidden var _tokenUrl;
        hidden var _clientId;
        hidden var _redirectUrl;
        hidden var _credentials;

        hidden var _tokenCallbacks;

        hidden var _isLoggingIn;
        hidden var _isFetchingAccessToken;
        hidden var _additionalHeaderKey;
        hidden var _additionalHeaderValue;
        hidden var _sessionGeneration;
        hidden var _configuredToken;
        hidden var _oauthState;

        function initialize(options) {
            Comm.registerForOAuthMessages(method(:onReceiveCode));

            _authUrl = options[:authUrl];
            _tokenUrl = options[:tokenUrl];
            _clientId = options[:clientId];
            _redirectUrl = options[:redirectUrl];
            _credentials = new OauthCredentials();
            _tokenCallbacks = new [0];
            _sessionGeneration = 0;
            _oauthState = null;
            _configuredToken = App.Properties.getValue("accessToken");
            _isLoggingIn = false;
            _isFetchingAccessToken = false;
            _additionalHeaderKey = App.Properties.getValue("additional_header_key");
            _additionalHeaderValue = App.Properties.getValue("additional_header_value");
        }

        function onSettingsChanged() {
            var token = App.Properties.getValue("accessToken");
            if (token != _configuredToken) {
                // Invalidate pending work without clearing the newly supplied property.
                Hass.cancelPendingWork();
                _sessionGeneration += 1;
                _isFetchingAccessToken = false;
                _setIsLoggingIn(false);
                fireTokenCallbacks(new RequestError(401));
                _configuredToken = token;
            }
            _credentials.loadLongLivedToken();
            _additionalHeaderKey = App.Properties.getValue("additional_header_key");
            _additionalHeaderValue = App.Properties.getValue("additional_header_value");
        }

        function setAuthUrl(newUrl) {
            if (!_authUrl.equals(newUrl)) {
                logout();
            }

            _authUrl = newUrl;
        }

        function setTokenUrl(newUrl) {
            if (!_tokenUrl.equals(newUrl)) {
                logout();
            }

            _tokenUrl = newUrl;
        }

        function addTokenCallback(callback, context) {
            _tokenCallbacks.add({
                "callback" => callback,
                "context" => context
            });
        }

        function removeTokenCallback(callbackObject) {
            _tokenCallbacks.remove(callbackObject);
        }

        function fireTokenCallbacks(error) {
            // Drain a snapshot: removing from the live array skipped every other waiter.
            // New callbacks added while invoking belong to the next refresh cycle.
            var callbacks = _tokenCallbacks;
            _tokenCallbacks = new [0];
            for (var i = 0; i < callbacks.size(); i++) {
                callbacks[i]["callback"].invoke(error, callbacks[i]["context"]);
            }
        }

        function _setIsLoggingIn(isLoggingIn) {
            System.println("is logging in: " + isLoggingIn);
            _isLoggingIn = isLoggingIn;
            App.getApp().viewController.showLoginView(_isLoggingIn);
        }

        function isLoggedIn() {
            return _credentials.isLoggedIn();
        }

        function onReceiveTokens(code, data, context) {
            if (context == null || context[:generation] != _sessionGeneration) { return; }
            _setIsLoggingIn(false);

            _isFetchingAccessToken = false;

            if (code == 200 && data != null && data["access_token"] != null && data["expires_in"] != null) {
                _credentials.setExpires(data["expires_in"]);
                _credentials.setAccessToken(data["access_token"]);

                if (data["refresh_token"]) {
                    System.println("Saving refresh token");
                    _credentials.setRefreshToken(data["refresh_token"]);
                }

                System.println("Received tokens from home assistant");

                fireTokenCallbacks(null);
            } else {
                var error = new OAuthError(code);

                if (error.code == ERROR_TOKEN_REVOKED) {
                    logout();
                }

                System.println("Failed to complete token request, status " + code);
                // Do not log token endpoint response bodies.

                fireTokenCallbacks(error);
            }
        }

        function refreshToken(force) {
            if (_isLoggingIn) {
                return;
            }

            if (isLoggedIn() == false) {
                System.println("Not logged in, let's log in!");
                login(null);
                return;
            }

            if (_isFetchingAccessToken == true) {
                return;
            }

            if (_credentials.hasExpired() == true || force == true) {
                System.println("AccessToken has expired, lets refresh!");
                var refreshToken = _credentials.getRefreshToken();

                _isFetchingAccessToken = true;
                Comm.makeWebRequest(
                    _tokenUrl,
                    {
                        "grant_type" => "refresh_token",
                        "client_id" => _clientId,
                        "refresh_token" => refreshToken
                    },
                    {
                        :method => Comm.HTTP_REQUEST_METHOD_POST,
                        :context => { :generation => _sessionGeneration }
                    },
                    method(:onReceiveTokens)
                );
            } else {
                System.println("AccessToken still valid :)");
                fireTokenCallbacks(null);
            }
        }

        function getTokensFromCode(code) {
            if (_isFetchingAccessToken != true) {
                _isFetchingAccessToken = true;

                System.println("Fetching token from code");
                System.println(_tokenUrl);

                Comm.makeWebRequest(
                    _tokenUrl,
                    {
                        "grant_type" => "authorization_code",
                        "client_id" => _clientId,
                        "code" => code
                    },
                    {
                        :method => Comm.HTTP_REQUEST_METHOD_POST,
                        :context => { :generation => _sessionGeneration }
                    },
                    method(:onReceiveTokens)
                );
            }
        }

        function onReceiveCode(value) {
            if (!_isLoggingIn) { return; }
            if (value.data != null && value.data["code"] != null) {
                // Bind the phone callback to this login, including after logout/re-login.
                if (!matchesOAuthState(value.data["state"])) {
                    _oauthState = null;
                    _setIsLoggingIn(false);
                    fireTokenCallbacks(new RequestError(401));
                    return;
                }
                _oauthState = null;
                System.println("Received auth code from home assistant");
                getTokensFromCode(value.data["code"]);
            } else {
                var error = new OAuthError(value.responseCode);

                _setIsLoggingIn(false);

                fireTokenCallbacks(error);

                System.println("Failed to receive auth code!");
                System.println(error.toString());
            }
        }

        function login(callback) {
            if (callback != null) {
                addTokenCallback(callback, {});
            }

            if (isLoggedIn() == true) {
                System.println("Trying to login when we are already logged in");
                refreshToken(false);
                return;
            }

            if (_isLoggingIn) { return; }
            _setIsLoggingIn(true);

            if (!System.getDeviceSettings().phoneConnected) {
                var error = new OAuthError(OAuthError.ERROR_PHONE_NOT_CONNECTED);
                _setIsLoggingIn(false);

                fireTokenCallbacks(error);

                return;
            }

            _oauthState = StringUtil.convertEncodedString(Cryptography.randomBytes(16), {
                :fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
                :toRepresentation => StringUtil.REPRESENTATION_STRING_HEX
            });
            System.println("About to fire an oauth request!");
            Comm.makeOAuthRequest(
            _authUrl,
                {
                    "client_id" => _clientId,
                    "response_type"=>"code",
                    "scope"=>"public",
                    "redirect_uri"=> _redirectUrl,
                    "state" => _oauthState
                },
                _redirectUrl,
                Comm.OAUTH_RESULT_TYPE_URL,
                {"code"=>"code", "state"=>"state"}
            );
        }

        function matchesOAuthState(state) {
            return _oauthState != null && state != null && _oauthState.equals(state);
        }

        function logout() {
            Hass.cancelPendingWork();
            _oauthState = null;
            _sessionGeneration += 1;
            _credentials.clear();
            _configuredToken = "";
            _isFetchingAccessToken = false;
            _setIsLoggingIn(false);
            fireTokenCallbacks(new RequestError(401));
        }

        function onWebResponse(responseCode, body, context) {
            // Old session owners have already cancelled their queues and loaders.
            if (context[:generation] != _sessionGeneration) { return; }
            var error = null;

            if (responseCode < 200 || responseCode >= 300) {
                error = new RequestError(responseCode);

                if (error.code == ERROR_NOT_AUTHORIZED) {
                    // A rejected fixed token must not remain "logged in" forever.
                    // Preserve an OAuth refresh token so a later request can refresh.
                    if (_credentials.getRefreshToken() == null) {
                        _credentials.clear();
                    } else {
                        _credentials.setAccessToken(null);
                        _credentials.setExpires(null);
                    }
                }
                if (
                    error.code == ERROR_NOT_FOUND
                    && context[:context] != null
                    && context[:context][:resource] != null
                ) {
                    error.setContext(context[:context][:resource]);
                }
            }

            // Request context may include sensitive identifiers; do not dump it.

            context[:responseCallback].invoke(error, {
                :responseCode => responseCode,
                :body => body,
                :context => context[:context]
            });
        }

        function doAuthenticatedWebRequest(error, context) {
            if (context[:generation] != _sessionGeneration) { return; }
            if (error != null) {
                context[:responseCallback].invoke(error, {
                    :context => context[:context]
                });
                return;
            }

            var accessToken = _credentials.getAccessToken();

            var options = {
                :method => Comm.HTTP_REQUEST_METHOD_GET,
                :headers => {
                    "Content-Type" => Comm.REQUEST_CONTENT_TYPE_JSON,
                    "Authorization" => "Bearer " + accessToken
                },
                :context => {
                    :generation => _sessionGeneration,
                    :responseCallback => context[:responseCallback],
                    :context => context[:options][:context]
                }
            };

            if (_additionalHeaderKey != null && _additionalHeaderKey.length() > 0
                && !_additionalHeaderKey.toLower().equals("authorization")) {
                options[:headers][_additionalHeaderKey] = _additionalHeaderValue;
            }

            var passedOptions = context[:options];

            if (passedOptions[:method] != null) {
                options[:method] = passedOptions[:method];
            }

            if (options[:method] == Comm.HTTP_REQUEST_METHOD_GET) {
                System.println("GET: " + context[:url] + ", " + context[:parameters]);
            } else if (options[:method] == Comm.HTTP_REQUEST_METHOD_POST) {
                System.println("POST: " + context[:url] + ", " + context[:parameters]);
            } else {
                System.println("REQUEST: " + context[:url] + ", " + context[:parameters]);
            }

            Comm.makeWebRequest(
                context[:url],
                context[:parameters],
                options,
                method(:onWebResponse)
            );
        }

        function makeAuthenticatedWebRequest(url, parameters, options, responseCallback) {
            addTokenCallback(method(:doAuthenticatedWebRequest), {
                :generation => _sessionGeneration,
                :url => url,
                :parameters => parameters,
                :options => options,
                :responseCallback => responseCallback,
            });

            refreshToken(false);
        }
    }
}