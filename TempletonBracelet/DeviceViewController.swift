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
    @IBOutlet weak var serverState: UILabel!
    @IBOutlet weak var serialNumLabel: UILabel!
    @IBOutlet weak var fwRevLabel: UILabel!
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
             NSLog("KeyPath: " + keyPath!);
        }
        switch (device.state) {
            case .Connected:
                NSLog("State: connected");
                self.connectionState.text = "Connected";
            case .Connecting:
                NSLog("State: connecting");
                self.connectionState.text = "Connecting";
            case .Disconnected:
                NSLog("State: disconnected");
                self.connectionState.text = "Disconnected";
            case .Disconnecting:
                NSLog("State: disconnecting");
                self.connectionState.text = "Disconnecting";
            case .Discovery:
                NSLog("State: discovery");
                self.connectionState.text = "Discovery";
        }
        // do something if disconnected?
    }
    
    func deviceConnected() {
        NSLog("deviceConnected");
        self.connectionState.text = "Connected";
        if let deviceInfo = self.device.deviceInfo {
            self.serialNumLabel.text = deviceInfo.serialNumber;
            self.fwRevLabel.text = deviceInfo.firmwareRevision;
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

    func sendPulse(intensity: Float, duration: UInt16) {
        NSLog("sendPulse \(intensity) \(duration)");
        if intensity > 0.0 {
            self.device.hapticBuzzer!.startHapticWithDutyCycleAsync(UInt8(intensity * 255), pulseWidth: duration, completion: nil);
        }
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
        self.serverState.text = "Contacted";
    }
    
    func websocketDidDisconnect(socket: WebSocket, error: NSError?) {
        NSLog("websocketDidDisconnect: \(error?.localizedDescription)")
        self.serverState.text = "Disconnected";
        self.delay(5.0) {
            self.socket.connect();
            self.serverState.text = "Connecting";
        }
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
                    if value as? Bool == true {
                        NSLog("--> link established")
                        self.serverState.text = "Connected";
                        self.sendPulse(0.5, duration: 500);
                    } else {
                        NSLog("--> link failed")
                        self.serverState.text = "Failed";
                    }
                }
                
                // handle pulses
                if key == "pulses" {
                    if let pulses = value as? [AnyObject] {
                        var d: Int = 0;
                        for pulse in pulses {
                            // NSLog("\(pulse)")
                            if let params = pulse as? [AnyObject] {
                                if let intensity = params[0] as? Float {
                                    if let duration = params[1] as? Int {
                                        NSLog("delay: \(d)");
                                        self.delay(Double(d) / 1000) {
                                            self.sendPulse(intensity, duration: UInt16(duration))
                                        }
                                        d += duration;
                                    } else {
                                        NSLog("--> bad duration \(params[1])")
                                    }
                                } else {
                                    NSLog("--> bad intensity \(params[0])");
                                }
                            }
                        }
                    }
                }
                
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
