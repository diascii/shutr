# Graph Report - .  (2026-05-17)

## Corpus Check
- Corpus is ~33,673 words - fits in a single context window. You may not need a graph.

## Summary
- 261 nodes · 308 edges · 16 communities detected
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output


## Input Scope
- Requested: auto
- Resolved: all (source: default-auto)
- Included files: 97 · Candidates: recursive
- Excluded: 0 untracked · 0 ignored · 0 sensitive · 0 missing committed
## God Nodes (most connected - your core abstractions)
1. `Create()` - 6 edges
2. `Destroy()` - 6 edges
3. `MessageHandler()` - 5 edges
4. `Win32Window::WndProc()` - 4 edges
5. `GetClientArea()` - 3 edges
6. `UpdateTheme()` - 3 edges
7. `GeneratedPluginRegistrant` - 2 edges
8. `handle_new_rx_page()` - 2 edges
9. `GeneratedPluginRegistrant` - 2 edges
10. `ShutRApp` - 2 edges

## Surprising Connections (you probably didn't know these)
- None detected - all connections are within the same source files.

## Communities

### Community 15 - "Community 15"
Cohesion: 0.67
Nodes (1): GeneratedPluginRegistrant

### Community 13 - "Community 13"
Cohesion: 0.5
Nodes (2): handle_new_rx_page(), Intercept NOTIFY_DEBUGGER_ABOUT_RX_PAGES and touch the pages.

### Community 16 - "Community 16"
Cohesion: 0.67
Nodes (2): GeneratedPluginRegistrant, -registerWithRegistry

### Community 10 - "Community 10"
Cohesion: 0.22
Nodes (5): ShutRApp, ShutrThemeExtension, PermissionGate, _PermissionGateState, main()

### Community 4 - "Community 4"
Cohesion: 0.17
Nodes (13): AlbumsPage, _AlbumsPageState, _AlbumCell, _PulsingDot, _PulsingDotState, _AlbumContextMenu, _MenuItem, _AlbumData (+5 more)

### Community 0 - "Community 0"
Cohesion: 0.08
Nodes (25): AlbumDetailPage, _AlbumDetailPageState, _LiveAlbumViewer, _LiveAlbumViewerState, _LiveSelectionBar, initState(), dispose(), _onScroll() (+17 more)

### Community 9 - "Community 9"
Cohesion: 0.2
Nodes (5): GalleryScreen, _GalleryScreenState, _SettingsSheet, _SettingsSheetState, initState()

### Community 2 - "Community 2"
Cohesion: 0.14
Nodes (13): PhotoViewer, _PhotoViewerState, _ZoomablePhoto, _ZoomablePhotoState, _DeleteDialog, initState(), dispose(), _toggleUI() (+5 more)

### Community 1 - "Community 1"
Cohesion: 0.09
Nodes (28): RecentPage, _RecentPageState, _FastScrollbar, _FastScrollbarState, _PermissionPrompt, initState(), dispose(), _onScroll() (+20 more)

### Community 5 - "Community 5"
Cohesion: 0.15
Nodes (6): SearchPage, _SearchPageState, dispose(), _AlbumChip, _AlbumData, _DateGroup

### Community 6 - "Community 6"
Cohesion: 0.13
Nodes (4): SharedGalleryScreen, _SharedGalleryScreenState, _RemotePhotoViewer, _RemotePhotoViewerState

### Community 7 - "Community 7"
Cohesion: 0.14
Nodes (4): LiveAsset, ConnectedUser, PeerEvent, PeerService

### Community 8 - "Community 8"
Cohesion: 0.14
Nodes (6): DateGroup, PhotoCell, _PhotoCellState, SelectionBar, DeleteDialog, DateHeaderDelegate

### Community 12 - "Community 12"
Cohesion: 0.33
Nodes (1): FlutterWindow()

### Community 14 - "Community 14"
Cohesion: 0.67
Nodes (2): GetCommandLineArguments(), Utf8FromUtf16()

### Community 3 - "Community 3"
Cohesion: 0.17
Nodes (16): Scale(), EnableFullDpiSupportIfAvailable(), WindowClassRegistrar, GetWindowClass(), UnregisterWindowClass(), Win32Window(), Create(), Win32Window::WndProc() (+8 more)

## Knowledge Gaps
- **43 isolated node(s):** `Intercept NOTIFY_DEBUGGER_ABOUT_RX_PAGES and touch the pages.`, `-registerWithRegistry`, `ShutrThemeExtension`, `PermissionGate`, `_PermissionGateState` (+38 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Community 15`** (1 nodes): `GeneratedPluginRegistrant`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 13`** (2 nodes): `handle_new_rx_page()`, `Intercept NOTIFY_DEBUGGER_ABOUT_RX_PAGES and touch the pages.`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 16`** (2 nodes): `GeneratedPluginRegistrant`, `-registerWithRegistry`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 12`** (1 nodes): `FlutterWindow()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 14`** (2 nodes): `GetCommandLineArguments()`, `Utf8FromUtf16()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What connects `Intercept NOTIFY_DEBUGGER_ABOUT_RX_PAGES and touch the pages.`, `-registerWithRegistry`, `ShutrThemeExtension` to the rest of the system?**
  _43 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.08 - nodes in this community are weakly interconnected._
- **Should `Community 2` be split into smaller, more focused modules?**
  _Cohesion score 0.14 - nodes in this community are weakly interconnected._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.09 - nodes in this community are weakly interconnected._
- **Should `Community 6` be split into smaller, more focused modules?**
  _Cohesion score 0.13 - nodes in this community are weakly interconnected._
- **Should `Community 7` be split into smaller, more focused modules?**
  _Cohesion score 0.14 - nodes in this community are weakly interconnected._
- **Should `Community 8` be split into smaller, more focused modules?**
  _Cohesion score 0.14 - nodes in this community are weakly interconnected._