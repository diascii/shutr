# shutr
SHUTR — Complete Project Brief v3
I am building a Flutter/Dart app called Shutr — a peer to peer collaborative photo gallery app. The master's phone acts as the server. Photos never touch any cloud. Zero cloud storage costs.
Core Concept:
A normal photo gallery app where users can "go live" on specific albums, allowing others to join via a generated code or link and view/download photos directly from the master's device peer to peer.
Tech Stack:

Flutter/Dart
P2P technology for photo transfer (WebRTC or similar Flutter package)
Cloudflare Workers free tier for peer discovery (V2 only)
No Firebase
No backend
No cloud storage ever

V1 Plan — Same Network Only:

Works on same WiFi network
No peer discovery server needed
Completely zero cost
Ship this first, test it, then move to V2

V2 Plan — Different Networks:

Add Cloudflare Workers free tier as tiny peer discovery server
Server only passes small messages, never touches photos
Soulseek architecture — server introduces devices then steps aside
Photos still transfer directly phone to phone
Cloudflare free tier = 100,000 requests per day, no card needed

Gallery UI — Most Important:

Must feel native, like Android's default gallery app
Simple 2 column grid of albums
Album thumbnail = just the first photo, no decoration
Album name below thumbnail
Photo count below album name
Dark background, white text
Clean minimal typography
No unnecessary icons, badges, or decorations
No techy or complex UI elements
The ONLY extra UI element = small green pulsing dot on live albums
Users should open Shutr and feel like it's just their normal gallery
Simple is the goal — restraint over complexity

Going Live:

Long press album → context menu appears:

🟢 Go Live
✏️ Rename
🗑️ Delete


Generates a unique 6 character alphanumeric code AND shareable link
Maximum 3 albums live simultaneously
Live albums show a subtle green pulsing dot indicator only

Joining:

Viewer enters code or taps link
Master receives Zoom style notification: "John wants to join Trees — Accept / Decline"
All users join as Viewer role by default always
Master upgrades or downgrades roles anytime

Role System:

👑 Master — full control, goes live, shuts down, manages roles, removes photos, deletes album
📸 Contributor — view, download permanently, add photos
👁️ Viewer — view and download permanently only, cannot add photos
Default role when joining = Viewer always, no exceptions

Master Control Panel inside live album:

List of all connected users
Shows each user's current role
One tap to upgrade Viewer to Contributor
One tap to downgrade Contributor to Viewer
One tap to remove any user entirely

Real Time Sync:

Anyone adds photo → appears instantly for all connected users
Master shutdown → disconnects everyone instantly
All via P2P, no cloud involved

Shutdown System:

Master taps shutdown → options:

⚡ Immediately
⏱️ 5 minutes
⏱️ 15 minutes
⏱️ 30 minutes
🔧 Custom minutes


During countdown viewers see banner: "🔴 Trees closes in 14:32 — download what you want"
Push notification to all viewers when countdown starts
1 minute remaining warning notification
Master can cancel shutdown during countdown
Master can accelerate to immediate anytime during countdown

Photo Limits:

Max 50 photos per contributor per album
Max 10MB per photo
Max 500 photos total per album
Max 3 live albums simultaneously
Counter shown inside album: "247/500 photos · Your contribution: 12/50"
Human friendly limit messages, never cold error messages

Privacy — Key Marketing Point:

Photos never touch any server ever
No cloud storage
No third party has any access
Master has complete physical control over everything
When master's album is offline, it's completely inaccessible to everyone

Future Premium Features — Do Not Build Yet:

Unlimited photo contributions
Larger file sizes per photo
More than 3 simultaneous live albums
Cross network support (V2 with Cloudflare Workers)

# qol suggestion
Bugs / Functional Issues

