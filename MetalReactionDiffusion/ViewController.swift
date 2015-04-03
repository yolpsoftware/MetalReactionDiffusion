//
//  ViewController.swift
//  MetalReactionDiffusion
//
//  Created by Simon Gladman on 18/10/2014.
//  Copyright (c) 2014 Simon Gladman. All rights reserved.
//
//  Thanks to http://www.raywenderlich.com/77488/ios-8-metal-tutorial-swift-getting-started
//  Thanks to https://twitter.com/steipete/status/473952933684330497
//  Thanks to http://metalbyexample.com/textures-and-samplers/
//  Thanks to http://metalbyexample.com/introduction-to-compute/
//
//  Thanks to http://jamesonquave.com/blog/core-data-in-swift-tutorial-part-1/

import UIKit
import Metal
import QuartzCore
import CoreData

class ViewController: UIViewController, UIPopoverControllerDelegate
{
    let bitmapInfo = CGBitmapInfo(CGBitmapInfo.ByteOrder32Big.rawValue | CGImageAlphaInfo.PremultipliedLast.rawValue)
    let renderingIntent = kCGRenderingIntentDefault
    
    let imageSide: UInt = 640
    let imageSize = CGSize(width: Int(640), height: Int(640))
    let imageByteCount = Int(640 * 640 * 4) 
    
    let bytesPerPixel = UInt(4)
    let bitsPerComponent = UInt(8)
    let bitsPerPixel:UInt = 32
    let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
     
    let bytesPerRow = UInt(4 * 640)
    let providerLength = Int(640 * 640 * 4) * sizeof(UInt8)
    var imageBytes = [UInt8](count: Int(640 * 640 * 4), repeatedValue: 0)
    
    var pipelineState: MTLComputePipelineState!
    var defaultLibrary: MTLLibrary! = nil
    var device: MTLDevice! = nil
    var commandQueue: MTLCommandQueue! = nil

    let imageView =  UIImageView(frame: CGRectZero)
    let editor = ReactionDiffusionEditor(frame: CGRectZero)
    
    var region: MTLRegion!
    var textureA: MTLTexture!
    var textureB: MTLTexture!
    var useTextureAForInput = true
    var resetSimulationFlag = false
    var newModelLoadedFlag = false

    var image:UIImage!
    var runTime = CFAbsoluteTimeGetCurrent()
    var errorFlag:Bool = false
    
    var threadGroupCount:MTLSize!
    var threadGroups: MTLSize!

    var reactionDiffusionModel: ReactionDiffusion = GrayScott()
    {
        didSet
        {
            if oldValue.model != reactionDiffusionModel.model
            {
                newModelLoadedFlag = true
            }
        }
    }
    
    var requestedReactionDiffusionModel: ReactionDiffusionModels?

    let appDelegate: AppDelegate
    let managedObjectContext: NSManagedObjectContext
    
    let browseAndLoadController: BrowseAndLoadController
    //let popoverController: UIPopoverController
    
    required init(coder aDecoder: NSCoder)
    {
        appDelegate = UIApplication.sharedApplication().delegate as AppDelegate
        managedObjectContext = appDelegate.managedObjectContext!
        
        browseAndLoadController = BrowseAndLoadController()
        //popoverController = UIPopoverController(contentViewController: browseAndLoadController)
        
        super.init(coder: aDecoder)

        browseAndLoadController.preferredContentSize = CGSize(width: 640, height: 480)

        //popoverController.delegate = self
    }

    
    override func viewDidLoad()
    {
        super.viewDidLoad()

        view.backgroundColor = UIColor.blackColor()
        
        imageView.contentMode = UIViewContentMode.ScaleAspectFit
        
        view.addSubview(imageView)
        view.addSubview(editor)

        editor.alpha = 0
        imageView.alpha = 0

        UIView.animateWithDuration(0.5, delay: 0.25, options: UIViewAnimationOptions.CurveEaseInOut, animations: {self.imageView.alpha = 1.0; self.editor.alpha = 1.0}, completion: nil)
        
        editor.reactionDiffusionModel = reactionDiffusionModel
        editor.addTarget(self, action: "editorChangeHandler:", forControlEvents: UIControlEvents.ValueChanged)
        editor.addTarget(self, action: "resetSimulationHandler", forControlEvents: UIControlEvents.ResetSimulation)
        editor.addTarget(self, action: "modelChangedHandler:", forControlEvents: UIControlEvents.ModelChanged)
        editor.addTarget(self, action: "saveModel", forControlEvents: UIControlEvents.SaveModel)
        editor.addTarget(self, action: "loadModel", forControlEvents: UIControlEvents.LoadModel)
        
        setUpMetal()
    }

