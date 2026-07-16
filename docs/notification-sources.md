# Notification sources

All inputs use a typed `NotificationSourceEvent`: existing developer and URL inputs remain normal `DockCatNotification` events, while the experimental Accessibility observer emits neutral snapshots. The Accessibility path parses, excludes, fingerprints, deduplicates, converts, and then uses the same bounded card queue. Direct developer and URL notifications do not pass through AX deduplication.

A source must validate at its trust boundary, avoid blocking the main actor, and submit only model values. No source may invoke presentation or animation directly.

## Experimental System Notifications onboarding

The disabled-by-default observer uses only public Accessibility APIs. It resolves `com.apple.notificationcenterui` (plus a small legacy identifier/name fallback), listens for that process launching or terminating, and reattaches after PID replacement. It independently attempts created, children/layout/value changed, window-created, and destroyed callbacks because availability varies by macOS release. Partial registration is degraded; no useful registration is unavailable.

Callbacks snapshot the changed element's immediate container rather than the desktop. Bursts are coalesced for 40 ms. Traversal defaults to depth 6, 80 nodes, 512 characters per string, and 8,192 total text characters; cycles and repeated elements are stopped. Snapshot data has no AX references, screenshots, or OCR.

## Normalization and deduplication

The source passes through the bounded identifier of the AX element that triggered a callback. The pure parser uses that identifier to select its containing banner/alert before reading any fields, so sibling notifications cannot be combined. If a parent contains multiple notification subtrees and none can be identified unambiguously, parsing fails closed. Within the selected subtree, structural identifiers, roles/subroles, hierarchy, and process metadata take priority over labels. Identifiers locate visible source, title, body, and action metadata; localized button labels are not required signals. Notification/banner/alert structure is required, so widgets, unrelated controls, and empty unknown containers are rejected. Fields are whitespace-normalized and bounded again to 512 characters. Missing and visibly empty fields remain distinct, and title and body are independently optional.

A structurally identified redacted notification may display the literal privacy-safe fallback “Preview hidden”; it never reconstructs hidden title/body text. A redacted-looking unrelated container is rejected. Actions remain inert descriptors and never become URLs.

Fingerprints use SHA-256 over length-delimited bundle/structural identity, an opaque source token when present, a coarse hierarchy signature, and separate SHA-256 digests of visible fields. Capture sequence and precise time are excluded. Thus repeated callbacks normally match while different bodies normally differ, and the cache retains only the final digest and safe observation metadata. Structural churn can still false-split an item; identical visible notifications without stable identifiers can false-merge. Those tradeoffs avoid retaining raw text.

The actor-isolated cache defaults to 15 seconds and 256 entries. It removes expired records opportunistically and then evicts the oldest observation (with insertion order as a deterministic tie-break) until within capacity. It creates no per-entry tasks and supports explicit removal for later lifecycle work. A full presentation queue rolls back the cache reservation so another callback may retry.

The Notification Center process bundle identifies the observer host, not the app that posted a banner, and is therefore never used as the candidate source. A source bundle is accepted only from bundle metadata inside the selected notification subtree; otherwise it remains absent. DockCat's exact derived bundle identifier and known overlay/simulator/URL structural identifiers are excluded. Display name alone is never an exclusion signal. Destroyed observations are rejected before deduplication or queueing. Full appeared/updated/disappeared reconciliation, native dismissal, and persistent presentation policy remain deferred to issue #70.

The health model reports `disabled`, `permissionRequired`, `starting`, `active`, `degraded`, or `unavailable`. `active` requires every attempted structural registration through the preferred bundle identifier; fallback resolution or partial registration is degraded. Permission loss removes registrations and the run-loop source.
