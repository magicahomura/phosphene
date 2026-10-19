import Foundation
import AVFoundation
import CoreMedia
import QuartzCore

/// Diagnostic: replace the video pipeline with a pure Core-Animation color sweep so the
/// desktop↔lock reveal can be characterized visually. A `CABasicAnimation` runs on the
/// render server (WindowServer) independently of our AVSampleBufferDisplayLayer / control
/// timebase, so its behavior DURING the reveal isolates what the compositor does to our
/// hosted context:
///   • sweep keeps moving smoothly  → the black is video-frame-delivery specific (the
///     AVSBDL has no frame for "now"); the context/compositing itself is fine.
///   • sweep FREEZES mid-travel     → the compositor pauses our layer for the transition.
///   • sweep JUMPS / snaps to start  → a reset (our layer/animation is being re-added).
///   • area goes BLACK               → the surface is being cleared to black, i.e. the
///     problem is the context, not the video — a much deeper issue.
///
/// Toggle by adding/removing `~Documents/COLOR_DIAG` in the extension container and
/// relaunching the Agent (`killall WallpaperAgent`) — no rebuild, mirrors `Bisect`.
enum ColorDiag {
    static var enabled: Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/COLOR_DIAG")
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Displays that already have the sweep installed. Touched ONLY on `Lifecycle.queue`.
    nonisolated(unsafe) static var installed: Set<SurfaceKey> = []
}

/// Install the color-sweep layer onto the display's root layer (idempotent per display).
/// Base fill is solid green; a magenta bar sweeps left→right→left forever. Must run on
/// `Lifecycle.queue`.
func colorDiagInstall(rootLayer: CALayer, for key: SurfaceKey) {
    guard !ColorDiag.installed.contains(key) else { return }
    ColorDiag.installed.insert(key)

    let bounds = rootLayer.bounds

    CATransaction.begin()
    CATransaction.setDisableActions(true)

    // Solid base color so any true-black (surface cleared) is unmistakable against it.
    rootLayer.contents = nil
    rootLayer.backgroundColor = CGColor(red: 0.0, green: 0.55, blue: 0.25, alpha: 1.0) // green

    // Remove any prior sweep (stale renderer/still sublayers too) so only the bar shows.
    rootLayer.sublayers?.forEach { $0.removeFromSuperlayer() }

    let fill = CALayer()
    fill.name = "colorDiag.fill"
    fill.anchorPoint = CGPoint(x: 0.0, y: 0.5) // grow rightward from the left edge
    fill.position = CGPoint(x: 0.0, y: bounds.midY)
    fill.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
    fill.backgroundColor = CGColor(red: 0.9, green: 0.1, blue: 0.6, alpha: 1.0) // magenta
    rootLayer.addSublayer(fill)

    CATransaction.commit()

    // Sweep the bar's width 0 → full → 0, linearly, forever. A steady linear travel makes
    // freezes, jumps, and skips obvious to the eye during the reveal.
    let sweep = CABasicAnimation(keyPath: "bounds.size.width")
    sweep.fromValue = 0.0
    sweep.toValue = bounds.width
    sweep.duration = 2.5
    sweep.autoreverses = true
    sweep.repeatCount = .infinity
    sweep.timingFunction = CAMediaTimingFunction(name: .linear)
    sweep.isRemovedOnCompletion = false
    fill.add(sweep, forKey: "colorDiag.sweep")

    CATransaction.flush()
    extensionLog("  [colorDiag] installed sweep on display \(key.displayID) (\(Int(bounds.width))x\(Int(bounds.height)))")
}

