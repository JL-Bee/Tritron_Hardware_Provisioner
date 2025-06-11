<!-- bluetooth_mesh_hardware_provisioner/README.md -->

# Tritron Hardware Provisioner

A comprehensive Flutter application for provisioning and managing Bluetooth mesh networks using NRF52 DK hardware.

## Features

### 🔌 Serial Connection Management
- Automatic detection of serial ports across all platforms
- Special NRF52 device identification
- Real-time connection status monitoring
- Auto-reconnection capabilities

### 📡 Bluetooth Mesh Scanner
- Discover unprovisioned Bluetooth mesh devices
- View provisioned nodes in the network
- Real-time device status updates
- Support for provisioning and unprovisioning devices

### 🕸️ Network Visualization
- Interactive 2D mesh network topology view
- Visual representation of node connections
- Group address visualization
- Real-time network status updates
- Zoom and pan controls

### 🎛️ Device Management
- Detailed device information display
- Model configuration viewing (SIG and Vendor models)
- Subscribe address management
- Publish configuration
- Health status monitoring

### 💻 Console Interface
- Raw command input for advanced users
- Real-time data logging
- Command history
- Bidirectional communication monitoring

## Architecture

```
lib/
├── main.dart                    # Main application entry
├── models/
│   ├── serial_port_info.dart   # Serial port information model
│   └── mesh_models.dart        # Bluetooth mesh data models
├── services/
│   └── serial_port_service.dart # Serial communication service
├── protocols/
│   └── nrf52_protocol.dart     # NRF52 command protocol handler
└── screens/
    ├── mesh_visualizer_screen.dart  # Network topology visualization
    └── device_details_screen.dart   # Device details and management
```

## NRF52 DK Commands

The app communicates with the NRF52 DK using shell commands.
All commands must be prefixed with `mesh/`.

### General Commands
- `mesh/factory_reset` - Factory reset the provisioner

### Provision Commands
- `mesh/provision/scan/get` - List provisionable device UUIDs
- `mesh/provision/provision {uuid}` - Provision a device
- `mesh/provision/result/get` - Get last provisioning result
- `mesh/provision/status/get` - Get provisioning state
- `mesh/provision/last_addr/get` - Get the last assigned address

### Device Commands
- `mesh/device/reset {node_addr}` - Reset and unprovision a node
- `mesh/device/remove {node_addr}` - Remove a node from the local DB
- `mesh/device/label/get {node_addr}` - Fetch the node's label
- `mesh/device/label/set {node_addr} {label}` - Set a label for the node
- `mesh/device/identify` - Identify a node
- `mesh/device/list` - List provisioned nodes

### Subscription Commands
- `mesh/device/sub/add {node_addr} {sub_addr}` - Add subscribe address
- `mesh/device/sub/remove {node_addr} {sub_addr}` - Remove subscribe address
- `mesh/device/sub/reset {node_addr}` - Reset subscribe list
- `mesh/device/sub/get {node_addr}` - Get subscribe list

### Lighting Control Commands
- `mesh/dali_lc/idle_cfg/set {addr} {arc} {fade} {timeout}` - Set idle config
- `mesh/dali_lc/idle_cfg/get {addr} {timeout}` - Get idle config
- `mesh/dali_lc/trigger_cfg/set {addr} {arc} {fade_in} {fade_out} {hold} {timeout}` - Set trigger config
- `mesh/dali_lc/trigger_cfg/get {addr} {timeout}` - Get trigger config
- `mesh/dali_lc/identify/set {addr} {duration} {timeout}` - Identify node
- `mesh/dali_lc/identify/get {addr} {timeout}` - Get identify time
- `mesh/dali_lc/override/set {addr} {arc} {fade} {duration} {timeout}` - Override output
- `mesh/dali_lc/override/get {addr} {timeout}` - Get override state