1. ~~Drag-select can't deselect a range, only add to it~~ → REPLACED: long-press + tap only, drag removed entirely
2. ~~Deleted photos in viewer still visible briefly when returning to grid~~ → FIXED: viewer returns deleted IDs, grid removes them immediately
3. WiFi drop during join = silent kick with a 3-second snackbar, no recovery
4. ~~Grid doesn't update after viewer actions (delete)~~ → FIXED: auto-refresh on album create/delete
5. ~~Pinch-to-zoom threshold feels inconsistent, can jump two columns at once~~ → MOOT: removed with drag-to-select, grid now fixed 3 columns
Missing Features
6. ~~No share functionality (WhatsApp, etc.)~~ → FIXED: share_plus added in photo viewer menu
7. ~~No video support — videos are completely invisible~~ → FIXED: added READ_MEDIA_VIDEO permission, DurationConstraint(allowNullable:true) for null-duration videos, getMediaUrl() for tap-to-play, play button overlay in PhotoViewer with external launch, share/info handle videos
8. No trash / undo for deleted photos — permanent and instant
9. ~~No way to set album cover manually~~ → FIXED: photo viewer menu → "Set as Album Cover", persists
10. Join tab has no recent sessions or history
UI / Visual
11. ~~Back button disappears against bright photos in viewer — no background~~ → FIXED: gradient backdrop overlaid
12. ~~Bottom nav labels too small (10px)~~ → FIXED: increased to 13px
13. ~~Green accent (#4ADE80) feels out of place for a photo gallery~~ → FIXED: replaced with neutral blue-gray (#6B8AFF), green kept only for live pulse indicators (#4CAF50)
14. ~~Skeleton loader missing — just a black screen with a spinner on first load~~ → WONTFIX: load is fast enough, skeleton is overkill
15. ~~Album header image visibly blurry (small thumbnail stretched to 200px)~~ → FIXED
16. No branded splash screen or app icon
UX / Flow
17. ~~Long press → drag immediately selects too aggressively, easy to select 20 photos by accident~~ → FIXED: drag removed
18. ~~Pull-to-refresh gives no feedback on whether anything actually changed~~ → FIXED: shows "X new photos added" or "Up to date"
19. ~~Join tab appears even when not needed, feels empty most of the time~~ → FIXED: vertically centered layout with link icon, friendlier empty state

# fix suggestion
The problem is clear — _GuestAlbumView receives isContributor as a constructor parameter, so it's fixed at the time the screen was opened. When the host changes the role, the WebSocket message updates _roles in SharedGalleryScreen but _GuestAlbumView is already pushed on the nav stack with the old isContributor value and never rebuilds.
The fix is to not pass isContributor as a static parameter — instead let _GuestAlbumView listen to role changes directly via the socket.
The cleanest approach: pass the _roles map as a ValueNotifier so _GuestAlbumView rebuilds when it changes.
In SharedGalleryScreen add:
dartfinal Map<String, ValueNotifier<String>> _roleNotifiers = {};
In _fetchAlbums / where you init roles, create notifiers:
dartif (data['type'] == 'decision') {
  // ... existing code ...
  for (final albumId in _roles.keys) {
    _roleNotifiers[albumId] = ValueNotifier(_roles[albumId] ?? 'viewer');
  }
}

if (data['type'] == 'role_update') {
  setState(() => _roles[data['albumId']] = data['role']);
  _roleNotifiers[data['albumId']]?.value = data['role']; // notify!
  // ... rest of existing code
}
Then pass the notifier to _GuestAlbumView instead of isContributor:
dartNavigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => _GuestAlbumView(
      album: album,
      baseUrl: _baseUrl,
      roleNotifier: _roleNotifiers[albumId] ?? ValueNotifier('viewer'), // change this
      uploadLimit: _limits[albumId] ?? 20,
      uploadCount: _counts[albumId] ?? 0,
      socket: _socket,
      onCountChange: (c) => setState(() => _counts[albumId] = c),
      nickname: widget.nickname,
    ),
  ),
);
Update _GuestAlbumView to use the notifier:
dartclass _GuestAlbumView extends StatefulWidget {
  // replace: final bool isContributor;
  final ValueNotifier<String> roleNotifier; // add this
  // ... rest
}
Then in _GuestAlbumViewState.build(), wrap with ValueListenableBuilder:
dart@override
Widget build(BuildContext context) {
  return ValueListenableBuilder<String>(
    valueListenable: widget.roleNotifier,
    builder: (context, role, _) {
      final isContributor = role == 'contributor';
      return Scaffold(
        appBar: AppBar(
          // ... use isContributor here
          actions: [
            if (!_selectionMode && isContributor)
              IconButton(
                icon: const Icon(Icons.add_photo_alternate_outlined),
                onPressed: _uploadPhoto,
              ),
            // ...
          ],
        ),
        // ... rest of scaffold, pass isContributor where needed
      );
    },
  );
}
Also update _uploadPhoto to read from the notifier:
dartFuture<void> _uploadPhoto() async {
  if (widget.roleNotifier.value != 'contributor') {
    SnackBarHelper.show(context, message: 'Only contributors can upload.', type: SnackBarType.warning);
    return;
  }
  // ... rest
}
Now when the host changes the role, _roleNotifiers[albumId]?.value = data['role'] fires, ValueListenableBuilder rebuilds, and the add button appears instantly without reopening the album. 🎉
# newest logs

