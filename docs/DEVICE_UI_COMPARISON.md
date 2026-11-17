# Physical-device UI/UX comparison

Scope: [Issue #13](https://github.com/C0verSnow/C0SnowMusic/issues/13), with the user's added requirement to compare Apple Music and c0vermusic on the same physical iPhone, revise differences, and complete acceptance before merging.

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

The artifact from run [43892955452](https://github.com/C0verSnow/C0SnowMusic/actions/runs/43892955452) was downloaded, checked against archive SHA-256 `77e4c7f85c4a9ae7ac9ff82fb54b0444ade6d24564b8326885dcf9e717f17e1d`, inspected as version 1.2.0/build 10, signed using the phone's existing certificate, and installed over the existing bundle `org.c0versnow.C0SnowMusic`. Existing songs and the account avatar remain visible. Playback was paused.

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

Run [43900939286](https://github.com/C0verSnow/C0SnowMusic/actions/runs/43900939286) built both simulator and unsigned iPhone Release successfully. All 47 unit/integration tests passed, including the saved-song artwork recovery. Four of six UI tests passed. The two failures were the account title and Library category visibility; this was not a compilation failure.

The exported accessibility hierarchy confirms that the account sheet had no visible title text: a toolbar `Label` adopted the icon-only presentation. The exported Library tap event targeted the row center at x=220 points, outside the short plain-button label's content. Build 12 explicitly lays out the account icon and title, removes their shared glass background, and gives category buttons a full-width rectangular hit area. The existing UI tests retain both failing assertions and now also check the category's Shown/Hidden value.

Additional corrections against the saved physical-device references:

- Place Library create/edit controls together, followed by a separate account avatar. Editing shows only the prominent checkmark, matching the reference hierarchy.
- Use 52-point minimum category rows with explicit insets and separator alignment. Hide the empty Recently Added heading.
- Increase the New Playlist artwork-to-title spacing from 42 to 64 points.
- Use the primary foreground tint for active mini-player controls. Keep unavailable idle controls disabled.
- Display search history only while search is active; inactive browsing keeps the category grid first.

The remote UI suite now saves Home, account, inactive Search, focused Search, Library editing, and New Playlist screenshots, in addition to its existing player, queue, import, and lyrics evidence. These are acceptance inputs; successful assertions alone do not establish visual identity.

## Build 12 results and build 13 follow-up

Run [43907719088](https://github.com/C0verSnow/C0SnowMusic/actions/runs/43907719088) compiled simulator and unsigned iPhone Release and passed all 47 unit/integration tests. Account text, Search scopes, Library category selection and playlist creation, and mini/full player UI tests passed. Both build 11 UI failures are resolved in this run.

The remaining failures are at the shared document-selection helper's initial file-existence assertion. In both cases the same query found the real file afterward, and the subsequent audio/LRC import assertions passed. The failure hierarchies show the presenting sheet before its remote file browser had finished appearing; the recorded files became actionable more than 20 seconds after the opening tap. Build 13 separately waits up to 30 seconds for the actual file-browser navigation bar, then uses the existing 15-second wait for the document cell (`Fixture.lrc, lrc` and `Test Tone, wav` in the recorded events). It narrows the broad `descendants(matching: .any)` query to actual cells and stops the helper after a missing-target failure. The real picker interaction, resulting import assertions, and overall per-test limits remain.

Two warnings in the touched UI code are addressed by passing immutable values into the sendable layout/PhotosPicker closures instead of reading main-actor view state inside them. The account screenshot also showed a missing title icon; it now uses the existing bundled AppLogo. No new workflow, dependency, mock picker, or local compilation was introduced.

## Build 13 verified artifacts

Run [43911966701](https://github.com/C0verSnow/C0SnowMusic/actions/runs/43911966701) passed simulator and unsigned iPhone Release compilation, all 47 unit/integration tests, all six UI tests, and the API job for commit `7040ce1a5f6854863f07fabeafa85342631a6251`. The separate validate job was initially cancelled before receiving a runner; GitHub reported macOS arm64 capacity constraints. Its targeted rerun passed. The tag-only Release job was correctly skipped.

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

Build 14 contains only these visual corrections. Its remote checks and a fresh installation are pending. Native navigation-title/search-field leading margins still differ slightly from Apple's private app layout; final visual acceptance must assess the new captures rather than treating build 13's functional checks as pixel identity.

## Acceptance still required

- Run build 14 remote checks, install the verified new artifact, and recheck the listed visual adjustments in the same appearance, device size, and scroll state.
- Exercise account dismissal, category visibility/order, playlist creation, search focus/filter/results, mini/full player transitions, lyrics settings/import/timing, and saved-song artwork recovery/reopening.
- Record remaining intentional content differences separately from layout or interaction defects. Do not claim global pixel identity while a source page is unavailable or a screen has not been compared.
- Merge and close the issue only after the requested device acceptance.

No local compilation, build, or test invocation has been performed.
