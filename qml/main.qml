/*
 * qt-kiosk-browser
 * Copyright (C) 2018
 * O.S. Systems Sofware LTDA: contato@ossystems.com.br
 *
 * SPDX-License-Identifier:     GPL-3.0
 */

import QtQuick 2.15
import QtQuick.Window 2.15

import QtWebEngine 6.3

import Browser 1.0


Window {
    id: window
    visibility: "FullScreen"

    visible: true
    color: "black"

    WebEngineView {
        id: webViewException
        backgroundColor: "black"
        url: ""
        property int errorCode
        anchors.fill: parent
        visible: false
        onRenderProcessTerminated: { Qt.exit(1) }
        onLoadingChanged: function(loadingInfo) {
            switch (loadingInfo.status) {
            case WebEngineLoadingInfo.LoadSucceededStatus:
                webViewException.runJavaScript("document.getElementById('custom-error-content').innerHTML = document.getElementById('custom-error-content').innerHTML.replace('%CODE%'," + errorCode + ");");
                break
            case WebEngineView.LoadFailedStatus:
                console.log("exception page loading failure: ", loadingInfo.errorString)
                break
            }
        }
    }

    WebEngineView {
        id: webView
        backgroundColor: "black"
        url: "https://www.fancom.com"
        property bool errorLoading: false
        property int loadStage: 0          // 0 = HTTPS active, 1 = HTTP fallback active, 2 = error page
        property url primaryUrl: ""
        property bool fallbackToHttp: false
        signal showErrorPage(int requestErrorCode)
        anchors.fill: parent
        profile.httpCacheType: WebEngineProfile.NoCache
        visible: false
        property bool disableContextMenu: false

        function handleLoadFailure(errorCode) {
            if (webView.loadStage === 0 && webView.fallbackToHttp) {
                console.log("HTTPS failed (code " + errorCode + "), falling back to HTTP");
                webView.loadStage = 1;
                webView.visible = false;
                httpsStabilityTimer.stop();

                var httpUrl = webView.primaryUrl.toString().replace(/^https:/i, "http:");
                if (httpFallbackLoader.active && httpFallbackLoader.item) {
                    // Renderer still warm from a previous fallback - just re-navigate,
                    // no process spin-up cost.
                    httpFallbackLoader.item.url = httpUrl;
                    httpFallbackLoader.item.visible = true;
                } else {
                    httpFallbackLoader.active = true; // cold start - never created, or fully torn down
                }
            } else if (webView.loadStage !== 2) {
                webView.loadStage = 2;
                showErrorPage(errorCode);
            }
        }

        onRenderProcessTerminated: { Qt.exit(1) }
        onLoadingChanged: function(loadingInfo) {
            switch (loadingInfo.status) {
            case WebEngineView.LoadStartedStatus:
                errorLoading = false
                break
            case WebEngineLoadingInfo.LoadSucceededStatus:
                errorLoading = false
                if (webView.loadStage === 1) {
                    // Background recovery check succeeded - HTTPS is back.
                    console.log("HTTPS reachable again, switching display back from HTTP");
                    webView.loadStage = 0;
                    webView.visible = true;
                    splash.visible = false;
                    if (httpFallbackLoader.item) {
                        // Kill JS timers/websockets on the HTTP page immediately,
                        // but keep the renderer process warm in case HTTPS flaps.
                        httpFallbackLoader.item.url = "about:blank";
                        httpFallbackLoader.item.visible = false;
                    }
                    httpsStabilityTimer.restart(); // only free the renderer after this elapses
                } else {
                    webView.visible = true;
                    splash.visible = false;
                }
                break
            case WebEngineView.LoadStoppedStatus:
            case WebEngineLoadingInfo.LoadFailedStatus:
                if (webView.loadStage === 1) {
                    // Background HTTPS recheck failed - stay on HTTP fallback, try again later.
                    console.log("HTTPS recheck failed, staying on HTTP fallback");
                    httpsStabilityTimer.stop();
                } else {
                    handleLoadFailure(loadingInfo.errorCode);
                }
                break
            }
        }
        onContextMenuRequested: {
            request.accepted = disableContextMenu;
        }
        onTouchSelectionMenuRequested: function(request) {
                request.accepted =disableContextMenu;
        }
        onJavaScriptConsoleMessage: {
            if (level === WebEngineView.ErrorMessageLevel) {
                if (webView.loadStage === 0 && webViewException.url.toString() !== "" && message.indexOf("ChunkLoadError") >= 0) {
                    console.error("Show errorpage due to JS error")
                    handleLoadFailure(500);
                }
            }
        }

        onCertificateError: function(error) {
            error.acceptCertificate();
        }

        onShowErrorPage: function(requestErrorCode) {
            errorLoading = true
            webViewException.errorCode = requestErrorCode
            if (webViewException.url.toString().length > 0) {
                splash.visible = false;
                webView.visible = false
                httpFallbackLoader.active = false
                webViewException.visible = true
                reloader.restart()
            }
        }
    }

    Loader {
        id: httpFallbackLoader
        anchors.fill: parent
        active: false

        sourceComponent: WebEngineView {
            id: webViewHttp
            backgroundColor: "black"
            url: "" // set explicitly by webView.handleLoadFailure() on (re)activation
            profile.httpCacheType: WebEngineProfile.NoCache
            visible: true

            onRenderProcessTerminated: { Qt.exit(1) }

            onLoadingChanged: function(loadingInfo) {
                switch (loadingInfo.status) {
                case WebEngineLoadingInfo.LoadSucceededStatus:
                    if (webViewHttp.url.toString() !== "about:blank") {
                        webViewHttp.visible = true;
                        splash.visible = false;
                    }
                    break
                case WebEngineView.LoadStoppedStatus:
                case WebEngineLoadingInfo.LoadFailedStatus:
                    if (webViewHttp.url.toString() !== "about:blank") {
                        console.log("HTTP fallback failed: ", loadingInfo.errorString)
                        webView.loadStage = 2;
                        webView.showErrorPage(loadingInfo.errorCode);
                    }
                    break
                }
            }

            onContextMenuRequested: {
                request.accepted = webView.disableContextMenu;
            }
            onTouchSelectionMenuRequested: function(request) {
                request.accepted = webView.disableContextMenu;
            }
        }
    }

    // Periodically re-checks whether HTTPS has become reachable again while
    // the HTTP fallback is what's actually on screen.
    Timer {
        id: httpsRecoveryTimer
        interval: 30000
        repeat: true
        running: webView.loadStage === 1
        onTriggered: {
            console.log("Checking whether HTTPS is available again...");
            webView.reloadAndBypassCache();
        }
    }

    // Grace period after HTTPS recovers before the HTTP fallback renderer is
    // actually torn down. Lets a flappy connection fall back to HTTP again
    // instantly (reusing the warm renderer) instead of paying process
    // spin-up cost on every blip.
    Timer {
        id: httpsStabilityTimer
        interval: 300000 // 5 minutes
        repeat: false
        onTriggered: {
            if (webView.loadStage === 0) {
                console.log("HTTPS stable for grace period, releasing HTTP fallback renderer");
                httpFallbackLoader.active = false;
            }
        }
    }

    Timer {
        id: reloader
        interval: 0
        onTriggered: {
            if (webView.errorLoading) {
                webView.loadStage = 0;
                if (webView.url == webView.primaryUrl) {
                    webView.reloadAndBypassCache();
                } else {
                    webView.url = webView.primaryUrl;
                }
            }
        }

        function start() {
            this.running = this.interval > 0;
        }
    }

    Component.onCompleted: {
        var xhr = new XMLHttpRequest();
        let conf = "file:" + (Qt.application.arguments.slice(1).find(arg => !arg.startsWith("--")) || "settings.json");
        console.log("Loading configuration from '" + conf + "'");
        xhr.open("GET", conf);
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.responseText.trim().length != 0) {
                    try {
                        var settings = JSON.parse(xhr.responseText);

                        if (typeof settings["RestartTimeout"] != "undefined") {
                            restartTimer.interval = parseInt(settings["RestartTimeout"]);
                        }

                        if (typeof settings["URL"] != "undefined") {
                            webView.primaryUrl = settings["URL"];
                            webView.url = settings["URL"];
                        }

                        if (typeof settings["FallbackToHttp"] != "undefined") {
                            webView.fallbackToHttp = settings["FallbackToHttp"];
                        }

                        if (typeof settings["HttpsRecoveryInterval"] != "undefined") {
                            httpsRecoveryTimer.interval = parseInt(settings["HttpsRecoveryInterval"]);
                        }

                        if (typeof settings["HttpsStabilityInterval"] != "undefined") {
                            httpsStabilityTimer.interval = parseInt(settings["HttpsStabilityInterval"]);
                        }

                        for (var key in settings["WebEngineSettings"]) {
                            if (typeof webView.settings[key] == "undefined") {
                                console.error("Invalid settings property: " + key);
                                continue;
                            }

                            webView.settings[key] = settings["WebEngineSettings"][key];
                        }

                        if (typeof settings["SplashScreen"] != "undefined") {
                            splash.source = settings["SplashScreen"];
                        }

                        if (typeof settings["ErrorURL"] != "undefined") {
                            webViewException.url = settings["ErrorURL"];
                            webView.settings.errorPageEnabled = false
                            webViewException.settings.errorPageEnabled = false
                        }

                        if (typeof settings["RetryInterval"] != "undefined") {
                            reloader.interval = parseInt(settings["RetryInterval"]);
                        }

                        if (typeof settings["DisableContextMenu"] != "undefined") {
                            webView.disableContextMenu = settings["DisableContextMenu"];
                        }
                    } catch (e) {
                        console.error("Failed to parse settings file: " + e)
                    }
                }
            }
        }

        xhr.send();
    }

    Image {
        id: splash
        anchors.fill: parent
        visible: false

        onStatusChanged: {
            if (status === Image.Ready) {
                visible = true;
            }
        }
    }

    Image {
        id: fallbackIndicator
        source: "qrc:/icons/warning.svg"
        width: 32
        height: 32
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 32
        visible: webView.loadStage === 1
        z: 10
    }

    Timer {
        id: restartTimer
        interval: 60000 * 3 // 3 minutes

        onTriggered: Browser.restart()

        function start() {
            this.running = this.interval > 0;
        }
    }
}