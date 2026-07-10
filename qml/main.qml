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
        signal showErrorPage(int requestErrorCode)
        anchors.fill: parent
        profile.httpCacheType: WebEngineProfile.NoCache
        visible: false
        property bool disableContextMenu: false
    
        onRenderProcessTerminated: { Qt.exit(1) }
        onLoadingChanged: function(loadingInfo) {
            switch (loadingInfo.status) {
            case WebEngineView.LoadStartedStatus:
                errorLoading = false
                break
            case WebEngineLoadingInfo.LoadSucceededStatus:
                errorLoading = false
                webView.visible = true
                splash.visible = false;
                break
            case WebEngineView.LoadStoppedStatus:
            case WebEngineLoadingInfo.LoadFailedStatus:
                showErrorPage(loadingInfo.errorCode);
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
                // https://rollbar.com/blog/javascript-chunk-load-error/#
                // target chunkloaderror
                if (webViewException.url.toString() !== "" && message.indexOf("ChunkLoadError") >= 0) {
                    console.error("Show errorpage due to JS error")
                    showErrorPage(500);
                }
            }
        }

        onShowErrorPage: function(requestErrorCode) {
            errorLoading = true
            webViewException.errorCode = requestErrorCode
            if (webViewException.url.toString().length > 0) {
                splash.visible = false;
                webView.visible = false
                webViewException.visible = true
                reloader.restart()
            }
        }
    }

    Timer {
        id: reloader
        interval: 0
        onTriggered: {
            if (webView.errorLoading) {
                webView.reloadAndBypassCache()
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
                            webView.url = settings["URL"];
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

    Timer {
        id: restartTimer
        interval: 60000 * 3 // 3 minutes

        onTriggered: Browser.restart()

        function start() {
            this.running = this.interval > 0;
        }
    }
}
