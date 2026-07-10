/*
 * qt-kiosk-browser
 * Copyright (C) 2018
 * O.S. Systems Sofware LTDA: contato@ossystems.com.br
 *
 * SPDX-License-Identifier:     GPL-3.0
 */


#include <QtQml/qqml.h>
#include <QtWebEngineQuick/qtwebenginequickglobal.h>
#include <QtQml/QQmlApplicationEngine>
#include <QtQml/QQmlContext>
#include <QtGui/QGuiApplication>
#include <QNetworkProxyFactory>

#include "proxyhandler.hpp"
#include "inputeventhandler.hpp"
#include "browser.hpp"

int main(int argc, char *argv[])
{
    QCoreApplication::setApplicationName("QT kiosk browser");

    qputenv("QT_IM_MODULE", QByteArray("qtvirtualkeyboard"));
    qputenv("QML_XHR_ALLOW_FILE_READ", QByteArray("1"));
    qputenv("QTWEBENGINE_CHROMIUM_FLAGS", "--disable-pinch --enable-smooth-scrolling");
    
    QtWebEngineQuick::initialize();

    QGuiApplication app(argc, argv);
    app.setApplicationName("Chrome");
    app.setApplicationVersion("118.0.5993.220");

    ProxyHandler proxyHandler;
    proxyHandler.useSystemProxy();
    proxyHandler.printCurrentProxySettings();

    qmlRegisterSingletonType<InputEventHandler>("Browser", 1, 0, "Browser", [](QQmlEngine *, QJSEngine *) -> QObject * {
        return new Browser();
    });
    qmlRegisterType<InputEventHandler>("Browser", 1, 0, "InputEventHandler");

    QQmlApplicationEngine engine;
    engine.load(QUrl(QStringLiteral("qrc:/qml/main.qml")));

    return app.exec();
}
