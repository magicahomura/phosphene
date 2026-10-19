import CoreGraphics
import QuartzCore

/// Detailed layer-tree snapshots are opt-in through VERBOSE_LOG. They deliberately
/// omit wallpaper filenames and user paths while preserving acquire/context identity.
func traceSurfaceGeometry(
    _ phase: String,
    acquireID: String,
    key: SurfaceKey,
    contextID: UInt32,
    logicalSize: CGSize,
    scaleFactor: CGFloat,
    rootLayer: CALayer,
    videoLayer: CALayer? = nil,
    rendererID: Int? = nil,
    cachedStill: CGImage? = nil,
) {
    guard verboseLoggingEnabled else { return }

    let renderPixels = CGSize(width: logicalSize.width * scaleFactor, height: logicalSize.height * scaleFactor)
    let cachedPixels = cachedStill.map { "\($0.width)x\($0.height)" } ?? "none"
    let renderer = rendererID.map(String.init) ?? "none"
    traceLog("[Geometry] acquire=\(acquireID) phase=\(phase) \(key) ctx=\(contextID) renderer=\(renderer) requestedPoints=\(logicalSize) requestedPixels=\(renderPixels) scale=\(scaleFactor) cachedStillPixels=\(cachedPixels) root{\(layerGeometry(rootLayer))} video{\(videoLayer.map(layerGeometry) ?? "none")}")
}

private func layerGeometry(_ layer: CALayer) -> String {
    "frame=\(layer.frame) bounds=\(layer.bounds) position=\(layer.position) anchor=\(layer.anchorPoint) contentsScale=\(layer.contentsScale) transform=\(layer.transform)"
}
