import QtQuick
import "Singletons"

// the sidebar Profile tab's dossier: the shared ProfileStats.qml (see
// ryoku/shared/quickshell/, symlinked in beside this file as ProfileStats.qml
// so it's inheritable here), with the three overrides this stacked/scrollable
// host needs -- no LOCAL TIME masthead (the sidebar has no clock to spare
// room for, and this host's Flickable has no fixed height to anchor one
// against anyway), the edition footer flowing as the last row instead of
// docked to a fixed-height bottom, and the pill's own hairline/surface tokens
// (`hair`/`sheen`/`tileBg`) in place of the Hub Theme's
// `line`/`lineSoft`/`surfaceLo`, which this Theme doesn't define. everything
// else -- Vitals/Runtime/Packages/Look/Palette, every SysInfo field -- comes
// straight from the base.
ProfileStats {
    id: root

    showMasthead: false
    footerFlows: true
    lineColor: Theme.hair
    lineSoftColor: Theme.sheen
    surfaceLoColor: Theme.tileBg
}
