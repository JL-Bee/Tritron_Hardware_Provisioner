// lib/blocs/provisioner_bloc.dart

import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:async';
import '../models/serial_port_info.dart';
import '../models/mesh_device.dart';
import '../models/dali_lc.dart';
import '../models/radar_info.dart';
import '../services/serial_port_service.dart';
import '../services/command_processor.dart';
import '../services/mesh_command_service.dart';


// Events
abstract class ProvisionerEvent {}

class ConnectToPort extends ProvisionerEvent {
  final SerialPortInfo port;
  ConnectToPort(this.port);
}

class Disconnect extends ProvisionerEvent {}

class ScanDevices extends ProvisionerEvent {}

class RefreshDeviceList extends ProvisionerEvent {}

class ProvisionDevice extends ProvisionerEvent {
  final String uuid;
  ProvisionDevice(this.uuid);
}

class UnprovisionDevice extends ProvisionerEvent {
  final MeshDevice device;
  UnprovisionDevice(this.device);
}

class RemoveDeviceFromDb extends ProvisionerEvent {
  final MeshDevice device;
  RemoveDeviceFromDb(this.device);
}

class AddSubscription extends ProvisionerEvent {
  final int nodeAddress;
  final int groupAddress;
  AddSubscription(this.nodeAddress, this.groupAddress);
}

class RemoveSubscription extends ProvisionerEvent {
  final int nodeAddress;
  final int groupAddress;
  RemoveSubscription(this.nodeAddress, this.groupAddress);
}

class SelectDevice extends ProvisionerEvent {
  final MeshDevice? device;
  SelectDevice(this.device);
}

class ClearError extends ProvisionerEvent {}

class SendConsoleCommand extends ProvisionerEvent {
  final String command;
  SendConsoleCommand(this.command);
}

class NodeDiscovered extends ProvisionerEvent {
  final String uuid;
  NodeDiscovered(this.uuid);
}

// Internal event for processed lines
class _ProcessedLineReceived extends ProvisionerEvent {
  final ProcessedLine line;
  _ProcessedLineReceived(this.line);
}

// Internal event for polling provisioning status
class _PollProvisioningStatus extends ProvisionerEvent {
  final String uuid;
  _PollProvisioningStatus(this.uuid);
}

// Internal event to finalise provisioning once completed
class _FinalizeProvisioning extends ProvisionerEvent {
  final String uuid;
  _FinalizeProvisioning(this.uuid);
}

// States
class ProvisionerState {
  final ConnectionStatus connectionStatus;
  final SerialPortInfo? connectedPort;
  final Set<String> foundUuids;
  final List<MeshDevice> provisionedDevices;
  final MeshDevice? selectedDevice;
  final List<int> selectedDeviceSubscriptions;
  final Map<int, DaliLcInfo> daliInfo;
  final Map<int, RadarInfo> radarInfo;
  final bool isScanning;
  final bool isProvisioning;
  final String provisioningStatus;
  final String? provisioningUuid;
  final List<ConsoleEntry> consoleEntries;
  final AppError? currentError;
  final List<ActionResult> actionHistory;
  final ActionExecution? currentAction;

  ProvisionerState({
    this.connectionStatus = ConnectionStatus.disconnected,
    this.connectedPort,
    Set<String>? foundUuids,
    List<MeshDevice>? provisionedDevices,
    this.selectedDevice,
    List<int>? selectedDeviceSubscriptions,
    Map<int, DaliLcInfo>? daliInfo,
    Map<int, RadarInfo>? radarInfo,
    this.isScanning = false,
    this.isProvisioning = false,
    this.provisioningStatus = '',
    this.provisioningUuid,
    List<ConsoleEntry>? consoleEntries,
    this.currentError,
    List<ActionResult>? actionHistory,
    this.currentAction,
  })  : foundUuids = foundUuids ?? {},
        provisionedDevices = provisionedDevices ?? [],
        selectedDeviceSubscriptions = selectedDeviceSubscriptions ?? [],
        daliInfo = daliInfo ?? {},
        radarInfo = radarInfo ?? {},
        consoleEntries = consoleEntries ?? [],
        actionHistory = actionHistory ?? [];

