//
//  RNVideoEditorModule.swift
//  ReactionSocial
//
//  Created by Vuong Duc Lam on 9/3/19.
//

import Foundation
import AVFoundation
import UIKit

@objc(RNVideoEditorModule)
class RNVideoEditorModule: NSObject {
    let VIDEO_FPS: Int = 30
    let VIDEO_BITRATE: Int = 4000000
    var exportSession: SDAVAssetExportSession? = nil
    
    @objc static func requiresMainQueueSetup() -> Bool {
        return false
    }
    
    func exportSession(
        asset: AVAsset,
        outputURL: URL,
        timeRange: CMTimeRange?,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) -> Void {
        self.exportSession = SDAVAssetExportSession(asset: asset)
        guard self.exportSession != nil else { return reject(nil, nil, "Export failed.") }
        
        self.exportSession!.outputURL = outputURL
        self.exportSession!.outputFileType = AVFileType.mp4.rawValue
        self.exportSession!.shouldOptimizeForNetworkUse = true
        if (timeRange != nil) {
            self.exportSession!.timeRange = timeRange!
        }
        
        let videoSize = RNVideoEditorUtilities.determineOutputVideoSize(asset: asset)
        
        self.exportSession!.videoSettings = [
            AVVideoCodecKey: AVVideoCodecH264,
            AVVideoWidthKey: String(videoSize.width),
            AVVideoHeightKey: String(videoSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoMaxKeyFrameIntervalKey: self.VIDEO_FPS,
                AVVideoAverageBitRateKey: self.VIDEO_BITRATE,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264High40
            ]
        ]
        self.exportSession!.audioSettings = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44100,
            AVEncoderBitRateKey: 128000
        ]
        