# Glimpse App — Deep Research Summary

## Overview
**Glimpse** (`org.lineageos.glimpse`) is the official gallery app for LineageOS 21.0 (Android 14). It's a native Android gallery built with Kotlin, designed to replace AOSP's Gallery2. It is the gold standard for "feels like a native Android gallery" — exactly what Shutr's gallery UI should aspire to.

- **Repo:** `lineage-next/android_packages_apps_Glimpse`
- **Language:** 100% Kotlin
- **Min SDK:** 30 (Android 11)
- **Target SDK:** 34 (Android 14)
- **License:** Apache-2.0
- **Commits:** 203
- **Stars:** 8 (niche, internal LineageOS project)

## Architecture

### Three-Activity Pattern
| Activity | Purpose |
|---|---|
| `MainActivity` | Shell — hosts `NavHostFragment` with bottom nav |
| `ViewActivity` | Full-screen media viewer (ViewPager2 + ExoPlayer) |
| `PickerActivity` | System picker for `ACTION_GET_CONTENT` / `ACTION_PICK` |

### Navigation Structure
```
MainActivity
  └─ MainFragment (bottom nav shell)
       ├─ AlbumsFragment → AlbumViewerFragment (via NavHost child)
       └─ (other tabs via main_fragment_navigation)
```

Uses **Jetpack Navigation Component** with nested `NavHostFragment`. `MainFragment` has its own child nav controller for tab switching.

### Data Layer — MediaStore via Kotlin Flow
```
MediaRepository (object)
  ├─ media() → MediaFlow → Flow<List<MediaStoreMedia>>
  ├─ album() → AlbumFlow → Flow<List<Album>>
  └─ albums() → AlbumsFlow → Flow<List<Album>>
```

**Key insight:** Glimpse does NOT use Room, SQLite, or any custom database. It queries `MediaStore.Files.getContentUri("external")` directly via `ContentResolver.queryFlow()` — a Kotlin Flow wrapper around ContentResolver that emits on data changes. This means:
- **Zero custom storage layer** — all data comes from Android's MediaStore
- **Reactive by default** — Flow emits when MediaStore content changes
- **No caching layer** — relies on MediaStore's own indexing

### ViewModel Layer
| ViewModel | Purpose |
|---|---|
| `AlbumsViewModel` | Emits list of albums (buckets) |
| `AlbumViewerViewModel` | Emits media list WITH date headers interleaved |
| `MediaViewerViewModel` | Emits media list for full-screen viewer |
| `MediaViewerUIViewModel` | UI state only — fullscreen toggle, sheet heights |

**Key pattern:** All ViewModels use `stateIn(viewModelScope, SharingStarted.WhileSubscribed(), initialValue)` — data is only fetched when UI is observing, and stops when UI is gone.

### MediaStore Buckets System
Glimpse uses a clever **fake bucket ID** system to represent virtual albums:
```kotlin
enum class MediaStoreBuckets {
    MEDIA_STORE_BUCKET_FAVORITES,  // IS_FAVORITE = 1
    MEDIA_STORE_BUCKET_TRASH,      // IS_TRASHED = 1
    MEDIA_STORE_BUCKET_REELS,      // ALL media
    MEDIA_STORE_BUCKET_PHOTOS,     // images only
    MEDIA_STORE_BUCKET_VIDEOS,     // videos only
    MEDIA_STORE_BUCKET_PLACEHOLDER // sentinel
}
// Bucket IDs are computed: -0x0000DEAD - ((ordinal + 1) shl 16)
```

