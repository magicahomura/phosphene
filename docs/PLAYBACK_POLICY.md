# Desktop playback policy

The manager's **Keep Playing When Covered** preference opts the extension out of
window-coverage and fullscreen-app pauses. It is stored as
`keepPlayingWhenCovered` in the shared preferences file and delivered to the
extension through the existing `glass.kagerou.phosphene.prefsChanged` Darwin
notification. Older preference files omit the key and decode it as `false`.

The setting does not override manual global or per-display pause, WallpaperAgent
suspension, display sleep, lock-screen-only mode, a foreign screen saver, Game
Mode, critical battery, near-zero display brightness, or thermal protection.
Those states retain their existing policy priority.

The manager recomputes per-display coverage on screen-parameter changes as well
as its existing app/Space notifications and low-frequency poll. The extension
logs a pause or resume reason for a surface only when that reason changes.

Source-level policy and reducer tests cover old preference files, both automatic
coverage pause paths, manual/system protection priority, and per-display
isolation. Installed dual-monitor and manager-reopen checks remain part of the
local integration acceptance.
