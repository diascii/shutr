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
The problem: Your _toggleUI() only changes _uiVisible state but never calls SystemChrome.setEnabledSystemUIMode(), so the system bars never actually hide/show. And your main.dart sets edgeToEdge globally which is good, but the viewer doesn't toggle it.
Here's the fix — update _toggleUI() and add a restore in dispose():
dartvoid _toggleUI() {
  final nextVisible = !_uiVisible;
  setState(() => _uiVisible = nextVisible);

  if (nextVisible) {
    // Show bars — but stay edge-to-edge so NO resize happens
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  } else {
    // Hide bars completely
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
    );
  }
}
And in your dispose(), restore back to edgeToEdge when leaving the viewer:
dart@override
void dispose() {
  // Restore system UI when leaving viewer
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  _pageCtrl.dispose();
  super.dispose();
}
That's literally all you need. The key reason this won't cause resizing is because:

Your Scaffold already has extendBodyBehindAppBar: true and extendBody: true ✅
edgeToEdge keeps your app filling the full screen even when bars are visible — the bars just overlay on top instead of pushing content
immersiveSticky hides them without any layout shift

Your existing code is already structured correctly for this, the _toggleUI just wasn't calling SystemChrome at all.

# newest logs