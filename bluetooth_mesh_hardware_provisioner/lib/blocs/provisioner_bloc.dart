// lib/blocs/provisioner_bloc.dart

import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:async';
import '../models/serial_port_info.dart';
import '../services/serial_port_service.dart';
import '../services/rtm_console_service.dart';
import '../protocols/rtm_console_protocol.dart';

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

class AddConsoleEntry extends ProvisionerEvent {
  final String text;
  final ConsoleEntryType type;
  AddConsoleEntry(this.text, this.type);
}

// States
class ProvisionerState {
  final ConnectionStatus connectionStatus;
  final SerialPortInfo? connectedPort;
  final Set<String> foundUuids;
  final List<MeshDevice> provisionedDevices;
  final MeshDevice? selectedDevice;
  final List<int> selectedDeviceSubscriptions;
  final bool isScanning;
  final bool isProvisioning;
  final String provisioningStatus;
  final List<ConsoleEntry> consoleEntries;
  final AppError? currentError;
  final List<ActionResult> actionHistory;

  ProvisionerState({
    this.connectionStatus = ConnectionStatus.disconnected,
    this.connectedPort,
    Set<String>? foundUuids,
    List<MeshDevice>? provisionedDevices,
    this.selectedDevice,
    List<int>? selectedDeviceSubscriptions,
    this.isScanning = false,
    this.isProvisioning = false,
    this.provisioningStatus = '',
    List<ConsoleEntry>? consoleEntries,
    this.currentError,
    List<ActionResult>? actionHistory,
  })  : foundUuids = foundUuids ?? {},
        provisionedDevices = provisionedDevices ?? [],
        selectedDeviceSubscriptions = selectedDeviceSubscriptions ?? [],
        consoleEntries = consoleEntries ?? [],
        actionHistory = actionHistory ?? [];

