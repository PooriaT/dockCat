# Overlay accessibility

DockCat cards expose separate semantic regions in this order: source, presentation behavior,
title, message, queue/delivery status, Open, and Dismiss. The title is a heading; the message
is independent static or scrollable text; queue state is status, not an action. The paw is
decorative and hidden. Stable `dockcat.card.*` identifiers never contain content, UUIDs, URLs,
bundle identifiers, or presentation generations.

## Announcements and privacy

After presentation completion passes session and content-revision validation, DockCat announces
arrival with source, persistent/transient behavior, and a nonzero waiting count. It never
automatically speaks title, body, queued contents, or action URL. An accepted external revision
says only “DockCat notification updated.” Queue-count-only changes are silent. Duplicate
session/revision announcements are suppressed; pending delivery is cancelled by replacement,
global disable, recovery, and shutdown. Announcements do not make the panel key or move focus.

Labels never recover hidden previews and expose only already-visible copy. Diagnostics contain
only category, generation, suppression reason, element count, appearance category, and focus
identifier.

## Interaction and keyboard

Cards begin passive and non-key, intercepting no keys. A deliberate pointer or VoiceOver
“Interact with notification” action validates the presentation session, enters interactive mode,
and applies the existing safe focus-restoration token. Local keyboard order is Open, Dismiss,
then the message only when it overflows and supports scrolling. Shift-Tab reverses the order.
Return and Space use native button activation; focused overflowing text uses standard scroll-view
arrow and page-key behavior. Escape requires a key, interactive, dismissible card.

Queue metadata refreshes preserve focus. Same-session external revisions reuse the hosting view
and retain a logical control target; a new queued notification begins passive. Open leaves focus
with the opened application. Other exits restore the prior running application only when the
generation remains current and no third application became frontmost.

## Display options and motion

One workspace display-options observer publishes a coherent snapshot of Reduce Motion, Increase
Contrast, Reduce Transparency, and Differentiate Without Color, with activation refresh and no
polling. Reduce Transparency swaps material blur for an opaque semantic window background.
Increase Contrast strengthens the semantic separator border and native focus treatment. Status
always has text plus a symbol, including persistent, automatic-close, queued, and paused states.

Appearance-only updates replace neither session nor hosting view, begin no visual operation, and
restart no transient timer. Reduced Motion remains distinct from Disable Walking and Pause Visual
Animations: it removes continuous travel and large card travel/zoom, but delivery and the wake →
pickup → handoff → presentation → waiting → dismissal → return → settlement semantic order are
unchanged. Timers begin only after accepted card presentation.

## Known limitations

- DockCat provides no custom VoiceOver rotors or arbitrary native notification actions.
- Keyboard scrolling uses standard SwiftUI `ScrollView` behavior rather than a custom text view.
- Spoken copy is English; the semantic-copy boundary is centralized for future localization.
- VoiceOver behavior requires hands-on validation for each supported macOS update.
