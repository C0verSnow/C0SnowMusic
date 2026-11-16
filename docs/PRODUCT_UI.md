# c0vermusic product interface

This change implements [Issue #13](https://github.com/C0verSnow/C0SnowMusic/issues/13), including its eight comments and seven Apple Music reference screenshots. The app's display name is **c0vermusic**; the Xcode target, bundle identifier, Keychain services, and on-disk library locations retain their existing identifiers so an update keeps the user's music and account.

## Navigation and behavior

- Home uses native inline-large titles, an account avatar, a full-width featured discovery card, artwork shelves, and the system mini player. Pull to refresh recommendations. A background recommendation, metadata, or warehouse failure does not add a red diagnostic banner or block cached playback.
- The four tabs are Home, Radio, Library, and Search, matching the source app navigation. Radio opens real YouTube radio playlists rather than Apple live stations. Genre lists omit missing and Uncategorized values.
- Library has one set of Playlists, Artists, Albums, Songs, Genres, Recently Played, and Favorite Songs destinations. YouTube playlists, albums, library artists and subscriptions appear directly in those destinations alongside imported music. Songs include saved YouTube songs, likes, warehouse favorites, and audio already downloaded on this device. Recently Played includes local playback and this device's online listening history. Favorite Songs includes local favorites and connected-account favorites.
- Signing in loads these categories automatically. Pull to refresh Library to retry. Each category retains its previous contents if a request fails; collection pagination must finish before replacing that category. YouTube likes still synchronize a complete snapshot to connected storage. Genres come from actual imported metadata; YouTube does not provide a genre field in these library responses.
- Search shows **c0vermusic** and **Library** scopes after focus, one top search field, browse-category tiles, horizontal result filters, artwork, subtitles, and trailing action menus. c0vermusic uses YouTube Music; connected warehouse matches are included without a separate storage search screen. Category tiles submit real searches, not invented playlists or charts. Library searches the imported library and loaded account collections. Artist artwork is circular.
- Lyrics has one bottom-right **Lyrics Settings** button. Find Lyrics and Artwork, Import LRC, Lyrics Timing, and Close Lyrics live in that menu. The sheet also supports swipe dismissal. Synchronized scrolling, line seeking, timing offsets, and plain lyrics remain available.
- App-owned text is English regardless of device language or a saved `appLanguage` preference. Original song titles, artists, lyrics, filenames, and provider metadata keep their original language. Only the three placeholders written by older builds are translated on library/cache loading; song and group IDs remain intact.
- Necessary failures from direct user actions use plain-language messages and retry paths. Search and collection requests use quiet placeholder rows. A requested audio download shows Preparing and Cancel on its row. Import progress remains visible while importing files.

Apple Music screenshots inform spacing, navigation, search scopes, and control placement. c0vermusic uses its own SwiftUI implementation, SF Symbols, neutral artwork placeholders, and gradient category tiles. It does not bundle Apple screenshots, catalog artwork, paid account services, or Apple live radio. Library categories can be shown, hidden, and reordered; the native creation sheet supports a playlist name and artwork.

Same-device comparison and current acceptance status are tracked in [DEVICE_UI_COMPARISON.md](DEVICE_UI_COMPARISON.md).

## Missing artwork recovery

An old cache sidecar could retain an artwork ID whose image was missing, or a track could have no thumbnail URL. Previously, a non-nil ID skipped recovery and missing URL recovery depended on an exact lyrics/album match. Playback now checks the saved image file, preserves usable embedded artwork, and tries the source thumbnail followed by the video's public thumbnail. This runs independently of LRCLIB matching. Successful artwork is persisted beside the cache metadata for reopening. Lyrics and original audio bytes stay intact. If the image sources are unreachable, a neutral music-note tile remains visible and playback continues.

The physical-device check also found a saved local song with no cover. Playing such a song now tries the matching YouTube song and artist before an exact album lookup, persists the cover through the existing library transaction, and refreshes player/system artwork without rewriting the audio.

## GitHub research and implementation choices

Checked on 2026-11-16 with GitHub repository search, source reads, license metadata, commit activity, and issue replies:

| Reference | Evidence and comparison | Choice |
| --- | --- | --- |
| [sigma67/ytmusicapi](https://github.com/sigma67/ytmusicapi) | MIT; 3,119 stars; pushed 2026-11-12. Its [library implementation](https://github.com/sigma67/ytmusicapi/blob/master/ytmusicapi/mixins/library.py) distinguishes saved songs, artist subscriptions, track artists, grids, and grid continuations. The maintainer [answered the OAuth issue](https://github.com/sigma67/ytmusicapi/issues/1030#issuecomment-6818691556); private API/authentication changes remain a known limitation. Python/HTTP dependencies would duplicate the app's native client. | Independently extend the existing Swift parser and URLSession pagination. No new dependency. |
| [MetrolistGroup/Metrolist](https://github.com/MetrolistGroup/Metrolist) | User-named business reference; GPL-3.0; approximately 14.5k stars; pushed 2026-11-16. Kotlin/InnerTube and its account-library model differ from SwiftUI/SwiftData. Prior issue-response checks are documented in [the protocol research](TELEGRAM_MUSIC_RESEARCH.md); activity alone is not proof of human support. | Use only as a product/data-responsibility comparison. No GPL source copied. |

The existing SwiftUI/AVFoundation/SwiftData architecture remains. No new UI framework, server, deployment, or account credential is required.

A follow-up GitHub search for SwiftUI Apple Music replicas checked [AppleMusicBottombarSwiftUI](https://github.com/ahmetbostanciklioglu/AppleMusicBottombarSwiftUI) (8 stars, last push 2026-07-02, no declared license returned by GitHub) and [MyPlaylists](https://github.com/aisultanios/MyPlaylists) (25 stars, last push 2024-06-23, no declared license returned). Neither met the repository's active-maintenance and clear-license criteria, so neither was used as an implementation source. The existing same-device Apple Music captures and Apple's public SwiftUI APIs remain the UI references; no additional dependency or copied implementation was introduced.

## Validation

Local verification is limited to source review, property-list linting, and diff checks. No local build, compiler invocation, or test execution is permitted by the repository instructions.

The existing GitHub Actions workflow builds the simulator and unsigned iPhone Release, then runs the actual import/playback, cache, HTTP-boundary, and UI tests. New regressions cover old missing-artwork sidecars with unavailable lyrics service, unchanged audio hashes and restored artwork, library grid/continuation parsing, complete HTTP pagination with duplicate removal, combined song categories, and translation of legacy placeholders without changing song content or IDs. UI tests cover English under a Chinese device preference, unified Library, search categories/scopes, and the single lyrics settings menu through real file/LRC selection.

Remote results and screenshots must be read from the PR's checks and `iOS-test-evidence` artifact before claiming a pass. Build 10 has been signed and installed on the physical device for comparison. Build 12 compiled, passed all 47 unit/integration tests, and resolved build 11's account title and category selection failures. Two UI tests still failed while waiting for system document cells, before subsequently importing successfully. Build 13 narrows that test query and captures immutable UI values in sendable closures; fresh remote and device acceptance is pending. Earlier Issue #11 device evidence is historical.

Apple API references used for native title/focus alignment: [inlineLarge](https://developer.apple.com/documentation/swiftui/toolbartitledisplaymode/inlinelarge) and [searchFocused](https://developer.apple.com/documentation/swiftui/view/searchfocused(_:)).

Toolbar grouping follows Apple's [sharedBackgroundVisibility](https://developer.apple.com/documentation/swiftui/toolbarcontent/sharedbackgroundvisibility(_:)) API: hiding a shared background places the item in its own group. Category reordering retains native [EditMode](https://developer.apple.com/documentation/swiftui/editmode) and `onMove` behavior.
