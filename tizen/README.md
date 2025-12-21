# Tizen (Samsung TV) Build Instructions

This directory contains the Tizen platform configuration for building the app for Samsung Smart TVs.

## Prerequisites

1. **Install Flutter-Tizen**: Follow the installation guide at [flutter-tizen](https://github.com/flutter-tizen/flutter-tizen)

```bash
git clone https://github.com/jckdotim/flutter-tizen.git
export PATH="$PATH:`pwd`/flutter-tizen/bin"
```

2. **Install Tizen Studio**: Download from [Samsung Developer](https://developer.samsung.com/smarttv/develop/getting-started/setting-up-sdk/installing-tv-sdk.html)

3. **Configure Tizen Certificate**: You need a Samsung certificate to deploy to real TV devices.

## Building for Tizen

### Development Build

```bash
# Run on connected TV or emulator
flutter-tizen run -d <device-id>

# List available devices
flutter-tizen devices
```

### Release Build

```bash
# Build TPK package for TV
flutter-tizen build tpk -ptv

# Build with release mode
flutter-tizen build tpk -ptv --release
```

The output TPK file will be in `build/tizen/tpk/`.

## TV-Specific Considerations

### Remote Control
The app handles Samsung TV remote control through keyboard events. Key mappings:
- Arrow keys: Navigation
- Enter: Select
- Escape: Back
- Media keys: Playback control

### Video Playback
Video playback uses `video_player_tizen` which provides native TV video decoding. This supports:
- Hardware-accelerated playback
- HDR content (on supported TVs)
- Adaptive streaming (HLS, DASH)

### Unsupported Features
Some features are not available on Tizen TV:
- Biometric authentication (local_auth)
- Screen brightness control
- Wakelock (handled by TV system)
- Desktop window management

### Privileges
The app requires these Tizen privileges (defined in `tizen-manifest.xml`):
- `http://tizen.org/privilege/internet` - Network access
- `http://tizen.org/privilege/mediastorage` - Media storage access
- `http://tizen.org/privilege/display` - Display control
- `http://tizen.org/privilege/volume.set` - Volume control

## Testing on TV

1. **Enable Developer Mode** on your Samsung TV:
   - Settings > General > System Manager > Smart Hub Reset
   - Navigate to Apps and press 1-2-3-4-5 on the remote
   - Enable Developer Mode and enter your PC's IP address

2. **Connect** to the TV:
   ```bash
   sdb connect <tv-ip-address>
   ```

3. **Deploy** the app:
   ```bash
   flutter-tizen run -d <tv-ip-address>
   ```

## Resources

- [Samsung TV Developer Documentation](https://developer.samsung.com/smarttv/develop/native/flutter.html)
- [Flutter-Tizen GitHub](https://github.com/flutter-tizen/flutter-tizen)
- [Flutter-Tizen Plugins](https://github.com/flutter-tizen/plugins)


