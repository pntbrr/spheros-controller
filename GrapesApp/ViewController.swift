//
//  ViewController.swift
//  GrapesApp
//
//  Created by Maëva on 02/12/2021.
//

import UIKit

struct Axes:Codable {
    let x:Float,y:Float,z:Float
    func toString() -> String {
        return "\(x);\(y);\(z)"
    }
}

class ViewController: UIViewController {

    @IBOutlet weak var socketIOconnectionLabel: UILabel!
    @IBOutlet weak var spherosConnectionLabel: UILabel!
    @IBOutlet weak var makeWineLabel: UILabel!
    
    var global = GlobalManager.instance
    var socketIO = SocketIOManager.instance
        
    override func viewDidLoad() {
        super.viewDidLoad()
        
        global.delegate = self
        
        socketIOconnectionLabel.text = socketIO.isConnected ? "SocketIO connected" : "SocketIO disconnected"
    }
    
    @IBAction func socketIOconnectButton(_ sender: Any) {
        if socketIO.isConnected {
            print("Already connected bro'")
        } else {
            socketIO.connect()
        }
        socketIOconnectionLabel.text = socketIO.isConnected ? "SocketIO connected" : "SocketIO disconnected"
    }
    
    @IBAction func connectionSpheroButtonClicked(_ sender: Any) {
        global.connectSpheros()
    }
    
    @IBAction func growSenderClicked(_ sender: Any) {
        socketIO.emit(event: "leds")
    }
    
    @IBAction func makeWineClicked(_ sender: Any) {
        global.isListening = !global.isListening
        makeWineLabel.text = global.isListening ? "Make wine started" : "Make wine stopped"
    }
}

extension ViewController: GlobalManagerDelegate {
    func spherosConnected() {
        self.spherosConnectionLabel.text = "Spheros Connected"
    }
}
