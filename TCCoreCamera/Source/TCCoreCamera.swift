//
//  CameraManager.swift
//  CustomCamera
//
//  Created by Taras Chernyshenko on 2/28/18.
//  Copyright © 2018 Taras Chernyshenko. All rights reserved.
//

import UIKit
import AVFoundation

class TCCoreCamera: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate,
    AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate {
    typealias VideoCompletion = (URL) -> Void
    typealias PhotoCompletion = (UIImage) -> Void
    
    public enum CameraType {
        case photo
        case video
    }
    
    public enum CameraPosition {
        case front
        case back
    }
    
    private let recordingQueue = DispatchQueue(label: "recording.queue")
    private let audioSettings: [String : Any]
    private let videoSettings: [String : Any]
    private let view: UIView
    private let audioWriterInput: AVAssetWriterInput
    private let videoWriterInput: AVAssetWriterInput
    private let photoOutput: AVCapturePhotoOutput = AVCapturePhotoOutput()
    private let videoOutput: AVCaptureVideoDataOutput = AVCaptureVideoDataOutput()
    private let audioOutput: AVCaptureAudioDataOutput = AVCaptureAudioDataOutput()
    private let session: AVCaptureSession = AVCaptureSession()
    
    private var deviceInput: AVCaptureDeviceInput?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var assetWriter: AVAssetWriter?
    private var recordingURL: URL?
    private(set) var isRecording: Bool = false
    private var isRecordingSessionStarted: Bool = false
    private(set) var cameraPosition: CameraPosition = .back
    private(set) var zoomFactor: CGFloat = 1.0 {
        didSet {
            if self.zoomFactor < 1.0 || self.zoomFactor > self.maxZoomFactor { return }
            if let device = self.deviceInput?.device {
                do {
                    try device.lockForConfiguration()
                    device.ramp(toVideoZoomFactor: self.zoomFactor, withRate: 3.0)
                    device.unlockForConfiguration()
                }
                catch {
                    print(error.localizedDescription)
                }
            }
        }
    }
    
    open var videoCompletion: VideoCompletion?
    open var photoCompletion: PhotoCompletion?
    open var camereType: CameraType = .photo {
        didSet {
            self.updateFileStorage(with: self.camereType)
        }
    }
    
    open var maxZoomFactor: CGFloat = 10.0
    
    init(view: UIView) {
        self.view = view
        self.audioSettings = [
            AVFormatIDKey : kAudioFormatAppleIMA4,
            AVNumberOfChannelsKey : 1,
            AVSampleRateKey : 32000.0
        ]
        self.videoSettings = [
            AVVideoCodecKey : AVVideoCodecH264,
            AVVideoWidthKey : 2 * view.frame.width,
            AVVideoHeightKey : 2 * view.frame.height
        ]
        self.audioWriterInput = AVAssetWriterInput(mediaType: .audio,
            outputSettings: self.audioSettings)
        self.videoWriterInput = AVAssetWriterInput(mediaType: .video,
            outputSettings: self.videoSettings)
        super.init()
        self.updateFileStorage(with: self.camereType)
        self.initialize()
        self.configureWriters()
        self.configurePreview()
        self.configureSession()
    }
    
    open func startRecording() {
        switch self.camereType {
            case .photo:
                let settings = AVCapturePhotoSettings()
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            case .video:
                self.configureWriters()
                self.updateFileStorage(with: self.camereType)
                guard let assetWriter = self.assetWriter else {
                    assertionFailure("AssetWriter was not initialized")
                    return
                }
                if !assetWriter.startWriting() {
                    assertionFailure("AssetWriter error: \(assetWriter.error.debugDescription)")
                }
                self.isRecording = true
                self.videoOutput.setSampleBufferDelegate(self, queue: self.recordingQueue)
                self.audioOutput.setSampleBufferDelegate(self, queue: self.recordingQueue)
        }
    }
    
    open func stopRecording() {
        self.videoOutput.setSampleBufferDelegate(nil, queue: nil)
        self.audioOutput.setSampleBufferDelegate(nil, queue: nil)
        self.assetWriter?.finishWriting {
            if let fileURL = self.recordingURL {
                self.videoCompletion?(fileURL)
            }
            self.isRecording = false
            self.isRecordingSessionStarted = false
        }
    }
    
    open func flip() {
        switch self.cameraPosition {
            case .front:
                self.cameraPosition = .back
                self.addVideoInput(position: .back)
            case .back:
                self.cameraPosition = .front
                self.addVideoInput(position: .front)
        }
        //TODO: we need to configure AVCaptureConnection videoOrientation. It's a temporary solution
        self.configureSession()
    }
    
    open func zoomIn() {
        if self.zoomFactor < self.maxZoomFactor {
            self.zoomFactor = self.zoomFactor + 0.035
        }
    }
    
    open func zoomOut() {
        if self.zoomFactor > 1.0 {
            self.zoomFactor = self.zoomFactor - 0.035
        }
    }
    
    private func updateFileStorage(with mode: CameraType) {
        var fileURL: URL
        switch mode {
        case .video:
            fileURL = URL(fileURLWithPath: "\(NSTemporaryDirectory() as String)/video.mov")
        case .photo:
            fileURL = URL(fileURLWithPath: "\(NSTemporaryDirectory() as String)/image.mp4")
        }
        self.recordingURL = fileURL
        let fileManager = FileManager()
        if fileManager.isDeletableFile(atPath: fileURL.path) {
            _ = try? fileManager.removeItem(atPath: fileURL.path)
        }
    }
    
    private func initialize() {
        self.session.sessionPreset = .high
        self.videoWriterInput.expectsMediaDataInRealTime = true
        self.audioWriterInput.expectsMediaDataInRealTime = true
        self.photoOutput.setPreparedPhotoSettingsArray([
            AVCapturePhotoSettings(format: [AVVideoCodecKey : AVVideoCodecJPEG])
        ], completionHandler: nil)
        self.cameraPosition = .front
        self.addVideoInput(position: .front)
    }
    
    func addVideoInput(position: AVCaptureDevice.Position) {
        guard let device: AVCaptureDevice = AVCaptureDevice.default(.builtInWideAngleCamera,
            for: .video, position: position) else { return }
        if let currentInput = self.deviceInput {
            self.session.removeInput(currentInput)
            self.deviceInput = nil
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if self.session.canAddInput(input) {
                self.session.addInput(input)
                self.deviceInput = input
            }
        } catch {
            print(error)
        }
    }
    
    private func configureWriters() {
        do {
            if let fileURL = self.recordingURL {
                self.assetWriter = try AVAssetWriter(outputURL: fileURL, fileType: .mov)
            }
        } catch {
            print(error.localizedDescription)
        }
        guard let assetWriter = self.assetWriter else {
            assertionFailure("AssetWriter was not initialized")
            return
        }
        if assetWriter.canAdd(self.videoWriterInput) {
            assetWriter.add(self.videoWriterInput)
        }
        if assetWriter.canAdd(self.audioWriterInput) {
            assetWriter.add(self.audioWriterInput)
        }
    }
    
    private func configurePreview() {
        let previewLayer: AVCaptureVideoPreviewLayer = AVCaptureVideoPreviewLayer(session: self.session)
//        importent line of code what will did a trick
        previewLayer.videoGravity = .resizeAspectFill
        let rootLayer = self.view.layer
        rootLayer.masksToBounds = true
        previewLayer.frame = CGRect(x: 0, y: 0,
                                    width: UIScreen.main.bounds.width,
                                    height: UIScreen.main.bounds.height/2)
        rootLayer.insertSublayer(previewLayer, at: 0)
        self.previewLayer = previewLayer
        DispatchQueue(label: "MANHPD2").async {
            self.session.startRunning()
        }
    }
    
    private func configureSession() {
        DispatchQueue.main.async {
            self.session.beginConfiguration()
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }
            if let videoConnection = self.videoOutput.connection(with: .video) {
                if videoConnection.isVideoStabilizationSupported {
                    videoConnection.preferredVideoStabilizationMode = .auto
                }
                videoConnection.videoOrientation = .portrait
            }
            self.session.commitConfiguration()
            let audioDevice = AVCaptureDevice.default(for: .audio)
            guard let audioDevice = audioDevice else {
                return
            }
            let audioIn = try? AVCaptureDeviceInput(device: audioDevice)
            if self.session.canAddInput(audioIn!) {
                self.session.addInput(audioIn!)
            }
            if self.session.canAddOutput(self.audioOutput) {
                self.session.addOutput(self.audioOutput)
            }
        }
    }
    
    func captureOutput(_ captureOutput: AVCaptureOutput, didOutput
        sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if !self.isRecordingSessionStarted {
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            self.assetWriter?.startSession(atSourceTime: presentationTime)
            self.isRecordingSessionStarted = true
        }
        self.appendSampleBuffer(sampleBuffer)
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photoSampleBuffer: CMSampleBuffer?, previewPhoto previewPhotoSampleBuffer: CMSampleBuffer?, resolvedSettings: AVCaptureResolvedPhotoSettings, bracketSettings: AVCaptureBracketedStillImageSettings?, error: Error?) {
        if let buffer = photoSampleBuffer, let data = AVCapturePhotoOutput.jpegPhotoDataRepresentation(forJPEGSampleBuffer: buffer, previewPhotoSampleBuffer: nil),
            let image = UIImage(data: data) {
            self.photoCompletion?(image)
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        
    }
    
    private func appendSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        let description = CMFormatDescriptionGetMediaType(CMSampleBufferGetFormatDescription(sampleBuffer)!)
        switch description {
        case kCMMediaType_Audio:
            if self.audioWriterInput.isReadyForMoreMediaData {
//                print("appendSampleBuffer audio");
                self.audioWriterInput.append(sampleBuffer)
            }
        default:
            if self.videoWriterInput.isReadyForMoreMediaData {
//                print("appendSampleBuffer video");
                if !self.videoWriterInput.append(sampleBuffer) {
                    print("Error writing video buffer");
                }
            }
        }
    }
}
