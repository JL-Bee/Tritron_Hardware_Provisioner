# Tritron Hardware Provisioner Setup

## Overview
This Flutter application provides a cross-platform serial port scanner and communication interface for provisioning NRF52 DK devices in a Bluetooth mesh network.

## Features
- Automatic detection of serial ports across all platforms
- NRF52 device identification
- Real-time serial communication
- Auto-reconnection capabilities
- Data logging and monitoring

## Platform-Specific Setup

### Windows
No additional setup required. The application will automatically detect COM ports.

### macOS
1. No special permissions needed for USB serial devices
2. Devices typically appear as `/dev/cu.usbmodem*` or `/dev/cu.usbserial*`

### Linux
1. Add your user to the `dialout` group:
   ```bash
   sudo usermod -a -G dialout $USER
   ```
2. Log out and back in for the changes to take effect
3. Devices typically appear as `/dev/ttyUSB*` or `/dev/ttyACM*`

### Android
1. The app requires USB host support
2. USB permissions will be requested when connecting to a device
3. Make sure USB debugging is disabled to avoid conflicts

### iOS
Serial port communication over USB is not supported on iOS due to platform limitations.

## Dependencies Installation

Run the following command to install all required dependencies:
```bash
flutter pub get
```

### Platform-Specific Dependencies

#### Linux
Install libserialport:
```bash
# Ubuntu/Debian
sudo apt-get install libserialport-dev

# Fedora
sudo dnf install libserialport-devel

# Arch
sudo pacman -S libserialport
```

#### macOS
Install libserialport using Homebrew:
```bash
brew install libserialport
```

#### Windows
No additional installation required. The package includes prebuilt binaries.

## Building and Running

### Development
```bash
flutter run
```

### Building for Release

#### Windows
```bash
flutter build windows --release
```

#### macOS
```bash
flutter build macos --release
```

#### Linux
```bash
flutter build linux --release
```

#### Android
```bash
flutter build apk --release
```

## NRF52 DK Configuration

Ensure your NRF52 DK is configured with:
- Baud rate: 115200
- Data bits: 8
- Stop bits: 1
- Parity: None
- Flow control: None

## Troubleshooting

### Port Access Denied (Linux)
If you get permission errors, ensure you're in the `dialout` group and have logged out/in.

### Device Not Detected
1. Check USB cable connection
2. Verify drivers are installed (Windows)
3. Try a different USB port
4. Check device manager / system information for the device

### Android USB Issues
1. Enable Developer Options and USB debugging temporarily to check if device is detected
2. Some Android devices require OTG adapters for USB host functionality
3. Check if your device supports USB host mode

## Communication Protocol

The app expects the NRF52 DK to respond to standard AT commands for initial handshake:
- Send: `AT\r\n`
- Expected response: `OK\r\n`

Implement your custom protocol on top of this basic communication layer.