/// Transparent geometry marker layered over the normal video renderer. Unlike
/// `COLOR_DIAG`, this leaves the sample-buffer video path intact. If the marker
/// fills the display while video is scaled into a corner, the fault is inside the
/// video presentation path; if both shrink together, the hosted surface is scaled.
enum ScaleOverlayDiag {
    static var enabled: Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/SCALE_OVERLAY_DIAG")
        return FileManager.default.fileExists(atPath: url.path)
    }

    private static let overlayName = "PhospheneScaleOverlayDiag"

    /// Called on Lifecycle.queue after the ordinary video layer is attached.
    static func install(rootLayer: CALayer, for key: SurfaceKey) {
        guard enabled, rootLayer.sublayers?.contains(where: { $0.name == overlayName }) != true else { return }

        let bounds = rootLayer.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let overlay = CALayer()
        overlay.name = overlayName
        overlay.frame = bounds
        overlay.contentsScale = rootLayer.contentsScale
        overlay.masksToBounds = false
        overlay.zPosition = 10_000
        rootLayer.addSublayer(overlay)

        let inset = max(18, min(bounds.width, bounds.height) * 0.035)
        let border = CALayer()
        border.frame = bounds.insetBy(dx: inset, dy: inset)
        border.borderWidth = max(5, min(bounds.width, bounds.height) * 0.009)
        border.borderColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        border.cornerRadius = 8
        border.zPosition = 1
        overlay.addSublayer(border)

        let center = CALayer()
        center.frame = CGRect(x: bounds.midX - 2, y: 0, width: 4, height: bounds.height)
        center.backgroundColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.9)
        center.zPosition = 1
        overlay.addSublayer(center)

        let midline = CALayer()
        midline.frame = CGRect(x: 0, y: bounds.midY - 2, width: bounds.width, height: 4)
        midline.backgroundColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.9)
        midline.zPosition = 1
        overlay.addSublayer(midline)

        let markerSize = max(34, min(bounds.width, bounds.height) * 0.055)
        let markers: [(CGRect, CGColor, String)] = [
            (CGRect(x: inset, y: bounds.height - inset - markerSize, width: markerSize, height: markerSize), CGColor(red: 1, green: 0.1, blue: 0.1, alpha: 1), "TL"),
            (CGRect(x: bounds.width - inset - markerSize, y: bounds.height - inset - markerSize, width: markerSize, height: markerSize), CGColor(red: 0.1, green: 1, blue: 0.1, alpha: 1), "TR"),
            (CGRect(x: inset, y: inset, width: markerSize, height: markerSize), CGColor(red: 0.1, green: 0.5, blue: 1, alpha: 1), "BL"),
            (CGRect(x: bounds.width - inset - markerSize, y: inset, width: markerSize, height: markerSize), CGColor(red: 1, green: 0.8, blue: 0.1, alpha: 1), "BR"),
        ]
        for (frame, color, label) in markers {
            let marker = CALayer()
            marker.frame = frame
            marker.backgroundColor = color
            marker.borderColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
            marker.borderWidth = 2
            marker.zPosition = 2
            overlay.addSublayer(marker)

            let text = CATextLayer()
            text.string = label
            text.alignmentMode = .center
            text.foregroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
            text.fontSize = max(16, markerSize * 0.42)
            text.contentsScale = rootLayer.contentsScale
            text.frame = marker.bounds
            text.zPosition = 3
            marker.addSublayer(text)
        }

        CATransaction.commit()
        CATransaction.flush()
        extensionLog("  [scaleDiag] overlay installed display=\(key.displayID) bounds=\(bounds) scale=\(rootLayer.contentsScale)")
    }
}

/// Add a frozen half-screen sample-buffer layer beside the live video layer. It
/// uses the same remote CAContext and AVSampleBufferDisplayLayer type, but no
/// reader/feed loop. After a monitor cycle, the user can compare the static patch
/// with the live image to isolate continuous presentation from surface scaling.
enum StillSampleComparisonDiag {
    static var enabled: Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/STILL_SAMPLE_COMPARISON_DIAG")
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func install(rootLayer: CALayer, image: CGImage?, surfaceKey: SurfaceKey, videoName: String) {
        guard enabled else { return }
        guard let image, let sample = makeStillSampleBuffer(from: image) else {
            extensionLog("  [stillCompare] no cached image; comparison not installed")
            return
        }

        let layer = AVSampleBufferDisplayLayer()
        layer.name = "PhospheneStillSampleComparison-\(surfaceKey.surfaceUUID.uuidString.prefix(8))"
        layer.videoGravity = .resizeAspectFill
        layer.isOpaque = true
        layer.frame = CGRect(x: 0, y: 0, width: rootLayer.bounds.width / 2, height: rootLayer.bounds.height)
        layer.contentsScale = rootLayer.contentsScale
        layer.zPosition = 100
        setDisallowsVideoLayerDisplayCompositing(layer, true)

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) {
            for index in 0 ..< CFArrayGetCount(attachments) {
                let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, index), to: CFMutableDictionary.self)
                CFDictionarySetValue(
                    dict,
                    Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                    Unmanaged.passUnretained(kCFBooleanTrue).toOpaque(),
                )
            }
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rootLayer.addSublayer(layer)
        layer.sampleBufferRenderer.enqueue(sample)
        CATransaction.commit()
        CATransaction.flush()
        extensionLog("  [stillCompare] installed surface=\(surfaceKey) video=\(videoName) layer=\(ObjectIdentifier(layer)) frame=\(layer.frame) scale=\(layer.contentsScale) image=\(image.width)x\(image.height)")
        let boxedLayer = SendableBox(value: layer)
        for delay in [0.5, 2.0, 5.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let layer = boxedLayer.value
                let ready: String
                if #available(macOS 14.4, *) {
                    ready = String(layer.isReadyForDisplay)
                } else {
                    ready = "unavailable"
                }
                extensionLog("  [stillCompare] snapshot after=\(delay)s surface=\(surfaceKey) video=\(videoName) layer=\(ObjectIdentifier(layer)) readyForDisplay=\(ready) status=\(layer.sampleBufferRenderer.status.rawValue) frame=\(layer.frame) bounds=\(layer.bounds) scale=\(layer.contentsScale)")
            }
        }
    }
}
