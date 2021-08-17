//
//  MainViewController.swift
//  PersonSegment
//
//  Created by 徐润康 on 2021/8/12.
//

import UIKit
import Vision
import AVFoundation
import VideoToolbox
import CoreImage.CIFilterBuiltins
import MetalKit

class MainViewController: UIViewController {
    
    private lazy var backgroundImage: CIImage = {
        let image = UIImage(named: "background.jpg")!
        return CIImage(cgImage: image.cgImage!)
    }()
    
    private var outputImage: CIImage?
    
    private var session = AVCaptureSession()
    private lazy var metalDevice = MTLCreateSystemDefaultDevice()!
    private lazy var metalCommandQueue = metalDevice.makeCommandQueue()!
    private lazy var ciContext = CIContext(mtlDevice: metalDevice)
    private lazy var mtkView = MTKView(frame: self.view.frame)
    
    private let blendWithMaskFilter = CIFilter.blendWithMask()
    private let requestHandler = VNSequenceRequestHandler()
    private let personSegmentationRequest = VNGeneratePersonSegmentationRequest()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupMetal()
        setupPersonSegmentationRequest()
        setupCaptureSession()
    }
}

private extension MainViewController {
    private func setupPersonSegmentationRequest() {
        personSegmentationRequest.qualityLevel = .balanced
        personSegmentationRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8
    }
    
    private func setupMetal() {
        view.addSubview(mtkView)
        
        mtkView.delegate = self
        mtkView.device = metalDevice
        mtkView.framebufferOnly = false
        mtkView.enableSetNeedsDisplay = false
    }
    
    private func setupCaptureSession() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            fatalError("Error In Init AVCaptureDevice")
        }
        
        let frameDuration = CMTime(seconds: 1, preferredTimescale: 60)
        try? device.lockForConfiguration()
        device.activeVideoMinFrameDuration = frameDuration
        device.activeVideoMaxFrameDuration = frameDuration
        device.unlockForConfiguration()
        
        guard let input = try? AVCaptureDeviceInput.init(device: device) else {
            fatalError("Error In Init AVCaptureDevice")
        }
        
        session.sessionPreset = .hd1920x1080
        session.addInput(input)
        
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = false
        output.setSampleBufferDelegate(self, queue: .global())
        
        session.addOutput(output)
        output.connections.first?.videoOrientation = .portrait
        output.connections.first?.isVideoMirrored = true
        session.startRunning()
    }
    
    private func runPersonSegment(input inputPixelBuffer: CVPixelBuffer,
                                  mask maskPixelBuffer: CVPixelBuffer,
                                  background backgroundImage: CIImage) -> CIImage? {
        let input = CIImage(cvPixelBuffer: inputPixelBuffer)
        var mask = CIImage(cvPixelBuffer: maskPixelBuffer)
        
        var scaleX = input.extent.width / mask.extent.width
        var scaleY = input.extent.height / mask.extent.height
        mask = mask.transformed(by: .init(scaleX: scaleX, y: scaleY))
        
        scaleX = input.extent.width / backgroundImage.extent.width
        scaleY = input.extent.height / backgroundImage.extent.height
        let background = backgroundImage.transformed(by: .init(scaleX: scaleX, y: scaleY))
        
        blendWithMaskFilter.inputImage = input
        blendWithMaskFilter.maskImage = mask
        blendWithMaskFilter.backgroundImage = background
        
        return blendWithMaskFilter.outputImage
    }
}

extension MainViewController: MTKViewDelegate {
    func draw(in view: MTKView) {
        guard let commandBuffer = metalCommandQueue.makeCommandBuffer() else {
            return
        }
        
        guard let ciImage = outputImage else {
            return
        }
        
        guard let currentDrawable = view.currentDrawable else {
            return
        }
        
        let drawSize = view.drawableSize
        let scaleX = drawSize.width / ciImage.extent.width
        
        let newImage = ciImage.transformed(by: .init(scaleX: scaleX, y: scaleX))
        
        self.ciContext.render(newImage,
                              to: currentDrawable.texture,
                              commandBuffer: commandBuffer,
                              bounds: newImage.extent,
                              colorSpace: CGColorSpaceCreateDeviceRGB())
        
        commandBuffer.present(currentDrawable)
        commandBuffer.commit()
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
    }
}

extension MainViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        guard let input = sampleBuffer.imageBuffer else { return }
        
        try? requestHandler.perform([personSegmentationRequest], on: input)
        guard let mask = personSegmentationRequest.results?.first?.pixelBuffer else { return }
        // messure(task: "blend image") {
        let blendImage = runPersonSegment(input: input, mask: mask, background: backgroundImage)
        outputImage = blendImage
        // }
    }
    
    func messure(task: String, action: () -> Void){
        let start = CFAbsoluteTimeGetCurrent()
        action()
        let end = CFAbsoluteTimeGetCurrent()
        print("\(task) cost：\((end-start) * 1000)ms")
    }
}
