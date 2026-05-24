# Graph Report - .  (2026-05-24)

## Corpus Check
- Corpus is ~44,919 words - fits in a single context window. You may not need a graph.

## Summary
- 319 nodes · 365 edges · 16 communities detected
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output


## Input Scope
- Requested: auto
- Resolved: committed (source: default-auto)
- Included files: 105 · Candidates: 176
- Excluded: 7 untracked · 16847 ignored · 0 sensitive · 1 missing committed
- Recommendation: Use --scope all or graphify.yaml inputs.corpus for a knowledge-base folder.

## Graph Freshness
- Built from Git commit: `dba57c6`
- Compare this hash to `git rev-parse HEAD` before trusting freshness-sensitive graph output.
## God Nodes (most connected - your core abstractions)
1. `Create()` - 6 edges
2. `Destroy()` - 6 edges
3. `MessageHandler()` - 5 edges
4. `Win32Window::WndProc()` - 4 edges
5. `GetClientArea()` - 3 edges
6. `UpdateTheme()` - 3 edges
7. `ShutRApp` - 2 edges
8. `main()` - 2 edges
9. `AlbumDetailPage` - 2 edges
10. `_AlbumDetailPageState` - 2 edges

## Surprising Connections (you probably didn't know these)
- None detected - all connections are within the same source files.

## Communities

### Community 0 - "Community 0"
Cohesion: 0.08
Nodes (28): _cancelSelection(), _DateGroup, _DateHeaderDelegate, _DeleteDialog, _deleteSelected(), dispose(), _enterSelection(), _FastScrollbar (+20 more)

### Community 1 - "Community 1"
Cohesion: 0.08
Nodes (25): AlbumDetailPage, _AlbumDetailPageState, _cancelSelection(), _DateGroup, _DateHeaderDelegate, _DeleteDialog, _deleteSelected(), dispose() (+17 more)

### Community 2 - "Community 2"
Cohesion: 0.05
Nodes (5): ConnectedUser, LiveAlbum, LiveAsset, PeerEvent, PeerService

### Community 3 - "Community 3"
Cohesion: 0.06
Nodes (10): _AlbumThumbnail, _AlbumThumbnailState, _GuestAlbumView, _GuestAlbumViewState, _RemotePhotoViewer, _RemotePhotoViewerState, SharedGalleryScreen, _SharedGalleryScreenState (+2 more)

### Community 4 - "Community 4"
Cohesion: 0.12
Nodes (15): _AlbumCell, _AlbumContextMenu, _AlbumData, _AlbumRevealZone, _AlbumRevealZoneState, AlbumsPage, _AlbumsPageState, dispose() (+7 more)

### Community 5 - "Community 5"
Cohesion: 0.14
Nodes (13): _BottomMeta, _BottomMetaState, _DeleteDialog, didUpdateWidget(), dispose(), initState(), PhotoViewer, _PhotoViewerState (+5 more)

### Community 6 - "Community 6"
Cohesion: 0.17
Nodes (16): Create(), Destroy(), EnableFullDpiSupportIfAvailable(), GetClientArea(), GetThisFromHandle(), GetWindowClass(), MessageHandler(), OnCreate() (+8 more)

### Community 7 - "Community 7"
Cohesion: 0.15
Nodes (6): _AlbumChip, _AlbumData, _DateGroup, dispose(), SearchPage, _SearchPageState

### Community 8 - "Community 8"
Cohesion: 0.13
Nodes (6): DateGroup, DateHeaderDelegate, DeleteDialog, PhotoCell, _PhotoCellState, SelectionBar

### Community 9 - "Community 9"
Cohesion: 0.15
Nodes (7): _LockedMediaQuery, _LockedMediaQueryState, main(), PermissionGate, _PermissionGateState, ShutRApp, ShutrThemeExtension

### Community 10 - "Community 10"
Cohesion: 0.2
Nodes (5): GalleryScreen, _GalleryScreenState, initState(), _SettingsSheet, _SettingsSheetState

### Community 12 - "Community 12"
Cohesion: 0.33
Nodes (1): FlutterWindow()

### Community 13 - "Community 13"
Cohesion: 0.5
Nodes (2): handle_new_rx_page(), Intercept NOTIFY_DEBUGGER_ABOUT_RX_PAGES and touch the pages.

### Community 14 - "Community 14"
Cohesion: 0.67
Nodes (2): GetCommandLineArguments(), Utf8FromUtf16()

### Community 15 - "Community 15"
Cohesion: 0.67
Nodes (1): GeneratedPluginRegistrant

### Community 16 - "Community 16"
Cohesion: 0.67
Nodes (2): GeneratedPluginRegistrant, -registerWithRegistry

## Knowledge Gaps
- **54 isolated node(s):** `_DateHeaderDelegate`, `_PhotoCell`, `_PhotoCellState`, `_SelectionBar`, `_DateGroup` (+49 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Community 12`** (1 nodes): `FlutterWindow()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 13`** (2 nodes): `handle_new_rx_page()`, `Intercept NOTIFY_DEBUGGER_ABOUT_RX_PAGES and touch the pages.`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 14`** (2 nodes): `GetCommandLineArguments()`, `Utf8FromUtf16()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 15`** (1 nodes): `GeneratedPluginRegistrant`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 16`** (2 nodes): `GeneratedPluginRegistrant`, `-registerWithRegistry`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What connects `_DateHeaderDelegate`, `_PhotoCell`, `_PhotoCellState` to the rest of the system?**
  _54 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.08 - nodes in this community are weakly interconnected._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.08 - nodes in this community are weakly interconnected._
- **Should `Community 2` be split into smaller, more focused modules?**
  _Cohesion score 0.05 - nodes in this community are weakly interconnected._
- **Should `Community 3` be split into smaller, more focused modules?**
  _Cohesion score 0.06 - nodes in this community are weakly interconnected._
- **Should `Community 4` be split into smaller, more focused modules?**
  _Cohesion score 0.12 - nodes in this community are weakly interconnected._
- **Should `Community 5` be split into smaller, more focused modules?**
  _Cohesion score 0.14 - nodes in this community are weakly interconnected._