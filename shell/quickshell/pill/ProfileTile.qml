import QtQuick
import "Singletons"

// the sidebar Profile tab's specimen tile: the shared ProfileCard.qml (see
// ryoku/shared/quickshell/, symlinked in beside this file as ProfileCard.qml
// so it's inheritable here), with the two overrides this static host needs --
// no cursor tilt/foil sheen (a sidebar tab isn't a hover surface), and the
// pill's own hairline tokens (`hair`/`sheen`) in place of the Hub Theme's
// `line`/`lineSoft`, which this Theme doesn't define. everything else --
// layout, SysInfo fields, wave meters, the percentage-annotated MEMORY/DISK
// readouts -- comes straight from the base.
ProfileCard {
    id: root

    interactiveHover: false
    lineColor: Theme.hair
    lineSoftColor: Theme.sheen
}
