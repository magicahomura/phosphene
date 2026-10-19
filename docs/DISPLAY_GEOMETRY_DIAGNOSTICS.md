# Display reconnect geometry diagnostics

With `VERBOSE_LOG` present at extension launch, each acquire gets a short
correlation ID. Geometry entries record that ID, display/surface key, remote
context ID, renderer ID, requested logical size, derived render-pixel size,
scale factor, cached-still pixel size, and the root/video layers' frame, bounds,
position, anchor point, contents scale, and transform. The extension records
snapshots at context creation, renderer creation, first-frame readiness, context
reuse, and agent updates. Wallpaper names and file paths are omitted from these
geometry records.

The 2026-10-19 trace provides these inputs around the reported recovery:

| Phase | Destination | Scale | Requested render pixels |
| --- | --- | ---: | ---: |
| Normal | 2048 × 1152 | 2× | 4096 × 2304 |
| Temporary display | 1920 × 1080 | 1× | 1920 × 1080 |
| Main display restored | 2048 × 1152 | 2× | 4096 × 2304 |

The restored request used a new remote context and renderer. The current source
sets the root layer to the requested point size and scale, then sizes the video
layer to the root bounds. Existing logs do not include the actual hosted layer
geometry, so they cannot locate the first divergence or prove a fixed-scale or
cache cause. The new log entries are intended to compare a normal start with one
controlled display-off/on recovery before selecting a geometry change.

Build 2203 adds opt-in metadata from the actual `CAContext` object in the
WallpaperAgent extension process. On its normal reacquire, the main and side
contexts retained `options={displayId:2}` and `options={displayId:3}` respectively,
while the private `displayId`, `displayNumber`, and `displayMask` getters all read
zero. The same getters read zero in an independent, non-hosted context, so these
values alone do not establish a fault. The 2203 install restarted WallpaperAgent;
the earlier dual-off fault is therefore represented by the saved 2202 log, and a
fresh physical reproduction is needed to capture 2203 context metadata during the
fault itself.

Keep verbose logging enabled only for that short reproduction, retain the log
locally, and turn logging off after capture. Do not post the raw log: ordinary
extension log lines can contain local paths and wallpaper identifiers.