  ProvisionerState copyWith({
    ConnectionStatus? connectionStatus,
    SerialPortInfo? connectedPort,
    Set<String>? foundUuids,
    List<MeshDevice>? provisionedDevices,
    MeshDevice? selectedDevice,
    List<int>? selectedDeviceSubscriptions,
    Map<int, DaliLcInfo>? daliInfo,
    Map<int, RadarInfo>? radarInfo,
    bool? isScanning,
    bool? isProvisioning,
    String? provisioningStatus,
    String? provisioningUuid,
    List<ConsoleEntry>? consoleEntries,
    AppError? currentError,
    bool clearError = false,
    List<ActionResult>? actionHistory,
    ActionExecution? currentAction,
  }) {
    return ProvisionerState(
      connectionStatus: connectionStatus ?? this.connectionStatus,
      connectedPort: connectedPort ?? this.connectedPort,
      foundUuids: foundUuids ?? this.foundUuids,
      provisionedDevices: provisionedDevices ?? this.provisionedDevices,
      selectedDevice: selectedDevice ?? this.selectedDevice,
      selectedDeviceSubscriptions: selectedDeviceSubscriptions ?? this.selectedDeviceSubscriptions,
      daliInfo: daliInfo ?? this.daliInfo,
      radarInfo: radarInfo ?? this.radarInfo,
      isScanning: isScanning ?? this.isScanning,
      isProvisioning: isProvisioning ?? this.isProvisioning,
      provisioningStatus: provisioningStatus ?? this.provisioningStatus,
      provisioningUuid: provisioningUuid ?? this.provisioningUuid,
      consoleEntries: consoleEntries ?? this.consoleEntries,
      currentError: clearError ? null : (currentError ?? this.currentError),
      actionHistory: actionHistory ?? this.actionHistory,
      currentAction: currentAction ?? this.currentAction,
    );
  }
}

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

enum ConsoleEntryType {
  command,
  response,
  info,
  error,
}

class ConsoleEntry {
  final String text;
  final ConsoleEntryType type;
  final DateTime timestamp;
  final bool timedOut;

  ConsoleEntry({
    required this.text,
    required this.type,
    DateTime? timestamp,
    this.timedOut = false,
  }) : timestamp = timestamp ?? DateTime.now();
}

class AppError {
  final String message;
  final ErrorSeverity severity;
  final DateTime timestamp;