  ProvisionerState copyWith({
    ConnectionStatus? connectionStatus,
    SerialPortInfo? connectedPort,
    Set<String>? foundUuids,
    List<MeshDevice>? provisionedDevices,
    MeshDevice? selectedDevice,
    List<int>? selectedDeviceSubscriptions,
    bool? isScanning,
    bool? isProvisioning,
    String? provisioningStatus,
    List<ConsoleEntry>? consoleEntries,
    AppError? currentError,
    bool clearError = false,
    List<ActionResult>? actionHistory,
  }) {
    return ProvisionerState(
      connectionStatus: connectionStatus ?? this.connectionStatus,
      connectedPort: connectedPort ?? this.connectedPort,
      foundUuids: foundUuids ?? this.foundUuids,
      provisionedDevices: provisionedDevices ?? this.provisionedDevices,
      selectedDevice: selectedDevice ?? this.selectedDevice,
      selectedDeviceSubscriptions: selectedDeviceSubscriptions ?? this.selectedDeviceSubscriptions,
      isScanning: isScanning ?? this.isScanning,
      isProvisioning: isProvisioning ?? this.isProvisioning,
      provisioningStatus: provisioningStatus ?? this.provisioningStatus,
      consoleEntries: consoleEntries ?? this.consoleEntries,
      currentError: clearError ? null : (currentError ?? this.currentError),
      actionHistory: actionHistory ?? this.actionHistory,
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

  ConsoleEntry({
    required this.text,
    required this.type,
    DateTime? timestamp,
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
  final DateTime timestamp;

  ActionResult({
    required this.action,
    required this.success,
    this.message,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

// BLoC Implementation
class ProvisionerBloc extends Bloc<ProvisionerEvent, ProvisionerState> {
  final SerialPortService _serialService = SerialPortService();
  RTMConsoleService? _consoleService;
  StreamSubscription? _dataSubscription;
  StreamSubscription? _nodeFoundSubscription;
  Timer? _provisioningTimer;

  ProvisionerBloc() : super(ProvisionerState()) {
    on<ConnectToPort>(_onConnectToPort);
    on<Disconnect>(_onDisconnect);
    on<ScanDevices>(_onScanDevices);
    on<RefreshDeviceList>(_onRefreshDeviceList);
    on<ProvisionDevice>(_onProvisionDevice);
    on<UnprovisionDevice>(_onUnprovisionDevice);
    on<AddSubscription>(_onAddSubscription);
    on<RemoveSubscription>(_onRemoveSubscription);
    on<SelectDevice>(_onSelectDevice);
    on<ClearError>(_onClearError);
    on<AddConsoleEntry>(_onAddConsoleEntry);
  }

  Future<void> _onConnectToPort(ConnectToPort event, Emitter<ProvisionerState> emit) async {
    emit(state.copyWith(connectionStatus: ConnectionStatus.connecting));

    try {
      await _serialService.connect(event.port.portName);

      _consoleService = RTMConsoleService(
        sendCommand: (cmd) async {
          await _serialService.sendCommand(cmd);
          add(AddConsoleEntry(cmd.trim(), ConsoleEntryType.command));
        },
        dataStream: _serialService.dataStream,
      );

      // Listen to raw data for console
      _dataSubscription = _serialService.dataStream.listen((data) {
        add(AddConsoleEntry(data.trim(), ConsoleEntryType.response));
      });

      // Listen for new nodes
      _nodeFoundSubscription = _consoleService!.nodeFoundStream.listen((uuid) {
        final updatedUuids = Set<String>.from(state.foundUuids)..add(uuid);
        emit(state.copyWith(foundUuids: updatedUuids));
      });

      emit(state.copyWith(
        connectionStatus: ConnectionStatus.connected,
        connectedPort: event.port,
      ));

      // Initial scan
      add(ScanDevices());
      add(RefreshDeviceList());

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
    _dataSubscription?.cancel();
    _nodeFoundSubscription?.cancel();
    _provisioningTimer?.cancel();
    _consoleService?.dispose();
    await _serialService.disconnect();

    emit(ProvisionerState());
  }

  Future<void> _onScanDevices(ScanDevices event, Emitter<ProvisionerState> emit) async {
    if (state.connectionStatus != ConnectionStatus.connected || _consoleService == null) return;

    emit(state.copyWith(isScanning: true));

    try {
      final uuids = await _consoleService!.scanDevices();
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
    if (_consoleService == null) return;

    try {
      final devices = await _consoleService!.listDevices();
      emit(state.copyWith(provisionedDevices: devices));
    } catch (e) {
      emit(state.copyWith(
        currentError: AppError(message: 'Failed to refresh devices: $e'),
      ));
    }
  }

  Future<void> _onProvisionDevice(ProvisionDevice event, Emitter<ProvisionerState> emit) async {
    if (state.isProvisioning || _consoleService == null) return;

    emit(state.copyWith(
      isProvisioning: true,
      provisioningStatus: 'Starting provisioning...',
    ));

    try {
      final success = await _consoleService!.provisionDevice(event.uuid);

      if (success) {
        _provisioningTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
          if (!state.isProvisioning) {
            timer.cancel();
            return;
          }

          final status = await _consoleService!.getProvisionStatus();
          emit(state.copyWith(provisioningStatus: status));

          if (status.contains('completed') || status.contains('failed')) {
            timer.cancel();

            final result = await _consoleService!.getProvisionResult();
            if (result == 0) {
              final updatedUuids = Set<String>.from(state.foundUuids)..remove(event.uuid);
              emit(state.copyWith(
                foundUuids: updatedUuids,
                isProvisioning: false,
              ));

              add(RefreshDeviceList());
              _addActionResult('Provision device', true, 'Device provisioned successfully', emit);
            } else {
              emit(state.copyWith(
                isProvisioning: false,
                currentError: AppError(message: 'Provisioning failed with error: $result'),
              ));
              _addActionResult('Provision device', false, 'Error code: $result', emit);
            }
          }
        });
      } else {
        emit(state.copyWith(
          isProvisioning: false,
          currentError: AppError(message: 'Failed to start provisioning'),
        ));
        _addActionResult('Provision device', false, 'Failed to start', emit);
      }
    } catch (e) {
      emit(state.copyWith(
        isProvisioning: false,
        currentError: AppError(message: 'Provisioning error: $e'),
      ));
      _addActionResult('Provision device', false, e.toString(), emit);
    }
  }

  Future<void> _onUnprovisionDevice(UnprovisionDevice event, Emitter<ProvisionerState> emit) async {
    if (_consoleService == null) return;

    try {
      final success = await _consoleService!.resetDevice(event.device.address);
      if (success) {
        add(RefreshDeviceList());
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

  Future<void> _onAddSubscription(AddSubscription event, Emitter<ProvisionerState> emit) async {
    if (_consoleService == null) return;

    try {
      final success = await _consoleService!.addSubscribe(event.nodeAddress, event.groupAddress);
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
    if (_consoleService == null) return;

    try {
      final success = await _consoleService!.removeSubscribe(event.nodeAddress, event.groupAddress);
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

    if (event.device != null && _consoleService != null) {
      await _loadDeviceSubscriptions(event.device!.address, emit);
    }
  }

  Future<void> _loadDeviceSubscriptions(int address, Emitter<ProvisionerState> emit) async {
    try {
      final subscriptions = await _consoleService!.getSubscribeAddresses(address);
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

  void _onClearError(ClearError event, Emitter<ProvisionerState> emit) {
    emit(state.copyWith(clearError: true));
  }

  void _onAddConsoleEntry(AddConsoleEntry event, Emitter<ProvisionerState> emit) {
    final entries = List<ConsoleEntry>.from(state.consoleEntries);
    entries.add(ConsoleEntry(text: event.text, type: event.type));

    // Keep only last 1000 entries
    if (entries.length > 1000) {
      entries.removeRange(0, entries.length - 1000);
    }

    emit(state.copyWith(consoleEntries: entries));
  }

  void _addActionResult(String action, bool success, String? message, Emitter<ProvisionerState> emit) {
    final history = List<ActionResult>.from(state.actionHistory);
    history.add(ActionResult(
      action: action,
      success: success,
      message: message,
    ));

    // Keep only last 100 actions
    if (history.length > 100) {
      history.removeRange(0, history.length - 100);
    }

    emit(state.copyWith(actionHistory: history));
  }

  @override
  Future<void> close() {
    _dataSubscription?.cancel();
    _nodeFoundSubscription?.cancel();
    _provisioningTimer?.cancel();
    _consoleService?.dispose();
    _serialService.dispose();
    return super.close();
  }
}
