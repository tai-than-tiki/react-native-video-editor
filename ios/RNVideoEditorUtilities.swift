//
//  RNVideoEditorUtilities.swift
//  ReactionSocial
//
//  Created by Vuong Duc Lam on 9/5/19.
//

import Foundation
import AVFoundation
import Photos

extension String: LocalizedError {
    public var errorDescription: String? { return self }
}

class RNVideoEditorUtilities {
    static let filePrefix: String = "reaction-media"
    private static let DEFAULT_VIDEO_WIDTH=720
    private static let DEFAULT_VIDEO_HEIGHT=1280
    
    static func requestAsset(_ source: String) throws -> AVAsset {
        var url: URL?
        var avAsset: AVAsset?
        if source.contains("ph://") {
            let ids: Array = [source.replacingOccurrences(of: "ph://", with: "")]
            let assets: PHFetchResult = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
            let phAsset: PHAsset? = assets.firstObject
            guard phAsset != nil else { throw "Failed to request asset." }
            guard (phAsset!.mediaType == .video) else { throw "Failed to request asset." }
            
            let semaphore: DispatchSemaphore = DispatchSemaphore(value: 0)
            let options: PHVideoRequestOptions = PHVideoRequestOptions()
            options.deliveryMode = .fastFormat
            options.isNetworkAccessAllowed = true
            
            PHCachingImageManager().requestAVAsset(
                forVideo: phAsset!,
                options: options) { (asset, _, _) in
                avAsset = asset
                semaphore.signal()
            }
            semaphore.wait()
        } else if source.contains("assets-library") {
            url = NSURL(string: source)! as URL
        } else {
            url = URL(string: source, relativeTo: Bundle.main.resourceURL)
        }
        if url != nil { avAsset = AVAsset(url: url!) }
        guard avAsset != nil else { throw "Failed to request asset." }
        
        return avAsset!
    }
    
    static func createTempFile(_ fileExtension: String) throws -> URL {
        do {
            let fileName: String = ProcessInfo.processInfo.globallyUniqueString
            let fileManager: FileManager = FileManager.default
            
            let dir: URL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let url: URL = dir.appendingPathComponent("\(RNVideoEditorUtilities.filePrefix)-\(fileName).\(fileExtension)")
            
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            try fileManager.removeItem(atPath: url.path)
            
            return url;
        } catch {
            throw "Failed to create temp file."
        }
    }
    
    static func cleanFiles() throws -> Void {
        do {
            let fileManager: FileManager = FileManager.default
            let dir: URL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let files: [URL] = try fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [])
            for file in files {
                if file.lastPathComponent.contains(RNVideoEditorUtilities.filePrefix) {
                    try fileManager.removeItem(atPath: file.path)
                }
            }
        } catch  {
            throw "Failed to clean files."
        }
    }
    
    static func determineOutputVideoSize(asset: AVAsset) ->VideoSize{
        do{
            let track = asset.tracks(withMediaType: .video)[0]
            let width = Int(track.naturalSize.width)
            let height = Int(track.naturalSize.height)
            let videoSize = VideoSize(width: width, height: height)
//            print("RNVideoEditorUtilities: determineOutputVideoSize video size before scale: \(videoSize)")
            applyScale(videoSize: videoSize)
//            print("RNVideoEditorUtilities: determineOutputVideoSize video size after scale: \(videoSize)")
            return videoSize
        }catch{
            return VideoSize(width: DEFAULT_VIDEO_WIDTH, height: DEFAULT_VIDEO_HEIGHT)
        }
    }
    
    private static func applyScale(videoSize: VideoSize){
        let oldWidth = videoSize.width;
        let oldHeight = videoSize.height;
        let maxPixelCount = DEFAULT_VIDEO_WIDTH * DEFAULT_VIDEO_HEIGHT;
        let newWidth = Int(round((Float(maxPixelCount * oldWidth) / Float(oldHeight)).squareRoot()));
        let newHeight = newWidth * oldHeight / oldWidth;
        videoSize.width = newWidth;
        videoSize.height = newHeight;
    }
}