    final func modelChangedHandler(value: ReactionDiffusionEditor)
    {
        if value.requestedReactionDiffusionModel != nil
        {
            requestedReactionDiffusionModel = value.requestedReactionDiffusionModel!
        }
    }
    
    final func editorChangeHandler(value: ReactionDiffusionEditor)
    {
        reactionDiffusionModel.reactionDiffusionStruct = value.reactionDiffusionModel.reactionDiffusionStruct
    }
    
    func resetSimulationHandler()
    {
        resetSimulationFlag = true
    }
    
    func saveModel()
    {
        var newEntity = ReactionDiffusionEntity.createInManagedObjectContext(managedObjectContext, model: reactionDiffusionModel.model.rawValue, reactionDiffusionStruct: reactionDiffusionModel.reactionDiffusionStruct, image: self.imageView.image!)
        
       appDelegate.saveContext()
    }
    
    func loadModel()
    {
        let fetchRequest = NSFetchRequest(entityName: "ReactionDiffusionEntity")
        
        if let fetchResults = managedObjectContext.executeFetchRequest(fetchRequest, error: nil) as? [ReactionDiffusionEntity]
        {
            // retrieved fetchResults.count records....
            //popoverController.presentPopoverFromRect(view.frame, inView: view, permittedArrowDirections: UIPopoverArrowDirection.allZeros, animated: true)
        
            browseAndLoadController.fetchResults = fetchResults
        }
    }
    
    func popoverControllerDidDismissPopover(popoverController: UIPopoverController)
    {
        if let _selectedEntity = browseAndLoadController.selectedEntity
        {
            reactionDiffusionModel = ReactionDiffusionEntity.createInstanceFromEntity(_selectedEntity)
        }
    }

    func setUpMetal()
    {
        device = MTLCreateSystemDefaultDevice()
        
        println("device = \(device)")
        
        if device == nil
        {
            errorFlag = true
            
    
        }
        else
        {
            defaultLibrary = device.newDefaultLibrary()
            commandQueue = device.newCommandQueue()
            
            let kernelFunction = defaultLibrary.newFunctionWithName(reactionDiffusionModel.shaderName)
            pipelineState = device.newComputePipelineStateWithFunction(kernelFunction!, error: nil)
            
            setUpTexture()
            run()
        }
    }

    var isRunning: Bool = false
    {
        didSet
        {
            if isRunning && oldValue != isRunning
            {
                self.run()
            }
        }
    }
    
    final func run()
    {
        if device == nil || !isRunning
        {
            return
        }
        
        Async.background()
        {
            self.image = self.applyFilter()
        }
        .main
        {
            self.imageView.image = self.image

            if self.useTextureAForInput
            {
                if self.newModelLoadedFlag
                {
                    self.newModelLoadedFlag = false
       
                    self.editor.reactionDiffusionModel = self.reactionDiffusionModel
                    
                    let kernelFunction = self.defaultLibrary.newFunctionWithName(self.reactionDiffusionModel.shaderName)
                    self.pipelineState = self.device.newComputePipelineStateWithFunction(kernelFunction!, error: nil)
                    
                    self.resetSimulationFlag = true
                }
                
                if self.resetSimulationFlag
                {
                    self.resetSimulationFlag = false
                    
                    self.setUpTexture()
                }
                
                if self.requestedReactionDiffusionModel != nil
                {
                    let _requestedReactionDiffusionModel = self.requestedReactionDiffusionModel!
                    
                    switch _requestedReactionDiffusionModel
                    {
                        case .GrayScott:
                            self.reactionDiffusionModel = GrayScott()
                        case .FitzHughNagumo:
                            self.reactionDiffusionModel = FitzhughNagumo()
                        case .BelousovZhabotinsky:
                            self.reactionDiffusionModel = BelousovZhabotinsky()
                    }
                    
                    self.requestedReactionDiffusionModel = nil
                    self.editor.reactionDiffusionModel = self.reactionDiffusionModel
                
                    let kernelFunction = self.defaultLibrary.newFunctionWithName(self.reactionDiffusionModel.shaderName)
                    self.pipelineState = self.device.newComputePipelineStateWithFunction(kernelFunction!, error: nil)
                }
            }
   
            let fps = Int( 1 / (CFAbsoluteTimeGetCurrent() - self.runTime))
            //println("\(fps) fps")
            self.runTime = CFAbsoluteTimeGetCurrent()
            
            self.run()
        }
    }

