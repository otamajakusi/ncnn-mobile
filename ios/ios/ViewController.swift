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
    var tracking = false

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

        let longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(longPressHandler))

        self.view.addGestureRecognizer(longPressRecognizer)

        guard let binFile = Bundle.main.path(forResource: "yolov5s", ofType: "bin") else { return }
        guard let paramFile = Bundle.main.path(forResource: "yolov5s", ofType: "param") else {
            return
        }
        yolov5NcnnInit(
            Array(paramFile.utf8).map({ CChar($0) }) + [0],
            Array(binFile.utf8).map({ CChar($0) }) + [0])

        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
        }
    }

    @objc func longPressHandler(gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            print("tracking \(tracking)")
            if tracking {
                tracking = false
            } else {
                tracking = true
            }
        }
    }
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let imgBuf = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImg = CIImage(cvPixelBuffer: imgBuf)

        let ciCtx = CIContext()
        guard let cgImg = ciCtx.createCGImage(ciImg, from: ciImg.extent) else { return }
        var uiImg = UIImage(cgImage: cgImg)

        guard let rawData = getByteArrayFromImage(img: uiImg) else { return }

        let imgWidth = UInt32(uiImg.size.width)
        let imgHeight = UInt32(uiImg.size.height)

        // begin context
        let renderer = UIGraphicsImageRenderer(size: uiImg.size)
        uiImg = renderer.image { (context) in
            uiImg.draw(at: CGPoint.zero)

            guard
                let objects: UnsafePointer<Yolov5NcnnObject> = yolov5NcnnDetect(
                    rawData, imgWidth, imgHeight, true)
            else { return }

            var stracks: UnsafePointer<Yolov5NcnnSTrack>? = nil
            if tracking {
                stracks = yolov5NcnnDetectSTrack(objects)
            }

            let font = UIFont.systemFont(ofSize: 32)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .left
            let textAttributes = [
                NSAttributedString.Key.font: font,
                NSAttributedString.Key.foregroundColor: UIColor.black,
                NSAttributedString.Key.paragraphStyle: paragraphStyle,
            ]

            var index = 0
            while true {
                if tracking {
                    if let stracks = stracks {
                        let strack = stracks[index]
                        drawSTrack(
                            strack: strack,
                            context: context.cgContext,
                            font: font,
                            textAttributes: textAttributes
                        )
                        if strack.last {
                            break
                        }
                    } else {
                        break
                    }
                } else {
                    let object = objects[index]
                    drawObject(
                        object: object,
                        context: context.cgContext,
                        font: font,
                        textAttributes: textAttributes
                    )
                    if object.last {
                        break
                    }
                }
                index += 1
            }
        }

        DispatchQueue.main.async {
            self.imageView.image = uiImg
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
    }

    func getByteArrayFromImage(img: UIImage) -> [UInt8]? {
        guard let data = img.cgImage?.dataProvider?.data else { return nil }
        let length = CFDataGetLength(data)
        var rawData = [UInt8](repeating: 0, count: length)
        CFDataGetBytes(data, CFRange(location: 0, length: length), &rawData)

        return rawData
    }

    func drawObject(
        object: Yolov5NcnnObject, context: CGContext, font: UIFont,
        textAttributes: [NSAttributedString.Key: NSObject]
    ) {
        // bbox
        let x = Int(object.x)
        let y = Int(object.y)
        let w = Int(object.w)
        let h = Int(object.h)
        let bbox = CGRect(x: x, y: y, width: w, height: h)
        UIColor.cyan.setStroke()
        context.setLineWidth(4)
        context.stroke(bbox)

        // label
        let labelCStr = yolov5NcnnClassName(object.label)
        if let labelCStr = labelCStr {
            let label = String(cString: labelCStr)
            let labelSize = label.size(with: font)
            let labelBox = CGRect(
                x: x, y: y, width: Int(labelSize.width + 8), height: Int(labelSize.height))
            UIColor.white.setFill()
            context.fill(labelBox)
            label.draw(in: labelBox, withAttributes: textAttributes)
        }
    }

    func drawSTrack(
        strack: Yolov5NcnnSTrack, context: CGContext, font: UIFont,
        textAttributes: [NSAttributedString.Key: NSObject]
    ) {
        // bbox
        let x = Int(strack.x)
        let y = Int(strack.y)
        let w = Int(strack.w)
        let h = Int(strack.h)
        let bbox = CGRect(x: x, y: y, width: w, height: h)
        UIColor.cyan.setStroke()
        context.setLineWidth(4)
        context.stroke(bbox)

        // label
        let label = String(strack.trackId)
        let labelSize = label.size(with: font)
        let labelBox = CGRect(
            x: x, y: y, width: Int(labelSize.width + 8), height: Int(labelSize.height))
        UIColor.white.setFill()
        context.fill(labelBox)
        label.draw(in: labelBox, withAttributes: textAttributes)
    }
}

extension String {
    func size(with font: UIFont) -> CGSize {
        let attributes = [NSAttributedString.Key.font: font]
        return (self as NSString).size(withAttributes: attributes)
    }
}
