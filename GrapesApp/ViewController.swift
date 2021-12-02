//
//  ViewController.swift
//  GrapesApp
//
//  Created by Maëva on 02/12/2021.
//

import UIKit

class ViewController: UIViewController {

    @IBOutlet weak var socketIOconnectionLabel: UILabel!
    @IBOutlet weak var spherosConnectionLabel: UILabel!
    @IBOutlet weak var makeWineLabel: UILabel!
    
    var socketIO = SocketIOManager.instance
    
    var isRecording = false
    var lastTime:Double = 0.00
    var winemakerIsDoing = false
    
    override func viewDidLoad() {
        super.viewDidLoad()

        socketIO.connect()
        socketIOconnectionLabel.text = socketIO.isConnected ? "SocketIO connected" : "SocketIO disconnected"

        socketIO.socket.on("grow", callback: { data, ack in
            self.grapesChanging(color: .green, duration: nil)
        })
        socketIO.socket.on("solar", callback: { data, ack in
            let duration = data.count > 0 ? data[0] as? Double : nil
            self.grapesChanging(color: .purple, duration: duration)
        })
    }
    
    @IBAction func socketIOconnectButton(_ sender: Any) {
        if socketIO.isConnected {
            print("Already connected bro'")
        } else {
            socketIO.connect()
        }
    }
    
    @IBAction func connectionSpheroButtonClicked(_ sender: Any) {
        // SB-313C - SB-A729
        SharedToyBox.instance.searchForBoltsNamed(["SB-A729", "SB-313C"]) { err in
            if err == nil {
                self.spherosConnectionLabel.text = "Spheros Connected"
                
                if let bolt = SharedToyBox.instance.bolt {
                    bolt.sensorControl.enable(sensors: SensorMask.init(arrayLiteral: .accelerometer,.gyro))
                    bolt.sensorControl.interval = 1
                    bolt.setStabilization(state: SetStabilization.State.off)
                    bolt.sensorControl.onDataReady = { data in
                        DispatchQueue.main.async {
                            self.onData(data: data)
                        }
                    }
                }
            }
        }
        
        
    }
    
    @IBAction func growSenderClicked(_ sender: Any) {
        socketIO.emit(event: "leds")
    }
    
    @IBAction func makeWineClicked(_ sender: Any) {
        self.isRecording = !self.isRecording
        makeWineLabel.text = self.isRecording ? "Make wine started" : "Make wine stopped"
    }
    
    func grapesChanging(color: UIColor, duration: Double?) {
        var timing:Double = 60/64
        print(["timing", timing])
        if let duration = duration {
            timing = duration/64 // = droneDuration/64
        }
        var count = 0
        
        for y in 0...7 {
            for x in 0...7 {
                let sum = timing * Double(count)
                print([timing, count, sum])
                DispatchQueue.main.asyncAfter(deadline: .now() + timing * Double(count)) {
                    SharedToyBox.instance.bolts.forEach{ bolt in
                        bolt.drawMatrix(pixel: Pixel(x: x, y: y), color: color)
                    }
                }
                count+=1
            }
        }
    }
        
    func onData(data: SensorControlData) {
        if self.isRecording {
            print("recording")
            if let acceleration = data.accelerometer?.filteredAcceleration {

                if let z = acceleration.z,
                   let y = acceleration.y,
                   let x = acceleration.x {
                    
                    let absSum = abs(x)+abs(y)+abs(z)
                    
                    if (absSum >= 2) {
                        if(!winemakerIsDoing) {
                            winemakerIsDoing = true
                            self.socketIO.emit(event: "winemaker", data: 1)
                            print("changed, 1")
                        }
                        lastTime = NSDate.timeIntervalSinceReferenceDate
                    }
                    
                    if(NSDate.timeIntervalSinceReferenceDate - lastTime > 0.5) {
                        if(winemakerIsDoing) {
                            winemakerIsDoing = false
                            self.socketIO.emit(event: "winemaker", data: 0)
                            print("changed, 0")
                        }
                    }
                }
            }
        }
    }
}