Real album buckets come from MediaStore's `BUCKET_ID` column. Fake ones use negative IDs that can never collide with real bucket IDs.

## UI Patterns

### Albums View
- Grid layout (`AlbumThumbnailLayoutManager`) — responsive columns
- Each album card: thumbnail (first photo as Coil-loaded image) + album name + photo count
- Uses `CoordinatorLayout` + `AppBarLayout` with scroll flags (`scroll|enterAlways|snap`)
- Toolbar collapses on scroll, reappears on scroll up

### Album Viewer (Grid of Photos)
- `ThumbnailAdapter` with **two view types**: `THUMBNAIL` and `DATE_HEADER`
- Date headers inserted when photos are ≥1 day apart — creates natural grouping
- Coil loads thumbnails with `memoryCacheKey("thumbnail_${id}")` for cache efficiency
- **Selection mode** uses `recyclerview-selection` library:
  - Long press → enters selection mode
  - Selected items get blur effect (Android 12+) or scrim overlay (older)
  - Action bar appears with: Share, Delete, Move to Trash
- `DisplayAwareGridLayoutManager` — calculates grid size based on screen density

### Full-Screen Media Viewer (`ViewActivity`)
- `ViewPager2` for swipe between photos
- `ExoPlayer` for video playback (lazy-initialized, only created when needed)
- **Top sheet:** back button, date/time text
- **Bottom sheet:** favorite, share, info, edit, delete buttons
- **Fullscreen toggle:** single tap hides/shows both sheets with fade animation
- `offscreenPageLimit = 2` — preloads adjacent pages for smooth swiping
- Video player controls are positioned between top/bottom sheets dynamically

### Media Info Bottom Sheet
- Reads EXIF data via `ExifInterface` from the media URI
- Shows: camera make/model, exposure, aperture, ISO, focal length, artist, software, copyright
- **Geocoding:** extracts GPS coords from EXIF, reverse-geocodes via `Geocoder`, shows address
- Tap location → opens map intent (`geo:?q=lat,long`)
- Editable description field (writes back to EXIF `userComment`)

## Key Technical Decisions

### Image Loading — Coil
```kotlin
ImageLoader.Builder(this).components {
    add(ImageDecoderDecoder.Factory())  // Android 9+ native decoder
    add(GifDecoder.Factory())           // GIF support
    add(VideoFrameDecoder.Factory())    // Video thumbnail extraction
}.memoryCache {
    MemoryCache.Builder(this).maxSizePercent(0.25).build()  // 25% of app memory
}.build()
```
- Uses **Coil 2.2.2** (not Glide, not Fresco)
- 25% memory cache — aggressive but justified for a gallery
- Separate cache keys: `thumbnail_${id}` and `full_${id}` for different resolutions

### Video Playback — ExoPlayer (Media3)
- Single `ExoPlayer` instance shared across all `MediaViewHolder`s
- Lazy initialization — only created when first video is viewed
- `REPEAT_MODE_ONE` — loops current video
- `keepScreenOn = true` only while video is playing
- Image and PlayerView toggle visibility based on media type

### Query System — Type-Safe DSL
Glimpse has a **custom type-safe query builder**:
```kotlin
infix fun <T> Column.eq(other: T) = Query(Literal(this)) eq Query(Literal(other))
infix fun Query.or(other: Query) = Query(Or(this.root, other.root))
infix fun Query.and(other: Query) = Query(And(this.root, other.root))
```
This builds SQL-like expressions that compile to parameterized queries. Clean, safe, no string concatenation.

### ContentResolver Extensions
- `queryFlow()` — wraps `ContentResolver.registerContentObserver()` into a Kotlin Flow
- `createTrashRequest()`, `createDeleteRequest()` — uses Android 11+ `MediaStore` scoped storage APIs
- All mutations go through `ActivityResultContracts.StartIntentSenderForResult()` — proper scoped storage compliance

### Permissions
- `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO` (Android 13+)
- `MANAGE_MEDIA` — for trash/delete without user confirmation dialogs
- `ACCESS_MEDIA_LOCATION` — for GPS data in EXIF
- `PermissionsGatedCallback` — reusable pattern that gates all UI behind permission check

### Dynamic Colors
```kotlin
DynamicColors.applyToActivitiesIfAvailable(this)
```
Uses Material You (Monet) dynamic colors — app theme adapts to user's wallpaper.

