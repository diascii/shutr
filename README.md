# Shutr

Shutr is a peer-to-peer collaborative photo gallery app built with Flutter. It allows users to "go live" on specific photo albums, enabling others to join via a generated code or link to view and download photos directly from the host's device. 

**Privacy First:** Shutr operates entirely peer-to-peer. Photos never touch any cloud server, ensuring zero cloud storage costs and maximum privacy.

## Features

- **P2P Photo Transfer**: Photos transfer directly phone-to-phone via local network.
- **Collaborative Albums**: Host live albums that multiple users can join and view simultaneously.
- **Role Management**: 
  - 👑 **Master**: Full control over the album (manage roles, delete photos, shutdown).
  - 📸 **Contributor**: Can view, download, and add new photos.
  - 👁️ **Viewer**: Can view and download photos only.
- **Real-Time Sync**: When a contributor adds a photo, it appears instantly for all connected users.
- **Clean Native UI**: Designed to look and feel exactly like a native Android gallery with a minimal, dark-themed interface.
- **Smart Photo Grid**: Photos are organized with natural date headers and a clean 2-column layout.

## Tech Stack

- **Framework**: Flutter / Dart
- **State Management**: Provider
- **Image Handling**: `photo_manager` & `photo_manager_image_provider`
- **Networking**: Peer-to-Peer local networking
- **Video Support**: External playback via `url_launcher`

## Step-by-Step Installation

Follow these steps to build and run Shutr locally:

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) installed (version 3.0+)
- Android Studio or VS Code with the Flutter extension
- An Android device (Android 11+) or emulator for testing

### 1. Clone the repository
```bash
git clone git@github.com:diascii/shutr.git
cd shutr
```

### 2. Install dependencies
```bash
flutter pub get
```

### 3. Run the app
Ensure your device or emulator is connected, then run:
```bash
flutter run
```

### 4. Build for release (Android)
To generate an APK for physical devices:
```bash
flutter build apk --split-per-abi
```
The built APKs will be located in `build/app/outputs/flutter-apk/`.

## Usage

1. Open the app and allow the required media permissions.
2. Long-press any album in your gallery and tap **Go Live**.
3. Share the generated 6-character code with your friends on the same network.
4. Friends can enter the code in the **Join** tab to instantly view and download the photos peer-to-peer!