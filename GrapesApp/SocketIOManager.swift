//
//  ViewController.swift
//  PointBarre
//
//  Created by Maëva Mezzasalma on 02/12/2021.
//  Copyright © 2021 Maëva Mezzasalma. All rights reserved.
//

import Foundation
import SocketIO

class SocketIOManager {
    let socketioManager = SocketManager(socketURL: URL(string: "http://192.168.3.1:3000")!, config: SocketIOClientConfiguration(arrayLiteral: .log(false), .compress))
    var socket: SocketIOClient
    var isConnected = false
    
    static let instance = SocketIOManager()
    
    init() {
        socket = socketioManager.defaultSocket
        
        socket.on(clientEvent: .connect) {data, ack in
            print("socket connected yay")
            self.socket.emit("hello", with: [["device": "iPhone"]])
            self.isConnected = true
        }
        socket.on(clientEvent: .disconnect) { data, ack in
            print("socket disconnected arrrrrgh")
            self.isConnected = false
        }
    }
    
    func connect() {
        socket.connect()
    }
    
    func disconnect() {
        socket.disconnect()
    }
    
    func emit(event: String) {
        if !isConnected { return }
        socket.emit(event)
    }
    
    func emit(event: String, data: Any) {
        if !isConnected { return }
        socket.emit(event, with: [data])
    }
}

