import CoreGraphics
import QuartzCore
import ObjectiveC

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

/// Read the private CAContext association metadata on the actual context that
/// WallpaperAgent receives. This is diagnostic only: selectors are checked
/// before KVC access, and the options dictionary is reduced to scalar values.
/// The independent CLI process cannot tell us what WallpaperExtensionKit's
/// hosted context carries after remoteContextWithOptions:.
func traceContextAssociation(_ context: AnyObject, phase: String, contextID: UInt32) {
    guard verboseLoggingEnabled else { return }
    let object = context as? NSObject
    let probes = ["displayId", "displayNumber", "displayMask", "options"]
    var values: [String] = []
    for key in probes {
        let selector = NSSelectorFromString(key)
        guard object?.responds(to: selector) == true else {
            values.append("\(key)=<unavailable>")
            continue
        }
        guard let value = object?.value(forKey: key) else {
            values.append("\(key)=nil")
            continue
        }
        if key == "options", let dictionary = value as? NSDictionary {
            let entries = dictionary.allKeys
                .compactMap { $0 as? String }
                .sorted()
                .map { optionKey -> String in
                    let optionValue = dictionary[optionKey]
                    if let number = optionValue as? NSNumber {
                        return "\(optionKey):\(number)"
                    }
                    if let string = optionValue as? String {
                        return "\(optionKey):\(string)"
                    }
                    return "\(optionKey):<\(type(of: optionValue as Any))>"
                }
            values.append("options={\(entries.joined(separator: ","))}")
        } else {
            values.append("\(key)=\(value)")
        }
    }
    traceLog("[CAContext] phase=\(phase) ctx=\(contextID) class=\(type(of: context)) \(values.joined(separator: " "))")
}

private func layerGeometry(_ layer: CALayer) -> String {
    "frame=\(layer.frame) bounds=\(layer.bounds) position=\(layer.position) anchor=\(layer.anchorPoint) contentsScale=\(layer.contentsScale) transform=\(layer.transform)"
}
