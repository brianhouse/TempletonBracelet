//
//  ScanTableViewController.swift
//
//  Created by Stephen Schiffli on 8/14/15.
//  Copyright (c) 2015 MbientLab Inc. All rights reserved.
//

import UIKit
import MBProgressHUD

protocol ScanTableViewControllerDelegate {
    func scanTableViewController(controller: ScanTableViewController, didSelectDevice device: MBLMetaWear)
}

class ScanTableViewController: UITableViewController {
    var delegate: ScanTableViewControllerDelegate?
    var devices: [MBLMetaWear]?
    var selected: MBLMetaWear?
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated);
        
        MBLMetaWearManager.sharedManager().startScanForMetaWearsAllowDuplicates(true, handler: { (array: [AnyObject]?) -> Void in
            self.devices = array as? [MBLMetaWear]
            self.tableView.reloadData()
        })
    }
    
    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)
        
        MBLMetaWearManager.sharedManager().stopScanForMetaWears()
    }

    // MARK: - Table view data source

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if let count = devices?.count {
            return count
        }
        return 0
    }

    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier("MetaWearCell", forIndexPath: indexPath) 

        // Configure the cell...
        if let cur = devices?[indexPath.row] {
            let name = cell.viewWithTag(1) as! UILabel
            name.text = cur.name
            
            let uuid = cell.viewWithTag(2) as! UILabel
            uuid.text = cur.identifier.UUIDString
            
            if let rssiNumber = cur.discoveryTimeRSSI {
                let rssi = cell.viewWithTag(3) as! UILabel
                rssi.text = rssiNumber.stringValue
            }
        }
        
        return cell
    }

    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        tableView.deselectRowAtIndexPath(indexPath, animated: true)
        if let selected = devices?[indexPath.row] {
            let hud = MBProgressHUD.showHUDAddedTo(UIApplication.sharedApplication().keyWindow, animated: true)
            hud.labelText = "Connecting..."
            
            self.selected = selected
            selected.connectWithTimeout(15, handler: { (error: NSError?) -> Void in
                if let realError = error {
                    hud.labelText = realError.localizedDescription
                    hud.hide(true, afterDelay: 2.0)
                } else {
                    hud.hide(true)
                    selected.led?.flashLEDColorAsync(UIColor.greenColor(), withIntensity: 1.0)
                    
                    let alert = UIAlertController(title: "Confirm Device", message: "Do you see a blinking green LED on the MetaWear", preferredStyle: UIAlertControllerStyle.Alert)
                    alert.addAction(UIAlertAction(title: "No", style: .Cancel, handler: { (action: UIAlertAction) -> Void in
                        selected.led?.setLEDOnAsync(false, withOptions: 1)
                        selected.disconnectWithHandler(nil)
                    }))
                    alert.addAction(UIAlertAction(title: "Yes!", style: .Default, handler: { (action: UIAlertAction) -> Void in
                        selected.led?.setLEDOnAsync(false, withOptions: 1)
                        selected.disconnectWithHandler(nil)
                        if let delegate = self.delegate {
                            delegate.scanTableViewController(self, didSelectDevice: selected)
                        }
                    }))
                    self.presentViewController(alert, animated: true, completion: nil)
                }
            })
        }
    }
}
