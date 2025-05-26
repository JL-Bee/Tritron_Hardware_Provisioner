#!/usr/bin/env python3
"""
Bluetooth-Mesh Provisioner GUI
Sequential “auto-provision” workflow included
Author : Johannes  (May 2025)

Quick install
-------------
    pip install pyqt5 pyserial
"""

import re
import sys
import time
import serial
import serial.tools.list_ports
from PyQt5.QtCore import QThread, pyqtSignal, QObject
from PyQt5.QtWidgets import (
    QApplication, QWidget, QVBoxLayout, QHBoxLayout,
    QComboBox, QPushButton, QLabel, QLineEdit, QListWidget,
    QTextEdit, QMessageBox
)

# ──────────────────────────────────────────────────────────────
# Serial worker (RX in background)
# ──────────────────────────────────────────────────────────────
class SerialThread(QThread):
    output_received = pyqtSignal(str)

    def __init__(self, port: str, baud: int = 115200):
        super().__init__()
        self._port = port
        self._baud = baud
        self._ser = None
        self._run = True

    def run(self):
        try:
            self._ser = serial.Serial(self._port, self._baud, timeout=0.2)
            while self._run:
                if self._ser.in_waiting:
                    data = self._ser.read(self._ser.in_waiting).decode(errors="replace")
                    self.output_received.emit(data)
        except Exception as exc:
            self.output_received.emit(f"[Serial-Error] {exc}")

    def stop(self):
        self._run = False
        if self._ser and self._ser.is_open:
            self._ser.close()

    def write(self, line: str):
        if self._ser and self._ser.is_open:
            self._ser.write((line.strip() + "\r\n").encode())


# ──────────────────────────────────────────────────────────────
# Sequential automation thread
# ──────────────────────────────────────────────────────────────
class SequenceThread(QThread):
    info = pyqtSignal(str)        # progress to GUI
    finished_ok = pyqtSignal()
    finished_err = pyqtSignal(str)

    def __init__(self, serial_thr: SerialThread, gui_ref: QObject):
        super().__init__()
        self.ser = serial_thr
        self.gui = gui_ref
        self._buf = ""
        self.ser.output_received.connect(self._capture)

    # collect incoming serial text
    def _capture(self, chunk: str):
        self._buf += chunk

    # helper – write & wait
    def _send(self, cmd: str, sleep_s: float = 1.0):
        self.info.emit(f"> {cmd}")
        self.ser.write(cmd)
        time.sleep(sleep_s)

    # extract first 32-char hex UUID from internal buffer
    def _first_uuid(self):
        m = re.search(r"\b[0-9a-fA-F]{32}\b", self._buf)
        return m.group(0) if m else None

    # extract first 4-hex-digit address (0x1234 style)
    def _first_addr(self):
        m = re.search(r"0x[0-9a-fA-F]{4}", self._buf)
        return m.group(0) if m else None

    # main workflow
    def run(self):
        try:
            # clear buffer
            self._buf = ""

            # 1) scan
            self._send("mesh/provision/scan/get", 2.0)
            uuid = self._first_uuid()
            if not uuid:
                raise RuntimeError("No UUID found during scan.")
            self.info.emit(f"[scan] first UUID = {uuid}")

            # 2) provision first result
            self._buf = ""
            self._send(f"mesh/provision/provision {uuid}", 3.0)

            # 3-4-5) result / status / last-addr
            self._send("mesh/provision/result/get")
            self._send("mesh/provision/status/get")
            self._send("mesh/provision/last_addr/get", 1.5)
            addr = self._first_addr()
            if not addr:
                raise RuntimeError("No node address reported.")
            self.info.emit(f"[provision] node addr = {addr}")

            # 6) run all device commands, ending with reset
            self._send("mesh/device/list")
            self._send(f"mesh/device/label/get {addr}")
            self._send(f"mesh/device/sub/get {addr}")
            self._send(f"mesh/device/reset {addr}")

            self.finished_ok.emit()
        except Exception as exc:
            self.finished_err.emit(str(exc))