    func setUpTexture()
    {
        let imageRef = reactionDiffusionModel.initalImage.CGImage!

        threadGroupCount = MTLSizeMake(16, 16, 1)
        threadGroups = MTLSizeMake(Int(imageSide) / threadGroupCount.width, Int(imageSide) / threadGroupCount.height, 1)

        var rawData = [UInt8](count: Int(imageSide * imageSide * 4), repeatedValue: 0)

        let context = CGBitmapContextCreate(&rawData, imageSide, imageSide, bitsPerComponent, bytesPerRow, rgbColorSpace, bitmapInfo)
        
        CGContextDrawImage(context, CGRectMake(0, 0, CGFloat(imageSide), CGFloat(imageSide)), imageRef)
        
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(MTLPixelFormat.RGBA8Unorm, width: Int(imageSide), height: Int(imageSide), mipmapped: false)
        
        textureA = device.newTextureWithDescriptor(textureDescriptor)
        
        let outTextureDescriptor = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(textureA.pixelFormat, width: textureA.width, height: textureA.height, mipmapped: false)
        textureB = device.newTextureWithDescriptor(outTextureDescriptor)
        
        region = MTLRegionMake2D(0, 0, Int(imageSide), Int(imageSide))
        textureA.replaceRegion(region, mipmapLevel: 0, withBytes: &rawData, bytesPerRow: Int(bytesPerRow))
    }

    final func applyFilter() -> UIImage
    {
        let commandBuffer = commandQueue.commandBuffer()
        let commandEncoder = commandBuffer.computeCommandEncoder()
        
        commandEncoder.setComputePipelineState(pipelineState)
        
        var buffer: MTLBuffer = device.newBufferWithBytes(&reactionDiffusionModel.reactionDiffusionStruct, length: sizeof(ReactionDiffusionParameters), options: nil)
        commandEncoder.setBuffer(buffer, offset: 0, atIndex: 0)
        
        commandQueue = device.newCommandQueue()
        
        for _ in 0 ... reactionDiffusionModel.iterationsPerFrame
        {
            if useTextureAForInput
            {
                commandEncoder.setTexture(textureA, atIndex: 0)
                commandEncoder.setTexture(textureB, atIndex: 1)
            }
            else
            {
                commandEncoder.setTexture(textureB, atIndex: 0)
                commandEncoder.setTexture(textureA, atIndex: 1)
            }

            commandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)

            useTextureAForInput = !useTextureAForInput
        }
        
        commandEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
  
        if !useTextureAForInput
        {
            textureB.getBytes(&imageBytes, bytesPerRow: Int(bytesPerRow), fromRegion: region, mipmapLevel: 0)
        }
        else
        {
            textureA.getBytes(&imageBytes, bytesPerRow: Int(bytesPerRow), fromRegion: region, mipmapLevel: 0)
        }
        
        let providerRef = CGDataProviderCreateWithCFData(NSData(bytes: &imageBytes, length: providerLength))
       
        let imageRef = CGImageCreate(UInt(imageSize.width), UInt(imageSize.height), bitsPerComponent, bitsPerPixel, bytesPerRow, rgbColorSpace, bitmapInfo, providerRef, nil, false, renderingIntent)

        return UIImage(CGImage: imageRef)!
    }

    
    override func viewDidLayoutSubviews()
    {
        if errorFlag
        {
            let alertController = UIAlertController(title: "ReDiLab v1.0\nReaction Diffusion Laboratory", message: "\nSorry! ReDiLab requires an iPad with an A7 or later processor. It appears your device is earlier.", preferredStyle: UIAlertControllerStyle.Alert)

            presentViewController(alertController, animated: true, completion: nil)
            
            errorFlag = false
        }

        let imageSide = view.frame.height - topLayoutGuide.length
        
        imageView.frame = CGRect(x: 0, y: topLayoutGuide.length, width: imageSide, height: imageSide)
     
        let editorWidth = CGFloat(view.frame.width - imageSide)
        
        editor.frame = CGRect(x: imageSide, y: topLayoutGuide.length, width: editorWidth, height: imageSide)
    }
    
    override func didReceiveMemoryWarning()
    {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func supportedInterfaceOrientations() -> Int
    {
        return Int(UIInterfaceOrientationMask.Landscape.rawValue)
    }
}