### Radar Commands
- `mesh/radar/cfg/set {addr} {band} {cross} {interval} {depth} {timeout}` - Set radar configuration
- `mesh/radar/cfg/get {addr} {timeout}` - Get radar configuration
- `mesh/radar/enable/set {addr} {enable} {timeout}` - Enable/disable radar
- `mesh/radar/enable/get {addr} {timeout}` - Get radar enable state

### Fade Time Values
The DALI commands use predefined fade times listed below:

| Value | Duration |
| ----- | -------- |
| 0 | 0s |
| 1 | 0.5s |
| 2 | 1s |
| 3 | 1.5s |
| 4 | 2s |
| 5 | 3s |
| 6 | 4s |
| 7 | 6s |
| 8 | 8s |
| 9 | 10s |
| 10 | 15s |
| 11 | 20s |
| 12 | 30s |
| 13 | 45s |
| 14 | 60s |
| 15 | 90s |
| 16 | 2m |
| 17 | 3m |
| 18 | 4m |
| 19 | 5m |
| 20 | 6m |
| 21 | 7m |
| 22 | 8m |
| 23 | 9m |
| 24 | 10m |
| 25 | 11m |
| 26 | 12m |
| 27 | 13m |
| 28 | 14m |
| 29 | 15m |
| 30 | 16m |
| 255 | Invalid |

## Platform Setup

### Windows
No additional setup required. The application will automatically detect COM ports.

### macOS
1. Install libserialport: `brew install libserialport`
2. Devices appear as `/dev/cu.usbmodem*`

### Linux
1. Install libserialport: `sudo apt-get install libserialport-dev`
2. Add user to dialout group: `sudo usermod -a -G dialout $USER`
3. Log out and back in
4. Devices appear as `/dev/ttyUSB*` or `/dev/ttyACM*`

### Android
1. Ensure device supports USB host mode
2. USB permissions will be requested automatically
3. May require OTG adapter for some devices

## Building

### Development
```bash
flutter run
```

### Release Builds
```bash
# Windows
flutter build windows --release

# macOS
flutter build macos --release

# Linux
flutter build linux --release

# Android
flutter build apk --release
```

## Usage Guide

### 1. Connect to NRF52 DK
1. Connect NRF52 DK via USB
2. Launch the app
3. Go to Connection tab
4. Select the NRF52 device (highlighted in blue)
5. Device will connect automatically

### 2. Scan for Devices
1. Navigate to Scanner tab
2. Unprovisioned devices appear automatically
3. Click "Provision" to add device to network
4. Provisioned nodes show configuration status

### 3. Visualize Network
1. Go to Mesh View tab
2. Pan and zoom to explore network
3. Click nodes for details
4. View connections between nodes

### 4. Manage Devices
1. Click on any provisioned node
2. View detailed information
3. Add/remove subscribe addresses
4. Perform health checks
5. Unprovision if needed

### 5. Advanced Usage
1. Use Console tab for raw commands
2. Monitor all communication
3. Send custom commands
4. Debug protocol issues

## Troubleshooting

### Connection Issues
- Verify USB cable is data-capable
- Check device drivers (Windows)
- Ensure user has proper permissions (Linux)
- Try different USB port

### Scanning Issues
- Ensure NRF52 firmware is properly flashed
- Check if mesh stack is initialized
- Verify beacon transmission

### Provisioning Failures
- Check if device is in range
- Ensure device isn't already provisioned
- Verify network keys are correct
- Check for address conflicts

## Protocol Details

The app expects responses in specific formats:

### Unprovisioned Device List
```
0: uuid (timestamp)
1: uuid (timestamp)
```

### Provisioned Node List
```
0: uuid || addr: 2 pub: c002  sub: [c002,c003]
1: uuid || addr: 3 pub: c003  sub: [c003]
```

### Error Responses
```
err: -errorcode
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Implement your changes
4. Add appropriate tests
5. Submit a pull request

## License

[Your License Here]
