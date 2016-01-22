//
//  DeviceViewController.swift
//  SwiftStarter
//
//  Created by Brian House on 1/5/16.
//  Copyright © 2016 Brian House. All rights reserved.
//

import UIKit
import Starscream
import Foundation

class DeviceViewController: UITableViewController, WebSocketDelegate {
    
    @IBOutlet weak var connectionState: UILabel!
    @IBOutlet weak var deviceName: UILabel!
    @IBOutlet weak var deviceID: UILabel!
    @IBOutlet weak var mfgNameLabel: UILabel!
    @IBOutlet weak var serialNumLabel: UILabel!
    @IBOutlet weak var hwRevLabel: UILabel!
    @IBOutlet weak var fwRevLabel: UILabel!
    @IBOutlet weak var modelNumberLabel: UILabel!
    @IBOutlet weak var batteryLevelLabel: UILabel!
    @IBOutlet weak var rssiLevelLabel: UILabel!
    @IBOutlet weak var switchLabel: UILabel!
    
    var device: MBLMetaWear!
    var socket: WebSocket!
    var socket_id: String? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.socket = WebSocket(url: NSURL(string: "ws://granu.local:5280/websocket")!)
        self.socket.delegate = self
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated);
        self.device.addObserver(self, forKeyPath: "state", options: NSKeyValueObservingOptions.New, context: nil)
        self.device.connectWithHandler { (error: NSError?) -> Void in
            self.deviceConnected();
        }
    }

    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)
        device.removeObserver(self, forKeyPath: "state")
        device.disconnectWithHandler(nil)
    }
    
    
    override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
        if keyPath != nil {
            // NSLog("KeyPath: " + keyPath!);
        }
        self.deviceName.text = device.name;
        switch (device.state) {
            case .Connected:
                self.connectionState.text = "Connected";
            case .Connecting:
                self.connectionState.text = "Connecting";
            case .Disconnected:
                self.connectionState.text = "Disconnected";
            case .Disconnecting:
                self.connectionState.text = "Disconnecting";
            case .Discovery:
                self.connectionState.text = "Discovery";
        }
        // do something if disconnected?
    }
    
    func deviceConnected() {
        NSLog("deviceConnected");
        self.connectionState.text = "Connected";
        self.deviceID.text = self.device.identifier.UUIDString;
        if let deviceInfo = self.device.deviceInfo {
            self.mfgNameLabel.text = deviceInfo.manufacturerName;
            self.serialNumLabel.text = deviceInfo.serialNumber;
            self.hwRevLabel.text = deviceInfo.hardwareRevision;
            self.fwRevLabel.text = deviceInfo.firmwareRevision;
            self.modelNumberLabel.text = deviceInfo.modelNumber;
        }
        
        // detect button (presumably never pressed on startup...)
        self.device.mechanicalSwitch?.switchValue.readAsync().success({ (obj:AnyObject?) in
            if let result = obj as? MBLNumericData {
                if result.value.boolValue {
                    self.switchLabel.text = "ON";
                } else {
                    self.switchLabel.text = "OFF";
                }
            }
        });
        
        // periodically read battery
        //// TODO: does that drain the battery? disable when pushing to the background?
        self.readBatteryPressed();
        self.readRSSIPressed();
        NSTimer.scheduledTimerWithTimeInterval(60.0, target: self, selector: Selector("readBatteryPressed:"), userInfo: nil, repeats: true) // note the colon
        NSTimer.scheduledTimerWithTimeInterval(5.0, target: self, selector: Selector("readRSSIPressed:"), userInfo: nil, repeats: true) // note the colon
        
        
        // set up handlers
        self.device.mechanicalSwitch?.switchUpdateEvent.startNotificationsWithHandlerAsync(mechanicalSwitchUpdate);
        
        // connect to server
        NSLog("Connecting to socket...")
        self.socket.connect()
        
    }
    
    @IBAction func readBatteryPressed(sender: AnyObject?=nil) {
        NSLog("readBatteryPressed");
        self.device.readBatteryLifeWithHandler({ (number: NSNumber?, error: NSError?) in
            if let n = number {
                self.batteryLevelLabel.text = n.stringValue + "%";
            }
        });
    }
    
    // change these to notifications, yeah?
    @IBAction func readRSSIPressed(sender: AnyObject?=nil) {
        NSLog("readRSSIPressed");
        self.device.readRSSIWithHandler({ (number: NSNumber?, error: NSError?) in
            if let n = number {
                self.rssiLevelLabel.text = n.stringValue + "";
            }
        });
    }

    @IBAction func flashBlueLEDPressed(sender: AnyObject?=nil) {
        NSLog("flashBlueLEDPressed");
        self.device.led?.flashLEDColorAsync(UIColor.blueColor(), withIntensity: 1.0, numberOfFlashes: 5);
    }

    func sendPulse(dutyCycle: Float, duration: UInt16) {
        NSLog("pulse");
        self.device.hapticBuzzer!.startHapticWithDutyCycleAsync(UInt8(dutyCycle * 255), pulseWidth: duration, completion: nil);
    }

    func mechanicalSwitchUpdate(obj: AnyObject?, error: NSError?) {
        NSLog("mechnicalSwitchUpdate");
        if let result = obj as? MBLNumericData {
            NSLog("Switch: " + result.value.stringValue);
            if result.value.boolValue {
                self.switchLabel.text = "ON";
                self.device.led?.setLEDColorAsync(UIColor.blueColor(), withIntensity: 1.0);
            } else {
                self.switchLabel.text = "OFF";
                self.device.led?.setLEDOnAsync(false, withOptions: 1);
            }
        }
    }
    
    func websocketDidConnect(socket: WebSocket) {
        NSLog("websocketDidConnect")
    }
    
    func websocketDidDisconnect(socket: WebSocket, error: NSError?) {
        NSLog("websocketDidDisconnect: \(error?.localizedDescription)")
        // TODO: should attempt to reconnect
    }
    
    func websocketDidReceiveMessage(socket: WebSocket, text: String) {
        NSLog("websocketDidReceiveMessage: \(text)")
        
        var data: [String: AnyObject]? = nil;
        do {
            data = try NSJSONSerialization.JSONObjectWithData(text.dataUsingEncoding(NSUTF8StringEncoding)!, options: .MutableLeaves) as? [String: AnyObject] // how do I do no options? nil fails
        } catch {
            NSLog("--> error serializing JSON: \(error)")
        }
        
        
        
        if data != nil {
            for (key, value) in data! {
                NSLog("\(key): \(value)");
                
                // handshake sequence
                if key == "socket_id" {
                    self.socket_id = value as? String;
                    // send the deviceID back
                    self.socket.writeString("{\"device_id\": \"\(self.device.deviceInfo!.serialNumber)\"}");
                }
                if key == "linked" {
                    if value as! Bool == true {
                        NSLog("--> link established")
                        self.sendPulse(0.5, duration: 500);
                    } else {
                        NSLog("--> link failed")
                    }
                }
                
                // handle pulses
                if key == "pulses" {
                    
                }
                
//                self.delay(2.0) {
//                    self.sendPulse(0.8, duration: 500);
//                }
                
                
            }
        }
    }
    
    func websocketDidReceiveData(socket: WebSocket, data: NSData) {
        NSLog("websocketDidReceiveData: \(data.length)")
    }
    
    func delay(delay:Double, closure:()->()) {
        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                Int64(delay * Double(NSEC_PER_SEC))
            ),
            dispatch_get_main_queue(), closure)
    }
    
    // TODO: what happens when we get disconnected? need to kill the counters, etc
    
}
