//
//  ViewController.swift
//  CustomCamera
//
//  Created by Taras Chernyshenko on 6/27/17.
//  Copyright © 2017 Taras Chernyshenko. All rights reserved.
//

import UIKit
import AVKit
import AVFoundation
import Photos
import ReplayKit

class CameraViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    @IBOutlet private weak var topView: UIView?
    @IBOutlet private weak var middleView: UIView?
    @IBOutlet private weak var innerView: UIView?
    
    @IBOutlet weak var videoView: UIView!
    @IBOutlet weak var cameraView: UIView!

    //for screen recording
//    let recorder = RPScreenRecorder.shared()

    @IBAction private func recordingButton(_ sender: UIButton) {
        guard let cameraManager = self.cameraManager else { return }
        if cameraManager.isRecording {
            cameraManager.stopRecording()
            self.setupStartButton()
            player?.pause()
            writer?.finishWriting {
                print("recoding success")
            }
        } else {
            cameraManager.startRecording()
            self.setupStopButton()
            player?.play()

            DispatchQueue(label: "ManhDZ").async {
                self.recordUIView()
            }
        }
    }

    var writer: AVAssetWriter?

    func recordUIView() {
        //_______________
        // Create an instance of AVCaptureSession
        let session = AVCaptureSession()
        session.sessionPreset = .high

        // Add a AVCaptureVideoDataOutput instance to the session
        let output = AVCaptureVideoDataOutput()
        let queue = DispatchQueue(label: "videoQueue")
        output.setSampleBufferDelegate(self, queue: queue)
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 394, //"kCVPixelBufferWidthKey as String: UIScreen.main.bounds.size.width",
            kCVPixelBufferHeightKey as String: UIScreen.main.bounds.size.height
        ]
        session.addOutput(output)

        // Create an instance of AVAssetWriter
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory() + "video.mp4")
        writer = try! AVAssetWriter(outputURL: fileURL, fileType: .mp4)

        // Create an instance of AVAssetWriterInput
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecH264,
            AVVideoWidthKey: UIScreen.main.bounds.size.width,
            AVVideoHeightKey: UIScreen.main.bounds.size.height
        ])
        input.expectsMediaDataInRealTime = true
        writer?.add(input)

//        // Create a CADisplayLink instance
//        let displayLink = CADisplayLink(target: self, selector: #selector(self.captureFrame(_:)))
//        displayLink.add(to: .current, forMode: .default)

        // Start the AVCaptureSession
        session.startRunning()
        writer?.startWriting()
        //_______________
    }

    var player: AVPlayer?

    private func playVideo() {
        guard let path = Bundle.main.path(forResource: "manhdz", ofType:"mp4") else {
            debugPrint("video.m4v not found")
            return
        }
        //2. Create AVPlayer object
        let asset = AVAsset(url: URL(fileURLWithPath: path))
        let size = asset.videoSize()
        let playerItem = AVPlayerItem(asset: asset)
        let ratio =  size.height/size.width
        self.player = AVPlayer(playerItem: playerItem)
        let withScreen = UIScreen.main.bounds.width
        //3. Create AVPlayerLayer object
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.frame = CGRect(x: 0, y: 0,
                                   width: withScreen,
                                   height: ratio * withScreen)
        //bounds of the view in which AVPlayer should be displayed
        //        playerLayer.videoGravity = .resizeAspectFill

        //4. Add playerLayer to view's layer
        self.videoView.layer.addSublayer(playerLayer)

        //5. Play Video
        //        player.play()
        //            let player = AVPlayer(url: URL(fileURLWithPath: path))
        //            let playerController = AVPlayerViewController()
        //            playerController.player = player
        //            present(playerController, animated: true) {
        //                player.play()
        //            }
    }

    @IBAction private func flipButtonPressed(_ button: UIButton) {
//        self.cameraManager?.flip()
    }
    
    private var cameraManager: TCCoreCamera?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationController?.isNavigationBarHidden = true
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(zoomingGesture(gesture:)))
        self.view.addGestureRecognizer(gesture)
        self.topView?.layer.borderWidth = 1.0
        self.topView?.layer.borderColor = UIColor.darkGray.cgColor
        self.topView?.layer.cornerRadius = 32
        self.middleView?.layer.borderWidth = 4.0
        self.middleView?.layer.borderColor = UIColor.white.cgColor
        self.middleView?.layer.cornerRadius = 32
        self.innerView?.layer.borderWidth = 32.0
        self.innerView?.layer.cornerRadius = 32
        self.setupStartButton()
        playVideo()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.cameraManager = TCCoreCamera(view: self.cameraView)
        self.cameraManager?.videoCompletion = { (fileURL) in
            self.saveInPhotoLibrary(with: fileURL)
            print("finished writing to \(fileURL.absoluteString)")
        }
        self.cameraManager?.photoCompletion = { [weak self] (image) in
            do {
                try PHPhotoLibrary.shared().performChangesAndWait {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
                self?.setupStartButton()
            } catch {
                print(error.localizedDescription)
            }
        }
        self.cameraManager?.camereType = .video
    }
    
    @objc private func zoomingGesture(gesture: UIPanGestureRecognizer) {
        let velocity = gesture.velocity(in: self.view)
        if velocity.y > 0 {
            self.cameraManager?.zoomOut()
        } else {
            self.cameraManager?.zoomIn()
        }
    }
    private func setupStartButton() {
        self.topView?.backgroundColor = UIColor.clear
        self.middleView?.backgroundColor = UIColor.clear
        
        self.innerView?.layer.borderWidth = 32.0
        self.innerView?.layer.borderColor = UIColor.white.cgColor
        self.innerView?.layer.cornerRadius = 32
        self.innerView?.backgroundColor = UIColor.lightGray
        self.innerView?.alpha = 0.2
    }
    
    private func setupStopButton() {
        self.topView?.backgroundColor = UIColor.white
        self.middleView?.backgroundColor = UIColor.white
        
        self.innerView?.layer.borderColor = UIColor.red.cgColor
        self.innerView?.backgroundColor = UIColor.red
        self.innerView?.alpha = 1.0
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    private func saveInPhotoLibrary(with fileURL: URL) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
        }) { saved, error in
            if saved {
                let alertController = UIAlertController(title: "Your video was successfully saved", message: nil, preferredStyle: .alert)
                let defaultAction = UIAlertAction(title: "OK", style: .default, handler: nil)
                alertController.addAction(defaultAction)
                DispatchQueue.main.async {
                    self.present(alertController, animated: true, completion: nil)
                }
            } else {
                print(error.debugDescription)
            }
        }
    }
}

extension AVAsset {
    func videoSize() -> CGSize {
        let tracks = self.tracks(withMediaType: AVMediaType.video)
        if (tracks.count > 0){
            let videoTrack = tracks[0]
            let size = videoTrack.naturalSize
            let txf = videoTrack.preferredTransform
            let realVidSize = size.applying(txf)
            print(videoTrack)
            print(txf)
            print(size)
            print(realVidSize)
            return realVidSize
        }
        return CGSize(width: 0, height: 0)
    }

}
