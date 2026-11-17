# Physical-device UI/UX comparison

Scope: [Issue #13](https://github.com/C0verSnow/c0versnowmusic/issues/13), with the user's added requirement to compare Apple Music and c0vermusic on the same physical iPhone, revise differences, and complete acceptance before merging.

## Product boundary

The user confirmed this is a free, open-source product and asked for a recommendation about Apple's paid screens. The implementation follows the same navigation, layout, controls, and interaction patterns while using the existing YouTube account, recommendations, and music settings. It does not introduce paid subscriptions, recharges, gift cards, or nonfunctional purchasing controls. Provider artwork and catalog data naturally differ. The app's brand is c0vermusic.

## Reference capture: 2026-11-16

Apple Music was opened on the user's physical iPhone through iPhone Mirroring. Reference captures use the same 370 x 813 mirroring window for Home, Radio, Library, Library editing, New Playlist, Search browsing, focused Search, results, and Account. Private screenshots stay in the local device-evidence directory rather than the public repository.

Observed source-app states:

- Home displays subscription promotions because this account is not subscribed. These positions use real music discovery content in c0vermusic.
- Radio currently displays Apple's Cannot Connect page. Its successful station screen cannot be accepted from this device state. c0vermusic's Radio uses actual YouTube radio playlists; it does not claim to carry Apple's live stations.
- Library places its large title and avatar on one row, adds a grouped create/edit toolbar, and supports showing, hiding, and moving categories. New Playlist is a sheet with artwork and a centered title field.
- Search starts with a large title, a top search field, and two-column category tiles. The service/library scope appears after search receives focus.
- The idle mini player stays above the tab bar. Account is an inset grouped sheet with an account row and a top-right close button.

## Initial c0vermusic installation

The artifact from run [43892955452](https://github.com/C0verSnow/c0versnowmusic/actions/runs/43892955452) was downloaded, checked against archive SHA-256 `77e4c7f85c4a9ae7ac9ff82fb54b0444ade6d24564b8326885dcf9e717f17e1d`, inspected as version 1.2.0/build 10, signed using the phone's existing certificate, and installed over the existing bundle `org.c0versnow.C0SnowMusic`. Existing songs and the account avatar remain visible. Playback was paused.

The first installed version did **not** satisfy the shared-page 1:1 target:

| Page / interaction | Observed difference | Revision prepared for build 11 |
| --- | --- | --- |
| Main navigation | Large title sat below a separate avatar row; Search was detached from the other tabs. | Native inline-large title; one four-tab group; Home / Radio / Library / Search. |
| Idle player | Hidden when no song was selected. | Persistent Not Playing accessory with disabled unavailable controls. |
| Home | Horizontal shelves only. | Full-width featured discovery card, then real listening/recommendation shelves. |
| Library | Oversized white icons; no create/edit toolbar. | Standard body rows, tinted icons, create playlist, category visibility and ordering. |
| New Playlist | Alert only. | Native sheet with artwork picker, title, cancel, and confirm. |
| Search | Scope picker visible before focus. | Top search field; scope appears when active; same category and row geometry. |
| Account | Conventional navigation list and Done text. | Inset account sheet with close icon and a separate account-connection screen. |
| One of the Girls artwork | The affected song is in the saved local library, not only the temporary online cache. | Playing a saved song with missing artwork searches an exact song/artist source, saves its cover in the library, and refreshes player artwork. |

These revisions require fresh remote compilation, installation, and another same-device comparison. This document does not mark them accepted merely because the source has changed.

## Remote validation so far

Run 43892955452 built the simulator and iPhone Release, packaged the IPA, and passed all 46 unit/integration tests. The English-device-preference and empty-library UI tests also passed. The combined import/player/queue/lyrics UI test exceeded its 120-second per-test limit after a 61-second XCTest element lookup; no functional assertion had failed at that point. The revised suite separates real audio document import, player/queue, and real LRC import while retaining the existing CI time limits. It also verifies Library category editing and playlist creation.

A new local-library artwork regression exercises actual import, SwiftData persistence, image decoding, audio hashing, and playback, replacing only external HTTP responses. It complements the already passing missing-cache-artwork regression.

## Build 11 evidence and build 12 revision

Run [43900939286](https://github.com/C0verSnow/c0versnowmusic/actions/runs/43900939286) built both simulator and unsigned iPhone Release successfully. All 47 unit/integration tests passed, including the saved-song artwork recovery. Four of six UI tests passed. The two failures were the account title and Library category visibility; this was not a compilation failure.

The exported accessibility hierarchy confirms that the account sheet had no visible title text: a toolbar `Label` adopted the icon-only presentation. The exported Library tap event targeted the row center at x=220 points, outside the short plain-button label's content. Build 12 explicitly lays out the account icon and title, removes their shared glass background, and gives category buttons a full-width rectangular hit area. The existing UI tests retain both failing assertions and now also check the category's Shown/Hidden value.

Additional corrections against the saved physical-device references:

- Place Library create/edit controls together, followed by a separate account avatar. Editing shows only the prominent checkmark, matching the reference hierarchy.
- Use 52-point minimum category rows with explicit insets and separator alignment. Hide the empty Recently Added heading.
- Increase the New Playlist artwork-to-title spacing from 42 to 64 points.
- Use the primary foreground tint for active mini-player controls. Keep unavailable idle controls disabled.
- Display search history only while search is active; inactive browsing keeps the category grid first.

The remote UI suite now saves Home, account, inactive Search, focused Search, Library editing, and New Playlist screenshots, in addition to its existing player, queue, import, and lyrics evidence. These are acceptance inputs; successful assertions alone do not establish visual identity.

## Build 12 results and build 13 follow-up

Run [43907719088](https://github.com/C0verSnow/c0versnowmusic/actions/runs/43907719088) compiled simulator and unsigned iPhone Release and passed all 47 unit/integration tests. Account text, Search scopes, Library category selection and playlist creation, and mini/full player UI tests passed. Both build 11 UI failures are resolved in this run.

The remaining failures are at the shared document-selection helper's initial file-existence assertion. In both cases the same query found the real file afterward, and the subsequent audio/LRC import assertions passed. The failure hierarchies show the presenting sheet before its remote file browser had finished appearing; the recorded files became actionable more than 20 seconds after the opening tap. Build 13 separately waits up to 30 seconds for the actual file-browser navigation bar, then uses the existing 15-second wait for the document cell (`Fixture.lrc, lrc` and `Test Tone, wav` in the recorded events). It narrows the broad `descendants(matching: .any)` query to actual cells and stops the helper after a missing-target failure. The real picker interaction, resulting import assertions, and overall per-test limits remain.

Two warnings in the touched UI code are addressed by passing immutable values into the sendable layout/PhotosPicker closures instead of reading main-actor view state inside them. The account screenshot also showed a missing title icon; it now uses the existing bundled AppLogo. No new workflow, dependency, mock picker, or local compilation was introduced.

## Build 13 verified artifacts

Run [43911966701](https://github.com/C0verSnow/c0versnowmusic/actions/runs/43911966701) passed simulator and unsigned iPhone Release compilation, all 47 unit/integration tests, all six UI tests, and the API job for commit `7040ce1a5f6854863f07fabeafa85342631a6251`. The separate validate job was initially cancelled before receiving a runner; GitHub reported macOS arm64 capacity constraints. Its targeted rerun passed. The tag-only Release job was correctly skipped.

Both original artifact archives were downloaded and compared with GitHub's SHA-256 values:

- iPhone archive: `2baed2efa83c86088ffae4fd67827a168e98017ac14c42ca9a7dc8c3953ed09f`.
- Test-evidence archive: `9676109107aedbaedc53a73c0142c1629859f6c44f892481bdd0a5beafefa358`.
- Extracted unsigned IPA: 25,151,102 bytes; SHA-256 `2bbf26cbe7c87dae0294c2365877484709f4fb0af5d1bfb65f86c857ee8f1aa4`; display name c0vermusic; version 1.2.0/build 13; bundle `org.c0versnow.C0SnowMusic`.

The exported Home, account, Search, Library, playlist, player, and lyrics screenshots are available locally for inspection. The account title icon is now present. Simulator screenshots use a different device size and appearance from the physical reference, so they do not establish same-device visual acceptance.

## Build 13 physical comparison and build 14 adjustments

After the user resumed, iPhone Mirroring was already unlocked. The verified IPA was downloaded on the phone under the distinct name `build13.ipa`, imported into the existing signing app, and signed with the existing certificate. The signing log showed BundleVer 13. It was installed over the existing application; both local songs, account avatar, connected playlists, and playback position remained. The temporary download server was stopped afterward.

Fresh Apple Music Home, Library, Search, search results, and Account references and build 13 captures use the same current 368 x 808 mirroring window and dark appearance. They remain outside the public repository in `C0SnowMusic-device/issue-13-comparison/reference-current` and `build13`.

Verified on the physical device:

- Home's title and avatar share a row; the four tabs and persistent mini player are present. The featured card has the reference's overall geometry while using the app's free discovery action.
- Account dismisses; its existing signed-in profile is retained. Search scopes appear after focus, and inactive Search presents the category grid first.
- Library category hiding and restoration work across leaving edit mode. Reordering Artists and Albums works; the original order and visible categories were restored.
- The New Playlist sheet created an empty `UICheck` playlist. The new playlist appeared alongside the existing connected playlists; only this temporary playlist was deleted afterward.
- Playing the previously coverless local One of the Girls restored its The Idol artwork, refreshed the mini/full player, and played successfully. After dismissing its app-switcher card and reopening, the cover, account avatar, selected track, and paused state remained. Playback was paused after the check.
- Radio loaded real provider playlists. Apple's successful live-station screen remains unavailable as a like-for-like service reference.

The comparison still found visible details for build 14 to correct:

- Account and New Playlist close icons inherited the pink accent; use the primary foreground color.
- Account profile row was taller than the source; reduce its added vertical padding from 6 to 2 points.
- Library edit selection circles were too small; use title3 symbols within a 20-point slot.
- Search category tiles were wider and started lower than the reference; explicitly use 20-point row side insets, a 12-point column gap, and remove automatic top content margins while keeping a 12-point row top inset.
- New Playlist artwork started about 10 window pixels too low; reduce its top padding from 30 to 20 points and adjust the artwork-to-title spacing to 70 points.
- The physical system volume slider inherited the pink app accent; explicitly set its UIKit tint to white.

Build 14 contains only these visual corrections. Its final remote checks and physical installation are recorded below. Native navigation-title/search-field leading margins still differ slightly from Apple's private app layout; final visual acceptance must assess the new captures rather than treating build 13's functional checks as pixel identity.

## Build 14 remote file-selection failure

Run [43986526337](https://github.com/C0verSnow/c0versnowmusic/actions/runs/43986526337) compiled simulator and iPhone Release, passed all 47 unit/integration tests, and passed five of six UI scenarios. The LRC scenario found and tapped `Fixture.lrc`, but the system browser remained open and synchronized lyrics never appeared. The separate real-audio document import passed.

The original evidence archive matches SHA-256 `0322ca81199af08c698d5a3429220acbd28458bc4719985de4ce2da2663cfb27`. Its exported hierarchy shows the LRC cell enabled and the WAV cell correctly disabled for the lyrics filter. The recorded tap was `(77.33, 262)` points, inside the LRC icon; subsequent video frames still show the same file browser. This rules out a disabled LRC filter or a successful import whose lyrics merely failed to refresh. The precise system reason for the ignored first selection remains unproven.

The follow-up changes only the UI test. It waits for the real file-browser navigation bar to disappear after selecting a file and, only while that browser remains present, permits one further selection attempt. Failure after both attempts still fails the test. The actual synchronized-lyrics import, line seeking, and current-line assertion remain required, and the 120-second per-test limit is unchanged. A missing lyric now stops that scenario before attempting to tap an absent line. No importer, file filter, product UI, or app build number changes in this follow-up.

The disappearance check uses Apple's public [waitForNonExistence(timeout:)](https://developer.apple.com/documentation/xcuiautomation/xcuielement/waitfornonexistence(timeout:)) API. The final remote validation passed; its physical comparison is recorded below.

## Final build 14 remote verification

Run [43990026426](https://github.com/C0verSnow/c0versnowmusic/actions/runs/43990026426), commit `d4dfb2a31ac3779ff704a28c1616ff8005bae19b`, passed simulator and unsigned iPhone Release compilation, all 47 unit/integration tests, all six UI scenarios, and API checks. Static validation also passed; the tag-only Release job was correctly skipped. The real LRC scenario passed in 53.894 seconds with one file selection, confirmed browser dismissal, imported synchronized lyrics, and line seeking. The second selection attempt was not needed in this run.

The final downloaded IPA archive matches GitHub SHA-256 `4aa808addfc78160970a168d57c1bab9fce325dfc5ed119b4413158194344454`. The extracted IPA is 25,154,715 bytes, version 1.2.0/build 14, bundle `org.c0versnow.C0SnowMusic`, SHA-256 `52206a6123ccf4a138714da451c5e8774ae4f9cb1663ee72893c8cd639afdf4a`. It is prepared locally as `C0SnowMusic-device/issue-13-build14/build14.ipa` for an unambiguous phone download.

The resumed mirror required a fresh Mac login. The user supplied it through the secure input card; that input was used only for the current unlock and its temporary file was deleted. No previous password was read. After reconnecting, the verified `build14.ipa` was downloaded to the phone, imported into its existing signing app, and signed with the existing certificate. Both the signing configuration and log confirmed build 14 before the installation prompt was accepted. The temporary download server was stopped.

## Build 14 physical comparison and build 15 follow-up

Fresh light-appearance Apple Music references and build 14 captures use the same physical iPhone and 368 x 808 mirror window. Private captures remain outside the repository under `C0SnowMusic-device/issue-13-comparison/reference-light` and `build14`.

- Account's primary-color close button and shorter profile row now match the reference geometry. Dismissal works and the original signed-in avatar remains.
- Library's edit circles have the intended larger size. The original local songs remain visible, including the recovered One of the Girls artwork. Editing can be entered and exited.
- New Playlist's artwork now starts at y=162 window pixels, matching the current Apple reference. Its close button is black in light appearance and cancellation works. Its overall sheet was still gray while Apple's was white.
- Search's category side edges and column gap now match the reference: x=26 and x=189, with the right edge at x=342. The first row still started at y=187 rather than Apple's y=177. The explicit 12-point top row inset added this remaining gap; build 15 removes it.
- The full player shows the recovered cover and white native volume slider. Playback remains paused. The app was returned to Home, with the original account, selected track, and artwork retained.

Build 15 changes only the search category row's top inset from 12 to 0 and the New Playlist background from grouped system background to ordinary system background, plus its build number. Semantic system colors preserve appearance adaptation. No search behavior, account data, playlist storage, importer, or UI test is changed. Source review, plist linting, and whitespace checks pass. Final build 15 remote and physical verification is recorded below.

Native navigation-title and search-field leading edges still differ by about four window pixels from Apple's private layout. The reference service content and Apple-only destinations also differ. At this comparison stage the PR remained draft; the later acceptance decision is recorded below.

## Build 15 remote and physical verification

Run [43994398915](https://github.com/C0verSnow/c0versnowmusic/actions/runs/43994398915), commit `4a6ca9568cb6d580aaec4d6a83478259e23ff69e`, passed simulator and unsigned iPhone Release compilation, all 47 unit/integration tests, all six UI scenarios, and API checks. [Static validation](https://github.com/C0verSnow/c0versnowmusic/actions/runs/43994398748) also passed. The tag-only Release job was correctly skipped. Real LRC import and line seeking passed in 59.336 seconds; real audio document import passed in 93.057 seconds. The result bundle includes a non-fatal UIKit toolbar-hosting diagnostic; both complete test suites report zero failures. No product change is inferred from that diagnostic alone.

Both original archives match GitHub's SHA-256 values:

- IPA archive: `da6da71e17deac6f19eabb36501ac4cedef820673e7b911f1084fccaa3f93db2`.
- Test-evidence archive: `c0bf5512576f929820283a587c82095698b6efbdc05a6473a37ebd12d8e609df`.
- Extracted IPA: 25,154,591 bytes; SHA-256 `0e8483ec9d24e4b193f4ebc2790de24ff4e514dd6eb59384337c9f557450ed78`; c0vermusic 1.2.0/build 15; original bundle `org.c0versnow.C0SnowMusic`.

The phone downloaded the uniquely named `build15.ipa`; the temporary download service was stopped after completion. The existing certificate was reused, the signing configuration and log both confirmed build 15, and the native installation prompt was accepted. No new credential or Mac unlock was required in this round.

On the same physical iPhone in light appearance and the same 368 x 808 window:

- Search's first tile row now begins at approximately y=176, compared with Apple's y=177; the former roughly 10-pixel extra gap is gone. Category columns retain the matched x=26 and x=189 edges.
- New Playlist has a white sheet background, with artwork still beginning at y=162 and primary-color cancellation. Opening and cancelling the sheet works.
- Account preserves the original avatar and profile, and its close button works. Search exposes scopes on focus; switching to Library and searching `Girls` returns the saved One of the Girls with its recovered cover. Search was dismissed afterward.
- The original local songs, connected account, selected track, and recovered mini-player artwork remain. Playback is paused and the app was returned to Home.

Private evidence remains outside the public repository in `C0SnowMusic-device/issue-13-comparison/build15` and `reference-light`. The two build 15 fixes are physically verified. Native title/search-field leading edges retain the previously recorded roughly four-pixel difference. Apple's Radio success state and subscription-only services remain unavailable or outside the agreed free-product scope. At the end of this comparison, global pixel identity remained unclaimed and the PR stayed draft. The subsequent user decision below resolves the remaining native-navigation acceptance question.

Public API checks for the remaining navigation detail covered Apple's [toolbarTitleDisplayMode](https://developer.apple.com/documentation/swiftui/view/toolbartitledisplaymode(_:)), [directionalLayoutMargins](https://developer.apple.com/documentation/uikit/uiview/directionallayoutmargins), and [UISearchBar](https://developer.apple.com/documentation/uikit/uisearchbar). UIKit margin documentation describes layout cues rather than guaranteeing the exact layout of SwiftUI's managed navigation/search hierarchy. No private-view traversal or replacement navigation implementation was introduced merely from that inference.

## Accepted scope and closeout decision

The user selected **保留原生导航并收尾** (retain native navigation and finish this round). The approximately four-window-pixel title/search-field leading-margin difference is accepted. The existing native navigation, search focus, scrolling, and back behavior remain; no custom navigation replacement is required for this round.

The same-device build 15 comparison and the preceding category/playlist/player/artwork checks satisfy the agreed UI scope with that accepted difference. The free-provider content boundary and the unavailable Apple Radio success reference remain documented limitations, rather than new work for this closeout. This decision does not claim global pixel identity or completion of unrelated business, hardware, format, or accessibility work.

The remaining closeout steps are the final documentation commit's existing remote checks, merging PR #14, confirming Issue #13 closes, and synchronizing local main. No further application code, build-number change, or device installation is needed for this documentation-only closeout.

No local compilation, build, or test invocation has been performed.


## Current follow-up awaiting physical-device acceptance

The user corrected the product name to **c0versnow music** and requested Apple's stacked Library icon plus the app logo in generic missing-artwork/player positions. These changes, including the final Account title correction, belong to build 17 and PR #16. This document's earlier c0vermusic names and build 13–15 acceptance records describe those historical builds; they do not certify build 17. The current PR must remain unmerged until fresh physical-device testing passes.


Build 17 simulator screenshots and the complete CI suite are now verified. The corrected Account title is fully visible; Library uses the stacked music symbol and missing artwork uses the existing AppLogo. This only establishes the current simulator result. Fresh installation and comparison on the original physical iPhone remain pending; PR #16 is unmerged.