        self.exportSession!.exportAsynchronously(completionHandler: {
            switch self.exportSession!.status {
            case .completed:
                self.exportSession = nil
                resolve(outputURL.absoluteString)
            case .failed:
                reject(nil, nil, "Export failed.")
            case .cancelled:
                reject(nil, nil, "Cancelled by user.")
            default:
                reject(nil, nil, "Export failed.")
            }
        })
    }
    
    @objc func getLocalURL(
        _ source: String,
        resolver resolve: RCTPromiseResolveBlock,
        rejecter reject: RCTPromiseRejectBlock
    ) -> Void {
        do {
            let asset: AVURLAsset! = try RNVideoEditorUtilities.requestAsset(source) as? AVURLAsset
            resolve(asset.url.absoluteString)
        } catch {
            reject(nil, nil, error)
        }
    }
    
    @objc func getVideoInfo(
        _ source: String,
        resolver resolve: RCTPromiseResolveBlock,
        rejecter reject: RCTPromiseRejectBlock
    ) -> Void {
        do {
            let asset: AVAsset! = try RNVideoEditorUtilities.requestAsset(source)
            var data: [String: Any] = [:]
            
            data["duration"] = asset.duration.seconds
            
            resolve(data)
        } catch {
            reject(nil, nil, error)
        }
    }
    
    @objc func getPictureAtPosition(
        _ source: String,
        options: NSDictionary,
        resolver resolve: RCTPromiseResolveBlock,
        rejecter reject: RCTPromiseRejectBlock
    ) -> Void {
        do {
            let asset: AVAsset! = try RNVideoEditorUtilities.requestAsset(source)
            let format: String = options.object(forKey: "format") as? String ?? "base64"
            var second: Double = options.object(forKey: "second") as? Double ?? 0
            if second > Double(asset.duration.seconds) || second < 0 {
                second = 0
            }
            
            let imageGenerator: AVAssetImageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            let timestamp: CMTime = CMTime(seconds: second, preferredTimescale: 600)
            
            let imageRef: CGImage = try imageGenerator.copyCGImage(at: timestamp, actualTime: nil)
            let image: UIImage = UIImage(cgImage: imageRef)
            let imgData: Data? = UIImageJPEGRepresentation(image, 0.5)
            
            if format == "jpg" {
                let outputURL: URL = try RNVideoEditorUtilities.createTempFile("jpg")
                try imgData?.write(to: outputURL, options: .atomic)
                resolve(outputURL.absoluteString)
            } else {
                let base64String: String? = imgData?.base64EncodedString(options: Data.Base64EncodingOptions.init(rawValue: 0))
                resolve(base64String != nil ? "data:image/png;base64,\(base64String!)" : "")
            }
        } catch {
            reject(nil, nil, error)
        }
    }
    
    @objc func getPictures(
        _ source: String,
        resolver resolve: RCTPromiseResolveBlock,
        rejecter reject: RCTPromiseRejectBlock
    ) -> Void {
        do {
            let asset: AVAsset! = try RNVideoEditorUtilities.requestAsset(source)
            
            var numberOfPictures: Double = 8
            let duration: Double = asset.duration.seconds
            if duration > 30 {
                numberOfPictures = 4 * (floor((duration / 30) + 1))
            }
            let second: Double = floor(duration / numberOfPictures)
            
            let imageGenerator: AVAssetImageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            
            var pictures: Array<String> = []
            for n in 0..<Int(numberOfPictures) {
                let timestamp: CMTime = CMTime(seconds: (Double(n) * second), preferredTimescale: 600)
                let imageRef: CGImage = try imageGenerator.copyCGImage(at: timestamp, actualTime: nil)
                let image: UIImage = UIImage(cgImage: imageRef)
                let imgData: Data? = UIImageJPEGRepresentation(image, 0.5)
                
                let base64String: String? = imgData?.base64EncodedString(options: Data.Base64EncodingOptions.init(rawValue: 0))
                let picture = base64String != nil ? "data:image/png;base64,\(base64String!)" : ""
                pictures.append(picture)
            }
            
            resolve(pictures)
        } catch {
            reject(nil, nil, error)
        }
    }
    
    @objc func merge(
        _ videoFiles: Array<String>,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) -> Void {
        do {
            var assets: Array<AVAsset> = Array()
            for source in videoFiles {
                let asset: AVAsset! = try RNVideoEditorUtilities.requestAsset(source)
                assets.append(asset)
            }
            
            let compositionAsset: AVMutableComposition = AVMutableComposition()
            let videoTrack: AVMutableCompositionTrack? = compositionAsset.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            let soundTrack: AVMutableCompositionTrack? = compositionAsset.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            
            var insertTime = kCMTimeZero
            for asset in assets {
                //        let track = asset.tracks(withMediaType: .video)[0]
                //        let width: CGFloat = track.naturalSize.width
                //        let height: CGFloat = track.naturalSize.height
                //        var transforms: CGAffineTransform = track.preferredTransform
                //        if width > height {
                //          transforms = transforms.concatenating(CGAffineTransform(rotationAngle: .pi / 2))
                //          transforms = transforms.concatenating(CGAffineTransform(translationX: height, y: 0))
                //        }
                //        videoTrack?.preferredTransform = transforms
                
                try videoTrack?.insertTimeRange(CMTimeRangeMake(kCMTimeZero, asset.duration), of: asset.tracks(withMediaType: .video)[0], at: insertTime)
                try soundTrack?.insertTimeRange(CMTimeRangeMake(kCMTimeZero, asset.duration), of: asset.tracks(withMediaType: .audio)[0], at: insertTime)
                insertTime = CMTimeAdd(insertTime, asset.duration)
            }
            
            let outputURL: URL = try RNVideoEditorUtilities.createTempFile("mp4")
            
            self.exportSession(
                asset: compositionAsset,
                outputURL: outputURL,
                timeRange: nil,
                resolver: resolve,
                rejecter: reject
            )
        } catch {
            reject(nil, nil, error)
        }
    }
    
    @objc func mergeWithAudio(
        _ source: String,
        audioSource: String,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) -> Void {
        do {
            let videoAsset: AVAsset! = try RNVideoEditorUtilities.requestAsset(source)
            let audioAsset: AVAsset! = try RNVideoEditorUtilities.requestAsset(audioSource)
            
            let compositionAsset: AVMutableComposition = AVMutableComposition()
            var videoTracks: [AVMutableCompositionTrack] = []
            var soundTracks: [AVMutableCompositionTrack] = []
            
            if let videoTrack = compositionAsset.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
               let audioTrack = compositionAsset.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                videoTracks.append(videoTrack)
                soundTracks.append(audioTrack)
                
                if let videoAssetTrack: AVAssetTrack = videoAsset.tracks(withMediaType: .video).first,
                   let audioAssetTrack: AVAssetTrack = audioAsset.tracks(withMediaType: .audio).first {
                    do {
                        try videoTracks.first?.insertTimeRange(CMTimeRangeMake(kCMTimeZero, videoAssetTrack.timeRange.duration), of: videoAssetTrack, at: kCMTimeZero)
                        try soundTracks.first?.insertTimeRange(CMTimeRangeMake(kCMTimeZero, audioAssetTrack.timeRange.duration), of: audioAssetTrack, at: kCMTimeZero)
                        videoTrack.preferredTransform = videoAssetTrack.preferredTransform
                    } catch{
                        throw "Export failed."
                    }
                }
            }
            
            let outputURL: URL = try RNVideoEditorUtilities.createTempFile("mp4")
            
            self.exportSession(
                asset: compositionAsset,
                outputURL: outputURL,
                timeRange: nil,
                resolver: resolve,
                rejecter: reject
            )
        } catch {
            reject(nil, nil, error)
        }
    }
    
    @objc func trim(
        _ source: String,
        options: NSDictionary,
        resolver resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) -> Void {
        do {
            let asset: AVAsset! = try RNVideoEditorUtilities.requestAsset(source)
            let duration: Double = asset.duration.seconds
            
            var startTime: Double = options.object(forKey: "startTime") as? Double ?? 0
            var endTime: Double = options.object(forKey: "endTime") as? Double ?? 0
            if startTime < 0 { startTime = 0 }
            if endTime > duration { endTime = duration }
            
            let outputURL: URL = try RNVideoEditorUtilities.createTempFile("mp4")
            let timeRange = CMTimeRange(start: CMTime(seconds: startTime, preferredTimescale: asset.duration.timescale), end: CMTime(seconds: endTime, preferredTimescale: asset.duration.timescale))
            
            self.exportSession(
                asset: asset,
                outputURL: outputURL,
                timeRange: timeRange,
                resolver: resolve,
                rejecter: reject
            )
        } catch {
            reject(nil, nil, error)
        }
    }
    
    @objc func cleanFiles(
        _ callBack: RCTResponseSenderBlock?
    ) -> Void {
        do {
            try RNVideoEditorUtilities.cleanFiles()
            callBack!(nil)
        } catch {
        }
    }
    
    @objc func cancel(
        _ callBack: RCTResponseSenderBlock?
    ) -> Void {
        guard self.exportSession != nil else { return callBack!(nil) }
        self.exportSession!.cancelExport()
        callBack!(nil)
    }
}
