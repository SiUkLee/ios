//
//  TinodiosUITests.swift
//  TinodiosUITests
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import XCTest

import Network
@testable import TinodeSDK

class FakeTinodeServer {
    var listener: NWListener
    var connectedClients: [NWConnection] = []

    // Request types.
    enum RequestType {
        case none, hi, acc, login, sub, get, set, pub, leave, note, del
    }
    // Request handlers.
    var requestHandlers: [RequestType : ((ClientMessage<Int, Int>) -> [ServerMessage])] = [:]

    init(port: UInt16) {
        let parameters = NWParameters(tls: nil)
        parameters.allowLocalEndpointReuse = true
        parameters.includePeerToPeer = true

        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true

        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        do {
            if let port = NWEndpoint.Port(rawValue: port) {
                listener = try NWListener(using: parameters, on: port)
            } else {
                fatalError("Unable to start WebSocket server on port \(port)")
            }
        } catch {
            fatalError(error.localizedDescription)
        }
    }

    func startServer() {
        let serverQueue = DispatchQueue(label: "ServerQueue")

        listener.newConnectionHandler = { newConnection in
            print("New connection connecting")

            func receive() {
                newConnection.receiveMessage { (data, context, isComplete, error) in
                    if let data = data, let context = context {
                        print("Received a new message from client")
                        try! self.handleClientMessage(data: data, context: context, stringVal: "", connection: newConnection)
                        receive()
                    }
                }
            }
            receive()

            newConnection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("Client ready")
                case .failed(let error):
                    print("Client connection failed \(error.localizedDescription)")
                case .waiting(let error):
                    print("Waiting for long time \(error.localizedDescription)")
                default:
                    break
                }
            }

            newConnection.start(queue: serverQueue)
        }

        listener.stateUpdateHandler = { state in
            print(state)
            switch state {
            case .ready:
                print("Server Ready")
            case .failed(let error):
                print("Server failed with \(error.localizedDescription)")
            default:
                break
            }
        }

        listener.start(queue: serverQueue)
    }

    func stopServer() {
        listener.cancel()
    }

    func handleClientMessage(data: Data, context: NWConnection.ContentContext, stringVal: String, connection: NWConnection) throws {
        let message = try Tinode.jsonDecoder.decode(ClientMessage<Int, Int>.self, from: data)

        print("--> received: \(String(decoding: data, as: UTF8.self))")
        var reqType: RequestType = .none
        if message.hi != nil {
            reqType = .hi
        } else if message.login != nil {
            reqType = .login
        } else if message.sub != nil {
            reqType = .sub
        }
        self.requestHandlers[reqType]?(message).forEach { self.sendResponse(response: $0, into: connection) }
    }

    func sendResponse(response: ServerMessage, into connection: NWConnection) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "textContext",
                                                  metadata: [metadata])
        do {
            let data = try Tinode.jsonEncoder.encode(response)
            print("sending --> \(String(decoding: data, as: UTF8.self))")
            connection.send(content: data, contentContext: context, isComplete: true,
                            completion: .contentProcessed({ error in
                                if let error = error {
                                    print(error.localizedDescription)
                                }
                            }))
        } catch {
            print("Error sending response: \(error)")
        }
    }
}

final class TinodiosUITests: XCTestCase {
    var tinodeServer: FakeTinodeServer!

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
        tinodeServer = FakeTinodeServer(port: 6060)
        tinodeServer.startServer()
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        tinodeServer.requestHandlers.removeAll()
        tinodeServer.stopServer()
    }

    func testExample() throws {
        tinodeServer.requestHandlers[.hi] = { req in
            let hi = req.hi!
            let response = ServerMessage()
            response.ctrl = MsgServerCtrl(id: hi.id, topic: nil, code: 200, text: "", ts: Date(), params: nil)
            return [response]
        }
        tinodeServer.requestHandlers[.login] = { req in
            let login = req.login!
            let response = ServerMessage()
            response.ctrl = MsgServerCtrl(id: login.id, topic: nil, code: 200, text: "ok", ts: Date(),
                                          params: ["authlvl": .string("auth"), "token": .string("fake"),
                                                   "user": .string("usrFake")])
            return [response]
        }
        tinodeServer.requestHandlers[.sub] = { req in
            let sub = req.sub!
            if sub.topic == "me", let get = sub.get, get.what.split(separator: " ").sorted().elementsEqual(["cred", "desc", "sub", "tags"]) {
                let responseCtrl = ServerMessage()
                responseCtrl.ctrl = MsgServerCtrl(id: sub.id, topic: sub.topic, code: 200, text: "ok", ts: Date(), params: nil)
                return [responseCtrl]
            }
            return []
        }

        // Allow notifications.
        let monitor = addUIInterruptionMonitor(withDescription: "Local Notifications") { (alert) -> Bool in
            let notifPermission = "Would Like to Send You Notifications"
            if alert.label.contains(notifPermission) {
                alert.buttons["Allow"].tap()
                return true
            }
            return false
        }
        defer { removeUIInterruptionMonitor(monitor) }

        let app = XCUIApplication()
        app.launch()

        let elementsQuery = XCUIApplication().scrollViews.otherElements
        let loginText = elementsQuery.textFields["usernameText"]
        XCTAssertTrue(loginText.exists)
        loginText.tap()
        loginText.typeText("alice")

        let passwordText = elementsQuery.secureTextFields["passwordText"]
        XCTAssertTrue(passwordText.exists)
        passwordText.tap()
        passwordText.typeText("alice123")

        let signInButton = elementsQuery.staticTexts["Sign In"]
        XCTAssertTrue(signInButton.exists)
        signInButton.tap()

        // "Allow Notifications?" dialog. Make sure modal dialog handler gets triggered.
        app.tap()
        print("sleepin 15 sec")
        sleep(15)
        print("done")
    }

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}