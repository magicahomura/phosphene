import AVFoundation
import CoreMedia
import CoreVideo
import ObjectiveC
import QuartzCore

enum Bisect {
    /// Read per-acquire. Toggle the marker and relaunch WallpaperAgent to change modes.
    static var stillOnly: Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/BISECT_STILL")
        return FileManager.default.fileExists(atPath: url.path)
    }

    private static let layerName = "PhospheneStillBisect"

    /// The root owns the layer, so teardown cannot leave a stale layer retained for a
    /// later context with the same SurfaceKey.
    static func layer(in rootLayer: CALayer) -> AVSampleBufferDisplayLayer? {
        rootLayer.sublayers?.first { $0.name == layerName } as? AVSampleBufferDisplayLayer
    }

    static func name(_ layer: AVSampleBufferDisplayLayer) {
        layer.name = layerName
    }
}

/// Decode and enqueue exactly one real image, with no feed loop or live VideoRenderer.
/// Cached BMP samples alone do not reliably become ready in a fresh remote context on
/// the affected macOS build. A decoded IOSurface-backed image is the validated source.
/// Runs only on Lifecycle.queue; nil means acquire must fail rather than advertise a
/// black context as ready.
func bisectDecodeStill(videoURL: URL?, for key: SurfaceKey) -> CMSampleBuffer? {
    guard let videoURL, let sample = decodeFirstImageSampleBuffer(videoURL) else {
        extensionLog("  [bisect] display \(key.displayID): no decoded image; still acquire failed")
        return nil
    }
    return sample
}

/// For a new surface, call bisectDecodeStill before creating its CAContext. Starting
/// the reader before remote context/layer creation is the validated initialization
/// order; loading a track alone did not make cached image samples become ready.
@discardableResult
func bisectShowStill(sample: CMSampleBuffer, rootLayer: CALayer, for key: SurfaceKey) -> AVSampleBufferDisplayLayer? {
    guard CMSampleBufferGetNumSamples(sample) > 0, CMSampleBufferDataIsReady(sample),
          let pixelBuffer = CMSampleBufferGetImageBuffer(sample),
          CVPixelBufferGetIOSurface(pixelBuffer) != nil else { return nil }

    let layer: AVSampleBufferDisplayLayer
    let isNewLayer: Bool
    if let existing = Bisect.layer(in: rootLayer) {
        layer = existing
        isNewLayer = false
    } else {
        layer = AVSampleBufferDisplayLayer()
        Bisect.name(layer)
        layer.videoGravity = .resizeAspectFill
        layer.isOpaque = true
        bisectSetDisallowsVideoLayerDisplayCompositing(layer, true)
        isNewLayer = true
    }

    bisectSetDisplayImmediately(sample)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.frame = rootLayer.bounds
    layer.contentsScale = rootLayer.contentsScale
    if isNewLayer {
        rootLayer.addSublayer(layer)
    }
    layer.sampleBufferRenderer.enqueue(sample)
    CATransaction.commit()
    CATransaction.flush()
    extensionLog("  [bisect] display \(key.displayID): enqueued real image source=decodedNV12 samples=\(CMSampleBufferGetNumSamples(sample)) pixels=\(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer)) IOSurface=\(CVPixelBufferGetIOSurface(pixelBuffer) != nil)")
    return layer
}

/// Keep the same layer settings as the normal VideoRenderer. This flag and a CA flush
/// alone did not fix the old cached-BMP probe; readiness is checked independently.
private func bisectSetDisallowsVideoLayerDisplayCompositing(_ layer: CALayer, _ flag: Bool) {
    let sel = NSSelectorFromString("_setDisallowsVideoLayerDisplayCompositing:")
    guard layer.responds(to: sel),
          let imp = class_getMethodImplementation(type(of: layer), sel) else { return }
    typealias SetBoolFn = @convention(c) (AnyObject, Selector, ObjCBool) -> Void
    unsafeBitCast(imp, to: SetBoolFn.self)(layer, sel, ObjCBool(flag))
}

/// outputSettings:nil yields compressed packets and may begin with a zero-sample
/// timing marker. Request decoded NV12 and accept only a real IOSurface-backed image.
/// The returned sample retains its image after the one-shot reader is cancelled.
private func decodeFirstImageSampleBuffer(_ url: URL) -> CMSampleBuffer? {
    let asset = AVURLAsset(url: url)
    let sem = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var track: AVAssetTrack?
    asset.loadTracks(withMediaType: .video) { tracks, _ in
        track = tracks?.first
        sem.signal()
    }
    guard sem.wait(timeout: .now() + 10) == .success,
          let track, let reader = try? AVAssetReader(asset: asset) else {
        extensionLog("  [bisect] could not load video track for one-shot decode")
        return nil
    }
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
    ])
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else { return nil }
    reader.add(output)
    guard reader.startReading() else {
        extensionLog("  [bisect] one-shot reader failed: \(String(describing: reader.error))")
        return nil
    }
    defer { reader.cancelReading() }
    while let sample = output.copyNextSampleBuffer() {
        guard CMSampleBufferGetNumSamples(sample) > 0,
              CMSampleBufferDataIsReady(sample),
              let image = CMSampleBufferGetImageBuffer(sample),
              CVPixelBufferGetIOSurface(image) != nil else { continue }
        return sample
    }
    extensionLog("  [bisect] reader ended without a real IOSurface image: status=\(reader.status.rawValue) error=\(String(describing: reader.error))")
    return nil
}

private func bisectSetDisplayImmediately(_ sample: CMSampleBuffer) {
    guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) else { return }
    for i in 0 ..< CFArrayGetCount(attachments) {
        let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, i), to: CFMutableDictionary.self)
        CFDictionarySetValue(
            dict,
            Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
            Unmanaged.passUnretained(kCFBooleanTrue).toOpaque(),
        )
    }
}
