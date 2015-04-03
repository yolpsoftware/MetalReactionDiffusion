//
//  AppDelegate.swift
//  MetalReactionDiffusion
//
//  Created by Simon Gladman on 18/10/2014.
//  Copyright (c) 2014 Simon Gladman. All rights reserved.
//


import UIKit
import CoreData

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?

    func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool
    {
        return true
    }
    
    func applicationWillResignActive(application: UIApplication)
    {
        if let viewController = window?.rootViewController as? ViewController
        {
            viewController.isRunning = false
        }
    }
    
    func applicationDidEnterBackground(application: UIApplication)
    {
    }
    
    func applicationWillEnterForeground(application: UIApplication)
    {
    }
    
    func applicationDidBecomeActive(application: UIApplication)
    {
        if let viewController = window?.rootViewController as? ViewController
        {
            viewController.isRunning = true
        }
    }
    
    func applicationWillTerminate(application: UIApplication)
    {
    }
}

