//
//  MainTableViewController.swift
//  SwiftStarter
//
//  Created by Stephen Schiffli on 10/16/15.
//  Copyright © 2015 MbientLab Inc. All rights reserved.
//

import UIKit

class MainTableViewController: UITableViewController, ScanTableViewControllerDelegate {
    var devices: [MBLMetaWear]?
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated);
        
        MBLMetaWearManager.sharedManager().retrieveSavedMetaWearsWithHandler({ (array: [AnyObject]?) -> Void in
            if let deviceArray = array as? [MBLMetaWear] {
                if deviceArray.count > 0 {
                    self.devices = deviceArray
                } else {
                    self.devices = nil
                }
            } else {
                self.devices = nil
            }
            self.tableView.reloadData()
        })
    }
    
    // MARK: - Scan table view delegate
    
    func scanTableViewController(controller: ScanTableViewController, didSelectDevice device: MBLMetaWear) {
        device.rememberDevice()
        // TODO: You should assign a device configuration object here
        //device.setConfiguration(..., handler: ...)
        navigationController?.popViewControllerAnimated(true)
    }

    // MARK: - Table view data source

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if let count = devices?.count {
            return count
        }
        return 1
    }

    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        var cell : UITableViewCell!
        if devices == nil {
            cell = tableView.dequeueReusableCellWithIdentifier("NoDeviceCell", forIndexPath: indexPath)
        } else {
            cell = tableView.dequeueReusableCellWithIdentifier("MetaWearCell", forIndexPath: indexPath)
            if let cur = devices?[indexPath.row] {
                let name = cell.viewWithTag(1) as! UILabel
                name.text = cur.name
                
                let uuid = cell.viewWithTag(2) as! UILabel
                uuid.text = cur.identifier.UUIDString
            }
        }
        return cell
    }
    

    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        tableView.deselectRowAtIndexPath(indexPath, animated: true)
        if let cur = devices?[indexPath.row] {
            performSegueWithIdentifier("ViewDevice", sender: cur)
        } else {
            performSegueWithIdentifier("AddNewDevice", sender: nil)
        }
    }

    override func tableView(tableView: UITableView, canEditRowAtIndexPath indexPath: NSIndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return devices != nil
    }
    
    override func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
        if editingStyle == .Delete {
            if let cur = devices?[indexPath.row] {
                cur.forgetDevice()
                // TODO: You should connect and set a nil configuration at this point
                devices?.removeAtIndex(indexPath.row)
                
                if devices?.count != 0 {
                    tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: .Automatic)
                } else {
                    devices = nil
                    tableView.reloadRowsAtIndexPaths([indexPath], withRowAnimation: .Automatic)
                }
            }
        }
    }

    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        // Get the new view controller using segue.destinationViewController.
        if let scanController = segue.destinationViewController as? ScanTableViewController {
            scanController.delegate = self
        } else if let deviceController = segue.destinationViewController as? DeviceViewController {
            deviceController.device = sender as! MBLMetaWear
        }
    }
}
