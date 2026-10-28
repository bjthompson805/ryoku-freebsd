import QtQuick as QQ

// Overrides every bare `TapHandler { ... }` in whatever directory this file is
// symlinked into. A same-name type from an implicit same-directory import
// does NOT win over an explicit `import QtQuick` (confirmed live: it silently
// stays on the built-in). It only wins once the directory is ALSO imported
// explicitly -- add `import "."` after `import QtQuick` in every consumer
// file that uses TapHandler (verified live too: gesturePolicy read back as
// ReleaseWithinBounds only once that import was added).
//
// TapHandler's own default gesturePolicy (DragThreshold) only takes a passive
// grab, which by Qt's own design doesn't stop the same press from also
// reaching a handler on whatever is positioned underneath it (QTBUG-87815) --
// e.g. a stepper button behind a popup, or a real button behind a modal's
// backdrop close-catcher. ReleaseWithinBounds takes an exclusive grab instead,
// so a tap can't leak through to a handler underneath. A consumer that needs
// the passive-grab behaviour can still set gesturePolicy explicitly to override
// this default.
QQ.TapHandler {
    gesturePolicy: QQ.TapHandler.ReleaseWithinBounds
}