## What Shutr Can Learn From Glimpse

### ✅ Adopt These Patterns
1. **Coil for image loading** — same library, same cache strategy. Use `memoryCacheKey` pattern for thumbnail vs full-res separation.
2. **Date headers in album grid** — Glimpse interleaves `DateHeader` view types between photos. This is the #1 thing that makes a gallery feel "native."
3. **Two-tier cache keys** — `thumbnail_${id}` for grid, `full_${id}` for viewer. Prevents re-decoding.
4. **Lazy video player** — don't initialize video decoder until a video is actually viewed.
5. **Flow-based reactive data** — Glimpse's `queryFlow()` pattern is elegant. In Flutter, the equivalent is using `photo_manager` with `ChangeNotifier` or `StreamBuilder`.
6. **EXIF info sheet** — Glimpse's media info bottom sheet is comprehensive and well-designed.
7. **Scoped storage compliance** — all deletions go through `ActivityResultContracts`, never direct file access.

### ❌ Don't Copy These (Shutr-Specific)
1. **No custom data layer** — Glimpse only reads MediaStore. Shutr needs to merge local MediaStore data with P2P-received photos. You'll need a custom data model that combines both sources.
2. **No network/P2P layer** — obviously, Glimpse has zero networking. Shutr's architecture is fundamentally different.
3. **Fragment-based navigation** — Flutter uses a different paradigm. Don't try to replicate NavHostFragment.
4. **MediaStore-only queries** — Shutr will need to query both MediaStore AND its own P2P photo cache.

### 🎨 UI/UX Takeaways
1. **Album grid = thumbnail + name + count** — nothing else. Glimpse proves this is all users need.
2. **Toolbar collapses on scroll** — Material 3 `AppBarLayout` with `scroll|enterAlways|snap`. In Flutter: `SliverAppBar` with `floating: true, snap: true`.
3. **Fullscreen viewer has top/bottom sheets** — not floating action buttons. Sheets are anchored to edges, fade in/out on tap.
4. **Selection mode uses blur** — Android 12+ `RenderEffect.createBlurEffect()`. In Flutter: `ImageFiltered` with `ImageFilter.blur`.
5. **No FABs in gallery** — all actions are in the bottom sheet or action bar. Clean, no floating elements over photos.

### 📐 Architecture Comparison: Glimpse vs Shutr

| Aspect | Glimpse | Shutr |
|---|---|---|
| Data source | MediaStore only | MediaStore + P2P cache |
| Image loading | Coil | `photo_manager` + `AssetEntityImage` |
| Video playback | ExoPlayer (Media3) | `url_launcher` external player |
| Navigation | Jetpack NavComponent | Flutter Navigator/BottomNav |
| State mgmt | ViewModel + Flow | Provider + setState |
| Reactive data | ContentResolver.queryFlow | photo_manager notifyListeners |
| Permissions | READ_MEDIA_*, MANAGE_MEDIA | Same + network permissions |
| Theme | Material You dynamic | Custom dark theme |
| Min SDK | 30 (Android 11) | Same (photo_manager requirement) |

### 🔑 Critical Insight for Shutr's Gallery Redesign
Glimpse's `AlbumViewerViewModel` does something Shutr doesn't: **it interleaves date headers into the data stream**. The `mediaWithHeaders` flow transforms a flat list of `MediaStoreMedia` into `List<DataType>` where `DataType` is either `Thumbnail` or `DateHeader`. This is computed reactively — when new photos arrive, headers are recalculated automatically.

**Shutr should do the same:** Instead of having separate state for "photos" and "headers," compute headers as a derived state from the photo list. This eliminates sync bugs between the two.

# compaction

## What We've Achieved (Pre-Reset)

### P2P Layer — Conceptual (Not Built Yet)
- Architecture defined: master-as-server, WebRTC for direct transfer, Cloudflare Workers for discovery (V2)
- Role system designed: Master / Contributor / Viewer
- Shutdown system designed: immediate + countdown with notifications
- Photo limits defined: 50/contributor, 500/album, 10MB/photo, 3 live albums max