# ──────────────────────────────────────────────────────────────
# Main GUI
# ──────────────────────────────────────────────────────────────
class MeshGUI(QWidget):
    CMDS = [
        "provision/scan/get",
        "provision/provision",
        "provision/result/get",
        "provision/status/get",
        "provision/last_addr/get",
        "device/list",
        "device/remove",
        "device/reset",
        "device/label/get",
        "device/label/set",
        "device/sub/add",
        "device/sub/remove",
        "device/sub/reset",
        "device/sub/get",
    ]

    def __init__(self):
        super().__init__()
        self.setWindowTitle("Bluetooth-Mesh Provisioner")
        self.resize(900, 620)
        self._build_ui()
        self.refresh_ports()
        self.update_param_fields()
        self.ser_thr = None
        self.seq_thr = None

    # ───────────────────────── UI
    def _build_ui(self):
        # widgets
        self.cb_port = QComboBox()
        self.btn_port_refresh = QPushButton("Refresh")
        self.btn_connect = QPushButton("Connect")
        self.btn_connect.setCheckable(True)
        self.lbl_status = QLabel("Disconnected")

        self.cb_cmd = QComboBox(); self.cb_cmd.addItems(self.CMDS)
        self.lbl_p1 = QLabel("Param1:"); self.edit_p1 = QLineEdit()
        self.lbl_p2 = QLabel("Param2:"); self.edit_p2 = QLineEdit()

        self.lbl_scan = QLabel("Scan results (UUID):")
        self.list_uuid = QListWidget(); self.list_uuid.setFixedHeight(110)

        self.text_out = QTextEdit(); self.text_out.setReadOnly(True)
        self.text_out.setLineWrapMode(QTextEdit.NoWrap)

        self.btn_exec = QPushButton("Execute")
        self.btn_copy = QPushButton("Copy")
        self.btn_auto = QPushButton("Auto-Provision Seq")

        # layout
        v = QVBoxLayout()
        h1 = QHBoxLayout()
        h1.addWidget(QLabel("COM:")); h1.addWidget(self.cb_port)
        h1.addWidget(self.btn_port_refresh); h1.addWidget(self.btn_connect)
        h1.addWidget(self.lbl_status); v.addLayout(h1)

        h2 = QHBoxLayout()
        h2.addWidget(QLabel("Command:")); h2.addWidget(self.cb_cmd, 1)
        h2.addWidget(self.lbl_p1); h2.addWidget(self.edit_p1)
        h2.addWidget(self.lbl_p2); h2.addWidget(self.edit_p2)
        h2.addWidget(self.btn_exec); v.addLayout(h2)

        v.addWidget(self.btn_auto)
        v.addWidget(self.lbl_scan); v.addWidget(self.list_uuid)
        v.addWidget(self.text_out); v.addWidget(self.btn_copy)
        self.setLayout(v)

        # vis
        self._toggle_params(False, False); self._toggle_scan(False)

        # signals
        self.btn_port_refresh.clicked.connect(self.refresh_ports)
        self.btn_connect.clicked.connect(self.toggle_connection)
        self.cb_cmd.currentIndexChanged.connect(self.update_param_fields)
        self.btn_exec.clicked.connect(self.manual_execute)
        self.btn_copy.clicked.connect(self.copy_output)
        self.list_uuid.itemDoubleClicked.connect(self.uuid_clicked)
        self.btn_auto.clicked.connect(self.start_sequence)

    # ───────────────────────── helpers
    def refresh_ports(self):
        self.cb_port.clear()
        self.cb_port.addItems([p.device for p in serial.tools.list_ports.comports()])

    def toggle_connection(self):
        if self.btn_connect.isChecked():  # connect
            port = self.cb_port.currentText()
            if not port:
                QMessageBox.warning(self, "COM", "Select a port.")
                self.btn_connect.setChecked(False)
                return
            self.ser_thr = SerialThread(port)
            self.ser_thr.output_received.connect(self.serial_rx)
            self.ser_thr.start()
            self.lbl_status.setText(f"Connected ({port})")
            self.btn_connect.setText("Disconnect")
        else:  # disconnect
            if self.seq_thr:
                QMessageBox.warning(self, "Busy", "Stop auto-sequence first.")
                self.btn_connect.setChecked(True)
                return
            if self.ser_thr:
                self.ser_thr.stop(); self.ser_thr = None
            self.lbl_status.setText("Disconnected")
            self.btn_connect.setText("Connect")

    def _toggle_params(self, p1: bool, p2: bool):
        self.lbl_p1.setVisible(p1); self.edit_p1.setVisible(p1)
        self.lbl_p2.setVisible(p2); self.edit_p2.setVisible(p2)

    def _toggle_scan(self, show: bool):
        self.lbl_scan.setVisible(show); self.list_uuid.setVisible(show)

    def update_param_fields(self):
        cmd = self.cb_cmd.currentText()
        self.edit_p1.clear(); self.edit_p2.clear()
        self._toggle_scan(cmd == "provision/scan/get")
        if cmd == "provision/provision":
            self.lbl_p1.setText("UUID"); self._toggle_params(True, False)
        elif cmd in ("device/remove", "device/reset", "device/label/get", "device/sub/get"):
            self.lbl_p1.setText("Node addr"); self._toggle_params(True, False)
        elif cmd == "device/label/set":
            self.lbl_p1.setText("Node addr"); self.lbl_p2.setText("Label")
            self._toggle_params(True, True)
        elif cmd in ("device/sub/add", "device/sub/remove"):
            self.lbl_p1.setText("Node addr"); self.lbl_p2.setText("Group")
            self._toggle_params(True, True)
        else:
            self._toggle_params(False, False)

    # manual single command
    def manual_execute(self):
        if not self.ser_thr:
            QMessageBox.warning(self, "Serial", "Not connected.")
            return
        cmd = self.cb_cmd.currentText()
        params = []
        if self.edit_p1.isVisible():
            p1 = self.edit_p1.text().strip(); params.append(p1)
            if not p1:
                QMessageBox.warning(self, "Input", "Param1 missing."); return
        if self.edit_p2.isVisible():
            p2 = self.edit_p2.text().strip(); params.append(p2)
            if not p2:
                QMessageBox.warning(self, "Input", "Param2 missing."); return
        line = f"mesh/{cmd}" + ((" " + " ".join(params)) if params else "")
        self.serial_tx(line)

    # universal TX
    def serial_tx(self, line: str):
        self.text_out.append(f"\n> {line}")
        if self.ser_thr: self.ser_thr.write(line)

    # RX handler
    def serial_rx(self, chunk: str):
        self.text_out.moveCursor(self.text_out.textCursor().End)
        self.text_out.insertPlainText(chunk)
        self.text_out.moveCursor(self.text_out.textCursor().End)
        # capture UUIDs if scanning
        if self.cb_cmd.currentText() == "provision/scan/get":
            for line in chunk.splitlines():
                line = line.strip()
                if re.fullmatch(r"[0-9a-fA-F]{32}", line):
                    if line not in [self.list_uuid.item(i).text() for i in range(self.list_uuid.count())]:
                        self.list_uuid.addItem(line)

    def uuid_clicked(self, item):
        self.cb_cmd.setCurrentText("provision/provision")
        self.edit_p1.setText(item.text())

    def copy_output(self):
        self.text_out.selectAll(); self.text_out.copy()

    # ───────────────────────── sequential automation
    def start_sequence(self):
        if not self.ser_thr:
            QMessageBox.warning(self, "Serial", "Connect first.")
            return
        if self.seq_thr:
            QMessageBox.warning(self, "Busy", "Sequence already running.")
            return
        self.seq_thr = SequenceThread(self.ser_thr, self)
        self.seq_thr.info.connect(lambda s: self.serial_tx(s))
        self.seq_thr.finished_ok.connect(self.seq_done)
        self.seq_thr.finished_err.connect(self.seq_error)
        self.seq_thr.start()
        self.btn_auto.setEnabled(False)

    def seq_done(self):
        self.serial_tx("[sequence] complete ✓")
        self._cleanup_seq()

    def seq_error(self, msg):
        self.serial_tx(f"[sequence] ERROR – {msg}")
        self._cleanup_seq()

    def _cleanup_seq(self):
        self.btn_auto.setEnabled(True)
        self.seq_thr = None

    # graceful exit
    def closeEvent(self, e):
        if self.seq_thr:
            QMessageBox.information(self, "Quit", "Stop sequence first.")
            e.ignore(); return
        if self.ser_thr: self.ser_thr.stop()
        e.accept()


# ──────────────────────────────────────────────────────────────
# entry point
# ──────────────────────────────────────────────────────────────
if __name__ == "__main__":
    app = QApplication(sys.argv)
    gui = MeshGUI()
    gui.show()
    sys.exit(app.exec_())