  AppError({
    required this.message,
    this.severity = ErrorSeverity.error,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

enum ErrorSeverity {
  info,
  warning,
  error,
}

class ActionResult {
  final String action;
  final bool success;
  final String? message;
  final List<ConsoleEntry> log;
  final DateTime timestamp;

  ActionResult({
    required this.action,
    required this.success,
    this.message,
    List<ConsoleEntry>? log,
    DateTime? timestamp,
  })  : log = log ?? [],
        timestamp = timestamp ?? DateTime.now();

  ActionResult copyWith({
    bool? success,
    String? message,
    List<ConsoleEntry>? log,
  }) {
    return ActionResult(
      action: action,
      success: success ?? this.success,
      message: message ?? this.message,
      log: log ?? this.log,
      timestamp: timestamp,
    );
  }
}

class ActionExecution {
  final String action;
  final List<ConsoleEntry> log;
  final DateTime timestamp;

  ActionExecution({
    required this.action,
    List<ConsoleEntry>? log,
    DateTime? timestamp,
  })  : log = log ?? [],
        timestamp = timestamp ?? DateTime.now();

  ActionExecution copyWith({List<ConsoleEntry>? log}) {
    return ActionExecution(
      action: action,
      log: log ?? this.log,
      timestamp: timestamp,
    );
  }
}

// BLoC Implementation
class ProvisionerBloc extends Bloc<ProvisionerEvent, ProvisionerState> {
  final SerialPortService _serialService = SerialPortService();
  CommandProcessor? _processor;
  MeshCommandService? _meshService;

  StreamSubscription? _serialStatusSubscription;
  StreamSubscription? _processedLineSubscription;
  StreamSubscription? _nodeFoundSubscription;

  /// Timer used to poll the provisioning status while a node is being
  /// provisioned. It is cancelled once provisioning completes or the bloc is
  /// disposed.
  Timer? _provisioningTimer;
  /// Timer that periodically refreshes the device list to update heartbeat
  /// information. Cancelled on disconnect.
  Timer? _deviceListTimer;

  /// Addresses of devices that have been seen in at least one device list call.
  final Set<int> _knownDeviceAddresses = {};

  ProvisionerBloc() : super(ProvisionerState()) {
    on<ConnectToPort>(_onConnectToPort);
    on<Disconnect>(_onDisconnect);
    on<ScanDevices>(_onScanDevices);
    on<RefreshDeviceList>(_onRefreshDeviceList);
    on<ProvisionDevice>(_onProvisionDevice);
    on<UnprovisionDevice>(_onUnprovisionDevice);
    on<RemoveDeviceFromDb>(_onRemoveDeviceFromDb);
    on<AddSubscription>(_onAddSubscription);
    on<RemoveSubscription>(_onRemoveSubscription);
    on<SelectDevice>(_onSelectDevice);
    on<ClearError>(_onClearError);
    on<NodeDiscovered>(_onNodeDiscovered);
    on<SendConsoleCommand>(_onSendConsoleCommand);
    on<_ProcessedLineReceived>(_onProcessedLineReceived);
    on<_PollProvisioningStatus>(_onPollProvisioningStatus);
    on<_FinalizeProvisioning>(_onFinalizeProvisioning);
  }

  Future<void> _onConnectToPort(ConnectToPort event, Emitter<ProvisionerState> emit) async {
    emit(state.copyWith(connectionStatus: ConnectionStatus.connecting));

    try {
      // Connect to serial port
      await _serialService.connect(event.port.portName);

      // Set up command processor
      _processor = CommandProcessor(_serialService.dataStream);

      // Set up mesh command service
      _meshService = MeshCommandService(
        sendData: _serialService.sendData,
        processor: _processor!,
      );

      // Listen to serial connection status
      _serialStatusSubscription = _serialService.statusStream.listen((status) {
        if (status == SerialConnectionStatus.disconnected ||
            status == SerialConnectionStatus.error) {
          add(Disconnect());
        }
      });

      // Forward processed lines to the bloc as events so state updates happen
      // within an event handler. This avoids calling `emit` after this handler
      // has completed, which would trigger a BLoC assertion.
      _processedLineSubscription = _processor!.lineStream.listen((line) {
        add(_ProcessedLineReceived(line));
      });

      // Listen for node discoveries
      _nodeFoundSubscription = _meshService!.nodeFoundStream.listen((uuid) {
        add(NodeDiscovered(uuid));
      });

      emit(state.copyWith(
        connectionStatus: ConnectionStatus.connected,
        connectedPort: event.port,
      ));

      // Initial scan
      add(ScanDevices());
      add(RefreshDeviceList());

      // Start periodic device list polling
      _deviceListTimer?.cancel();
      _deviceListTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => add(RefreshDeviceList()),
      );

    } catch (e) {
      emit(state.copyWith(
        connectionStatus: ConnectionStatus.error,
        currentError: AppError(
          message: 'Connection failed: $e',
          severity: ErrorSeverity.error,
        ),
      ));
    }
  }

  Future<void> _onDisconnect(Disconnect event, Emitter<ProvisionerState> emit) async {
    _serialStatusSubscription?.cancel();
    _processedLineSubscription?.cancel();
    _nodeFoundSubscription?.cancel();
    _provisioningTimer?.cancel();
    _deviceListTimer?.cancel();

    _meshService?.dispose();
    _processor?.dispose();
    await _serialService.disconnect();

    _knownDeviceAddresses.clear();

    emit(ProvisionerState());
  }

  Future<void> _onScanDevices(ScanDevices event, Emitter<ProvisionerState> emit) async {
    if (state.connectionStatus != ConnectionStatus.connected || _meshService == null) return;

    emit(state.copyWith(
      isScanning: true,
      currentAction: ActionExecution(action: 'Device scan'),
    ));

    try {
      final uuids = await _meshService!.scanForDevices();
      final updatedUuids = Set<String>.from(state.foundUuids)..addAll(uuids);

      emit(state.copyWith(
        foundUuids: updatedUuids,
        isScanning: false,
      ));

      _addActionResult('Device scan', true, 'Found ${uuids.length} devices', emit);
    } catch (e) {
      emit(state.copyWith(
        isScanning: false,
        currentError: AppError(message: 'Scan failed: $e'),
      ));
      _addActionResult('Device scan', false, e.toString(), emit);
    }
  }

  Future<void> _onRefreshDeviceList(RefreshDeviceList event, Emitter<ProvisionerState> emit) async {
    if (_meshService == null) return;

    try {
      final fetched = await _meshService!.getProvisionedDevices();
      final adjusted = <MeshDevice>[];
      for (var device in fetched) {
        if (!_knownDeviceAddresses.contains(device.address)) {
          _knownDeviceAddresses.add(device.address);
          if (device.timeSinceLastHb == null || device.timeSinceLastHb! < 0) {
            device = device.copyWith(timeSinceLastHb: 0);
          }
        }
        adjusted.add(device);
      }

      emit(state.copyWith(provisionedDevices: adjusted));
    } catch (e) {
      emit(state.copyWith(
        currentError: AppError(message: 'Failed to refresh devices: $e'),
      ));
    }
  }

  Future<void> _onProvisionDevice(ProvisionDevice event, Emitter<ProvisionerState> emit) async {
    if (state.isProvisioning || _meshService == null) return;

    emit(state.copyWith(
      isProvisioning: true,
      provisioningStatus: 'Starting provisioning...',
      provisioningUuid: event.uuid,
      currentAction: ActionExecution(action: 'Provision device'),
    ));

    try {
      final success = await _meshService!.provisionDevice(event.uuid);

      if (!success) {
        // Check if device is already provisioned
        final devices = await _meshService!.getProvisionedDevices();
        final isAlreadyProvisioned = devices.any((d) => d.uuid == event.uuid);

        if (isAlreadyProvisioned) {
          emit(state.copyWith(
            isProvisioning: false,
            provisioningUuid: null,
            currentError: AppError(
              message: 'Device is already provisioned. Use Factory Reset to clear the database.',
              severity: ErrorSeverity.warning,
            ),
          ));
          _addActionResult('Provision device', false, 'Already provisioned', emit);
          return;
        }

        emit(state.copyWith(
          isProvisioning: false,
          provisioningUuid: null,
          currentError: AppError(message: 'Failed to start provisioning'),
        ));
        _addActionResult('Provision device', false, 'Failed to start', emit);
        return;
      }

      // Start polling for provisioning status until the process completes.
      _startProvisioningPolling(event.uuid);
    } catch (e) {
      emit(state.copyWith(
        isProvisioning: false,
        provisioningUuid: null,
        currentError: AppError(message: 'Provisioning error: $e'),
      ));
      _addActionResult('Provision device', false, e.toString(), emit);
    }
  }

  Future<void> _onUnprovisionDevice(UnprovisionDevice event, Emitter<ProvisionerState> emit) async {
    if (_meshService == null) return;

    emit(state.copyWith(
      currentAction: ActionExecution(
        action: 'Unprovision device ${event.device.addressHex}',
      ),
    ));

    try {
      final success = await _meshService!.resetDevice(event.device.address);
      if (success) {
        add(RefreshDeviceList());
        _knownDeviceAddresses.remove(event.device.address);
        if (state.selectedDevice?.address == event.device.address) {
          emit(state.copyWith(selectedDevice: null));
        }
        _addActionResult('Unprovision device ${event.device.addressHex}', true, null, emit);
      } else {
        emit(state.copyWith(
          currentError: AppError(message: 'Failed to reset device'),
        ));
        _addActionResult('Unprovision device ${event.device.addressHex}', false, null, emit);
      }
    } catch (e) {
      emit(state.copyWith(
        currentError: AppError(message: 'Reset error: $e'),
      ));
      _addActionResult('Unprovision device ${event.device.addressHex}', false, e.toString(), emit);
    }
  }

  Future<void> _onRemoveDeviceFromDb(RemoveDeviceFromDb event, Emitter<ProvisionerState> emit) async {
    if (_meshService == null) return;

    emit(state.copyWith(
      currentAction: ActionExecution(
        action: 'Remove device ${event.device.addressHex}',
      ),
    ));

    try {
      final success = await _meshService!.removeDevice(event.device.address);
      if (success) {
        add(RefreshDeviceList());
        _knownDeviceAddresses.remove(event.device.address);
        if (state.selectedDevice?.address == event.device.address) {
          emit(state.copyWith(selectedDevice: null));
        }
        _addActionResult('Remove device ${event.device.addressHex}', true, null, emit);
      } else {
        emit(state.copyWith(
          currentError: AppError(message: 'Failed to remove device'),
        ));
        _addActionResult('Remove device ${event.device.addressHex}', false, null, emit);
      }
    } catch (e) {
      emit(state.copyWith(
        currentError: AppError(message: 'Remove error: $e'),
      ));
      _addActionResult('Remove device ${event.device.addressHex}', false, e.toString(), emit);
    }
  }

  Future<void> _onAddSubscription(AddSubscription event, Emitter<ProvisionerState> emit) async {
    if (_meshService == null) return;

    emit(state.copyWith(
      currentAction: ActionExecution(
        action: 'Add subscription 0x${event.groupAddress.toRadixString(16)}',
      ),
    ));

    try {
      final success = await _meshService!.addSubscription(event.nodeAddress, event.groupAddress);
      if (success && state.selectedDevice?.address == event.nodeAddress) {
        await _loadDeviceSubscriptions(event.nodeAddress, emit);
        _addActionResult(
          'Add subscription 0x${event.groupAddress.toRadixString(16)}',
          true,
          null,
          emit,
        );
      } else {
        emit(state.copyWith(
          currentError: AppError(message: 'Failed to add subscription'),
        ));
        _addActionResult(
          'Add subscription 0x${event.groupAddress.toRadixString(16)}',
          false,
          null,
          emit,
        );
      }
    } catch (e) {
      emit(state.copyWith(
        currentError: AppError(message: 'Error: $e'),
      ));
      _addActionResult(
        'Add subscription 0x${event.groupAddress.toRadixString(16)}',
        false,
        e.toString(),
        emit,
      );
    }
  }

  Future<void> _onRemoveSubscription(RemoveSubscription event, Emitter<ProvisionerState> emit) async {
    if (_meshService == null) return;

    emit(state.copyWith(
      currentAction: ActionExecution(
        action: 'Remove subscription 0x${event.groupAddress.toRadixString(16)}',
      ),
    ));

    try {
      final success = await _meshService!.removeSubscription(event.nodeAddress, event.groupAddress);
      if (success && state.selectedDevice?.address == event.nodeAddress) {
        await _loadDeviceSubscriptions(event.nodeAddress, emit);
        _addActionResult(
          'Remove subscription 0x${event.groupAddress.toRadixString(16)}',
          true,
          null,
          emit,
        );
      } else {
        emit(state.copyWith(
          currentError: AppError(message: 'Failed to remove subscription'),
        ));
        _addActionResult(
          'Remove subscription 0x${event.groupAddress.toRadixString(16)}',
          false,
          null,
          emit,
        );
      }
    } catch (e) {
      emit(state.copyWith(
        currentError: AppError(message: 'Error: $e'),
      ));
      _addActionResult(
        'Remove subscription 0x${event.groupAddress.toRadixString(16)}',
        false,
        e.toString(),
        emit,
      );
    }
  }

  Future<void> _onSelectDevice(SelectDevice event, Emitter<ProvisionerState> emit) async {
    emit(state.copyWith(selectedDevice: event.device));

    if (event.device != null && _meshService != null) {
      await _loadDeviceSubscriptions(event.device!.address, emit);
      await _loadDeviceDetails(event.device!.address, emit);
    }
  }

  Future<void> _loadDeviceSubscriptions(int address, Emitter<ProvisionerState> emit) async {
    try {
      final subscriptions = await _meshService!.getSubscriptions(address);
      emit(state.copyWith(selectedDeviceSubscriptions: subscriptions));
    } catch (e) {
      emit(state.copyWith(
        currentError: AppError(
          message: 'Failed to load subscriptions: $e',
          severity: ErrorSeverity.warning,
        ),
      ));
    }
  }

  Future<void> _loadDeviceDetails(int address, Emitter<ProvisionerState> emit) async {
    try {
      final idle = await _meshService!.getDaliIdleConfig(address);
      final trig = await _meshService!.getDaliTriggerConfig(address);
      final identify = await _meshService!.getDaliIdentifyTime(address);
      final override = await _meshService!.getDaliOverrideState(address);
      final radar = await _meshService!.getRadarConfig(address);

      final newDali = Map<int, DaliLcInfo>.from(state.daliInfo);
      if (idle != null && trig != null && identify != null && override != null) {
        newDali[address] = DaliLcInfo(
          idle: idle,
          trigger: trig,
          identifyRemaining: identify,
          override: override,
        );
      }

      final newRadar = Map<int, RadarInfo>.from(state.radarInfo);
      if (radar != null) newRadar[address] = radar;

      emit(state.copyWith(daliInfo: newDali, radarInfo: newRadar));
    } catch (e) {
      emit(state.copyWith(
        currentError: AppError(
          message: 'Failed to load device details: $e',
          severity: ErrorSeverity.warning,
        ),
      ));
    }
  }

  void _onClearError(ClearError event, Emitter<ProvisionerState> emit) {
    emit(state.copyWith(clearError: true));
  }
Future<void> _onSendConsoleCommand(SendConsoleCommand event, Emitter<ProvisionerState> emit) async {
    if (_meshService == null) return;

    // Add command to console entries
    final entries = List<ConsoleEntry>.from(state.consoleEntries);
    entries.add(ConsoleEntry(
      text: event.command,
      type: ConsoleEntryType.command,
      timestamp: DateTime.now(),
    ));

    // Keep only last 1000 entries
    if (entries.length > 1000) {
      entries.removeRange(0, entries.length - 1000);
    }

    emit(state.copyWith(consoleEntries: entries));

    try {
      // Send the command via mesh service
      await _meshService!.sendCommand(event.command);
    } catch (e) {
      // Add error to console
      final errorEntries = List<ConsoleEntry>.from(state.consoleEntries);
      errorEntries.add(ConsoleEntry(
        text: 'Error sending command: $e',
        type: ConsoleEntryType.error,
        timestamp: DateTime.now(),
      ));

      emit(state.copyWith(
        consoleEntries: errorEntries,
        currentError: AppError(
          message: 'Failed to send command: $e',
          severity: ErrorSeverity.error,
        ),
      ));
    }
  }
  void _onNodeDiscovered(NodeDiscovered event, Emitter<ProvisionerState> emit) {
    final updated = Set<String>.from(state.foundUuids)..add(event.uuid);
    emit(state.copyWith(foundUuids: updated));
  }

void _onProcessedLineReceived(_ProcessedLineReceived event, Emitter<ProvisionerState> emit) {
  final entries = List<ConsoleEntry>.from(state.consoleEntries);
  entries.add(ConsoleEntry(
    text: event.line.raw,
    type: _getConsoleEntryType(event.line.type),
  ));

  // Parse responses for GET commands
  if (event.line.type == LineType.response && state.currentAction != null) {
    final command = state.currentAction!.action;
    final response = event.line.content;

    // Parse different response types
    if (command.contains('device/label/get') && !response.contains('error')) {
      // Store label response
      // You might want to add a field to state for storing these values
    } else if (command.contains('dali_lc/idle_cfg/get') && response.contains(',')) {
      // Parse idle config: arc,fade
      final parts = response.split(',');
      if (parts.length == 2) {
        // Store idle config
      }
    } else if (command.contains('dali_lc/trigger_cfg/get') && response.contains(',')) {
      // Parse trigger config: arc,fade_in,fade_out,hold_time
      final parts = response.split(',');
      if (parts.length == 4) {
        // Store trigger config
      }
    }
    // Add more parsing as needed...
  }

  // Check for provisioning messages that are pushed by the device itself
  _handleProvisioningNotification(event.line.content, emit);

  // Update current action log if active
  ActionExecution? current = state.currentAction;
  if (current != null) {
    final log = List<ConsoleEntry>.from(current.log)
      ..add(ConsoleEntry(
        text: event.line.raw,
        type: _getConsoleEntryType(event.line.type),
      ));
    current = current.copyWith(log: log);
  }

  // Keep only last 1000 entries
  if (entries.length > 1000) {
    entries.removeRange(0, entries.length - 1000);
  }

  emit(state.copyWith(consoleEntries: entries, currentAction: current));
}

  /// Begin polling of the provisioning status. Any existing polling timer is
  /// cancelled before a new one is created. The polling continues until the
  /// device reports that provisioning has completed or failed.
  void _startProvisioningPolling(String uuid) {
    _provisioningTimer?.cancel();
    _provisioningTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => add(_PollProvisioningStatus(uuid)),
    );
  }

  Future<void> _onPollProvisioningStatus(
      _PollProvisioningStatus event, Emitter<ProvisionerState> emit) async {
    if (!state.isProvisioning) {
      _provisioningTimer?.cancel();
      return;
    }

    final status = await _meshService!.getProvisioningStatus();
    emit(state.copyWith(provisioningStatus: status));

    if (status.contains('completed') ||
        status.contains('failed') ||
        status.contains('timeout')) {
      add(_FinalizeProvisioning(event.uuid));
    }
  }

  Future<void> _onFinalizeProvisioning(
      _FinalizeProvisioning event, Emitter<ProvisionerState> emit) async {
    await _finalizeProvisioning(event.uuid, emit);
  }

  /// Handle the finalisation of a provisioning task once the device reports
  /// completion or failure.
  Future<void> _finalizeProvisioning(String uuid, Emitter<ProvisionerState> emit) async {
    _provisioningTimer?.cancel();

    final result = await _meshService!.getProvisioningResult();
    if (result == 0) {
      final updatedUuids = Set<String>.from(state.foundUuids)..remove(uuid);
      emit(state.copyWith(
        foundUuids: updatedUuids,
        isProvisioning: false,
        provisioningUuid: null,
      ));

      add(RefreshDeviceList());
      _addActionResult('Provision device', true, 'Device provisioned successfully', emit);
    } else {
      emit(state.copyWith(
        isProvisioning: false,
        provisioningUuid: null,
        currentError: AppError(message: 'Provisioning failed with error: $result'),
      ));
      _addActionResult('Provision device', false, 'Error code: $result', emit);
    }
  }

  /// Update provisioning status based on a line pushed by the provisioner.
  /// If the line indicates completion or failure, the provisioning workflow is
  /// finalised immediately without waiting for the polling timer.
  void _handleProvisioningNotification(String line, Emitter<ProvisionerState> emit) {
    if (!state.isProvisioning) return;

    final lower = line.toLowerCase();
    if (lower.contains('provisioning')) {
      emit(state.copyWith(provisioningStatus: line));

      if (lower.contains('completed') || lower.contains('failed') || lower.contains('timeout')) {
        final uuid = state.provisioningUuid;
        if (uuid != null) {
          add(_FinalizeProvisioning(uuid));
        }
      }
    }
  }

  ConsoleEntryType _getConsoleEntryType(LineType lineType) {
    switch (lineType) {
      case LineType.error:
        return ConsoleEntryType.error;
      case LineType.warning:
      case LineType.info:
      case LineType.nodeFound:
        return ConsoleEntryType.info;
      default:
        return ConsoleEntryType.response;
    }
  }

  void _addActionResult(String action, bool success, String? message, Emitter<ProvisionerState> emit) {
    final history = List<ActionResult>.from(state.actionHistory);
    final current = state.currentAction;
    history.add(ActionResult(
      action: action,
      success: success,
      message: message,
      log: current?.log ?? [],
      timestamp: current?.timestamp ?? DateTime.now(),
    ));

    // Keep only last 100 actions
    if (history.length > 100) {
      history.removeRange(0, history.length - 100);
    }

    emit(state.copyWith(actionHistory: history, currentAction: null));
  }

  @override
  Future<void> close() {
    _serialStatusSubscription?.cancel();
    _processedLineSubscription?.cancel();
    _nodeFoundSubscription?.cancel();
    _provisioningTimer?.cancel();
    _deviceListTimer?.cancel();

    _meshService?.dispose();
    _processor?.dispose();
    _serialService.dispose();

    return super.close();
  }
}