### Gallery Layer — Working but Rough
- **Album grid** — 2-column grid showing albums with thumbnail (first photo), name, photo count
- **Photo viewer** — PageView swipe between photos, pinch-to-zoom, rotation
- **Video support** — Videos visible in grid, play button overlay, opens external player
- **Photo actions** — Share, delete, set as album cover, view info
- **Live asset handling** — Photos added via P2P show uploader name, can be removed
- **Deleted ID tracking** — Viewer returns deleted IDs back to grid for immediate removal
- **System UI toggle fix** — `SystemChrome.setEnabledSystemUIMode()` properly hides/shows bars
- **Pull-to-refresh feedback** — Shows "X new photos" or "Up to date"
- **Album cover** — Manual set via photo viewer menu, persists
- **Color scheme** — Neutral blue-gray (#6B8AFF), green only for live pulse (#4CAF50)
- **Bottom nav** — Labels increased to 13px, friendlier empty states
- **Gradient backdrop** — Back button visible against bright photos
- **Drag-select removed** — Replaced with long-press + tap only

### File Structure
```
lib/
  main.dart                    — App entry, bottom nav shell
  screens/
    recent_page.dart           — Recent photos grid (all media)
    albums_page.dart           — Album grid (2 columns)
    album_detail_page.dart     — Photos inside an album
    gallery_screen.dart        — Shared gallery view
    shared_gallery_screen.dart — Viewer-side gallery
    photo_viewer.dart          — Full-screen photo viewer
    search_page.dart           — Search functionality
  services/
    peer_service.dart          — P2P service (skeleton)
  utils/
    gallery_utils.dart         — Gallery helper utilities
```

### Dependencies
- `photo_manager` — MediaStore access (images + videos)
- `photo_manager_image_provider` — AssetEntityImage widget
- `provider` — State management
- `share_plus` — Share photos/videos
- `url_launcher` — External video playback
- `flutter/services.dart` — SystemChrome, HapticFeedback

## What We're Gonna Do (Gallery Layer Reset)

### Inspired by Glimpse (LineageOS Gallery)

### 1. Date Headers in Album Grid
- Photos grouped by day: "Today", "Yesterday", "March 15, 2026"
- Computed as derived state from photo list — no separate state management
- Header inserted when gap ≥ 1 day OR crosses month boundary
- Flutter equivalent: `SliverList` with mixed `SliverToBoxAdapter` (header) + grid items

### 2. Collapsible AppBar
- `SliverAppBar` with `floating: true, snap: true`
- Collapses on scroll down, reappears on scroll up
- Album name as title, clean Material 3 styling

### 3. Full-Screen Viewer Overhaul
- Top sheet: back button, date/time text — anchored to top
- Bottom sheet: share, info, delete, rotate buttons — anchored to bottom
- Single tap toggles fullscreen — calls `SystemChrome.setEnabledSystemUIMode()`
- Sheets fade with `AnimatedOpacity`, not just hide
- Video: keep external player for now (ExoPlayer in Flutter = heavy dependency)

### 4. Two-Tier Image Caching
- Thumbnail cache key: `thumb_${asset.id}` for grid view
- Full-res cache key: `full_${asset.id}` for viewer
- Prevents re-decoding when navigating between grid and viewer
- Use `photo_manager`'s thumbnail size parameter explicitly

### 5. Album Grid Redesign
- Keep 2-column layout (Glimpse uses responsive, but 2-col is fine for mobile)
- Album card: thumbnail (first photo, no decoration) + album name + photo count
- No icons, no badges, no unnecessary elements
- Live album = small green pulsing dot ONLY
- Dark background, white text, minimal typography

### 6. Photo Info Sheet Upgrade
- Add EXIF data: camera make/model, exposure, ISO, focal length
- GPS coordinates if available (photo_manager supports latlngAsync)
- Format cleanly in bottom sheet
- Keep it simple — no editable descriptions (out of scope)

### 7. Selection Mode (Future)
- Long-press enters multi-select mode
- Selected photos show checkmark overlay
- Action bar appears: share, delete
- For now: keep long-press + tap, add action bar later

## Our Goal

**Shutr's gallery layer should feel indistinguishable from a native Android gallery app.**

When a user opens Shutr, they should think "this is just my gallery" — not "this is a P2P app with a gallery tacked on." The P2P features (going live, joining, contributing) should feel like natural extensions of the gallery, not separate features.

### Design Principles
1. **Restraint over complexity** — If Glimpse doesn't have it, we probably don't need it
2. **Derived state over separate state** — Compute headers, counts, etc. from source data
3. **Reactive over imperative** — Data flows down, events flow up. No manual refresh calls
4. **Native feel over custom flair** — Material 3 patterns, not custom animations
5. **P2P is invisible** — Live photos appear seamlessly, no "syncing" indicators

### Target Architecture (Gallery Layer Only)
```
lib/
  screens/
    home_screen.dart           — Bottom nav shell (Recent, Albums, Join)
    recent_screen.dart         — All photos with date headers (SliverList)
    albums_screen.dart         — Album grid (2 columns)
    album_screen.dart          — Photos inside album with date headers
    photo_viewer.dart          — Full-screen viewer with top/bottom sheets
  widgets/
    date_header.dart           — Reusable date header widget
    album_card.dart            — Album grid item
    photo_grid_item.dart       — Photo thumbnail in grid
    viewer_top_sheet.dart      — Back + date/time
    viewer_bottom_sheet.dart   — Action buttons
  models/
    gallery_item.dart          — Union type: Photo | DateHeader
  utils/
    gallery_utils.dart         — Date grouping, cache key generation
```

## Problems We Cannot Fix (And Won't)

### photo_manager Limitations
1. **No real-time MediaStore observer** — `photo_manager` doesn't emit when device gallery changes. Must poll or manually refresh. Glimpse uses `ContentResolver.registerContentObserver()` which Flutter can't access directly.
2. **No EXIF read API** — `photo_manager` gives basic metadata (width, height, date, orientation) but not camera make, ISO, aperture, GPS. Would need `exif` package + file access, which is slow and unreliable on Android 13+.
3. **Thumbnail quality** — `photo_manager` thumbnails are compressed. Cannot get full-res without loading entire image into memory. Coil (Glimpse) handles this better natively.
4. **Video thumbnails** — Video frame extraction is inconsistent across devices. Some devices return black frames.

### Flutter Platform Constraints
5. **No in-app video player without heavy dependency** — ExoPlayer via `video_player` or `media_kit` adds 10-20MB to APK. External player (`url_launcher`) is lighter but breaks immersion. Trade-off: keep external for now.
6. **No native blur on selection** — Flutter's `ImageFiltered` blur is GPU-intensive on large grids. Glimpse uses Android's `RenderEffect` which is hardware-accelerated. Not worth the performance cost.
7. **No dynamic colors** — Flutter's `dynamic_color` package exists but requires Material 3 setup and doesn't work as seamlessly as Android's Monet. Fixed dark theme is fine.
8. **SystemChrome toggle has race condition** — When rapidly tapping to toggle UI, bars can flicker. This is a Flutter engine limitation, not fixable at app level.

### Android Scoped Storage
9. **Cannot delete photos silently** — Android 13+ requires user confirmation for each delete via `createDeleteRequest()`. No workaround without `MANAGE_MEDIA` permission (which requires special approval). Glimpse uses this permission because it's a system app. Shutr cannot.
10. **Cannot write to EXIF** — Scoped storage prevents modifying photo metadata without `createWriteRequest()` user confirmation. Photo descriptions (Glimpse feature) not possible without UX friction.

### P2P Layer (Future Problems)
11. **WebRTC on mobile is unstable** — NAT traversal fails on some networks. STUN/TURN servers needed for reliability, but TURN costs money. Free tier = same-network only (V1 plan).
12. **Background transfer impossible** — Android kills background processes aggressively. P2P transfer only works while app is in foreground. No workaround without foreground service (battery drain).
13. **Large file transfer over WebRTC** — WebRTC data channels have 256KB buffer limit. Photos >10MB need chunking, which adds complexity and failure points.

### What We Accept As-Is
- Delete = permanent, no trash (scoped storage limitation)
- Video = external player (weight vs immersion trade-off)
- No EXIF camera details (photo_manager limitation)
- No real-time gallery sync (Flutter platform channel limitation)
- No dynamic colors (not worth the setup cost)
- No selection blur (performance cost too high)
- No silent delete (Android policy, no workaround)