//
//  ViewController.swift
//  ios
//
//  Created by hiroyuki obinata on 2023/03/21.
//

import AVFoundation
import UIKit

class ViewController: UIViewController {

    @IBOutlet weak var imageView: UIImageView!

    let captureSession = AVCaptureSession()

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.

        let screenWidth = self.view.bounds.width
        let screenHeight = self.view.bounds.height
        self.imageView.frame = CGRect(x: 0, y: 0, width: screenWidth, height: screenHeight)
        self.imageView.contentMode = .scaleAspectFit

        captureSession.beginConfiguration()

        guard let captureDevice = AVCaptureDevice.default(for: .video),
            let deviceInput = try? AVCaptureDeviceInput(device: captureDevice),
            captureSession.canAddInput(deviceInput)
        else { return }

        captureSession.addInput(deviceInput)
        captureSession.sessionPreset = .hd1280x720

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "sampleBufferQueue"))
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true

        captureSession.addOutput(videoOutput)

        captureSession.commitConfiguration()

        //yolov5NcnnInit(<#T##param: UnsafePointer<CChar>!##UnsafePointer<CChar>!#>, <#T##bin: UnsafePointer<CChar>!##UnsafePointer<CChar>!#>)
        guard let binFile = Bundle.main.path(forResource: "yolov5s", ofType: "bin") else { return }
        guard let paramFile = Bundle.main.path(forResource: "yolov5s", ofType: "param") else {
            return
        }
        print(binFile, paramFile)
        yolov5NcnnInit(
            Array(paramFile.utf8).map({ CChar($0) }) + [0],
            Array(binFile.utf8).map({ CChar($0) }) + [0])

        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
        }
    }
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {

        guard let pixelBuffe = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffe)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        let image = UIImage(cgImage: cgImage)
        let rawData = getByteArrayFromImage(img: image)
        let objects: UnsafeMutablePointer<Object>? = yolov5NcnnDetect(
            rawData, UInt32(image.size.width), UInt32(image.size.height), true)
        if (objects != nil) {
            print(objects![0])
        }
        DispatchQueue.main.async {
            self.imageView.image = image
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
    }

    func getByteArrayFromImage(img: UIImage) -> [UInt8] {
        let data = img.cgImage?.dataProvider?.data
        let length = CFDataGetLength(data)
        var rawData = [UInt8](repeating: 0, count: length)
        CFDataGetBytes(data, CFRange(location: 0, length: length), &rawData)

        return rawData
    }
}
