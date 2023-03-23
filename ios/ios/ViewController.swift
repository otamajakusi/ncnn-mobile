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
        var image = UIImage(cgImage: cgImage)
        let rawData = getByteArrayFromImage(img: image)
        let objects: UnsafePointer<Yolov5NcnnObject>? = yolov5NcnnDetect(
            rawData, UInt32(image.size.width), UInt32(image.size.height), true)
        if objects != nil {

            // Begin an image context with the size of the image
            UIGraphicsBeginImageContext(image.size)

            // Draw the original image onto the context
            image.draw(at: CGPoint.zero)

            guard let context = UIGraphicsGetCurrentContext() else {
                return
            }
            var index = 0
            while true {
                // Create a CGRect object to represent the rectangle
                let object = objects![index]
                let x = Int(object.x)
                let y = Int(object.y)
                let w = Int(object.w)
                let h = Int(object.h)
                let last = object.last
                let rectangle = CGRect(x: x, y: y, width: w, height: h)

                // Set the fill color of the rectangle
                UIColor.red.setStroke()

                // Set the line width of the rectangle border
                context.setLineWidth(4)

                // Draw the rectangle border
                context.stroke(rectangle)

                // Set up the text attributes
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .center
                let textAttributes = [
                    NSAttributedString.Key.font: UIFont.systemFont(ofSize: 32),
                    NSAttributedString.Key.foregroundColor: UIColor.white,
                    NSAttributedString.Key.paragraphStyle: paragraphStyle,
                ]

                // Draw the text on the image
                let textRect = CGRect(x: x, y: y, width: 128, height: 64)
                let label = yolov5NcnnClassName(object.label)
                if label != nil {
                    let text = String(cString: label!)
                    text.draw(in: textRect, withAttributes: textAttributes)
                }
                if last {
                    break
                }
                index += 1
            }

            // Get the image from the context
            image = UIGraphicsGetImageFromCurrentImageContext()!

            // End the image context
            UIGraphicsEndImageContext()
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
