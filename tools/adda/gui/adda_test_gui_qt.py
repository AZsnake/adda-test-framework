#!/usr/bin/env python3
"""adda_test_gui_qt.py — Modern Qt (PySide6 + pyqtgraph) ADDA board test tool.

Drop-in replacement for the Tkinter ``adda_test_gui.py`` with the same UART
feature set, but a modern plotting stack:

  * pyqtgraph plots with **native mouse pan (drag), scroll-wheel zoom**,
    right-click axis menu, a live **crosshair cursor** (MATLAB-style data tip),
    and a **draggable marker line** on the FFT.
  * Real-time streaming stays smooth — pyqtgraph only re-uploads the curve data
    instead of repainting an entire canvas.

The protocol layer (``rf_uart_client``) and the analysis layer
(``adc_analysis``) are reused unchanged.

Run:
    pip install -r tools/adda/requirements.txt
    python tools/adda/gui/adda_test_gui_qt.py
"""
from __future__ import annotations

import os
import queue
import re
import subprocess
import sys
import threading
import time
from collections import deque
from pathlib import Path

import numpy as np

try:
    import pyqtgraph as pg
    from PySide6 import QtCore, QtGui, QtWidgets
except ImportError as e:  # pragma: no cover - import guard
    sys.exit(
        "error: PySide6 / pyqtgraph not installed.\n"
        "  pip install PySide6 pyqtgraph\n"
        f"  ({e})"
    )

# Allow running both as a module and as a bare script from any CWD.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
import _bootstrap  # noqa: F401, E402

from rf_uart_client import (  # noqa: E402
    CHIP_AD9117,
    CHIP_AD9640,
    CHIP_SI5340,
    DAC_TONE_FREQ_HZ,
    DAC_WAVE_NAME_TO_CODE,
    DEFAULT_ADC_FS_HZ,
    DAC_WAVE_FS_HZ,
    MAX_SAMPLES,
    CAPTURE_MODE_SNAPSHOT,
    CAPTURE_MODE_STREAM,
    ADC_CHAN_I,
    ADC_CHAN_Q,
    RfAddaUart,
    dac_freq_word_to_hz,
    hz_to_dac_freq_word,
    enumerate_ports,
    normalize_com_port,
    pick_default_port,
    export_matlab_ifft_bin,
    decode_stream_iq_payload,
    samples_to_signed,
    samples_to_volts,
)
from adc_analysis import (  # noqa: E402
    iq_words_to_s14,
    DEFAULT_WINDOW,
    DEFAULT_DC_METHOD,
    DEFAULT_DC_MASK_BINS,
    DC_METHOD_CHOICES,
    DC_METHOD_KEY_TO_LABEL,
    DC_METHOD_LABEL_TO_KEY,
    WINDOW_CHOICES,
    WINDOW_KEY_TO_LABEL,
    WINDOW_LABEL_TO_KEY,
    compute_dynamic_metrics,
    compute_fft_spectrum,
    spectrum_summary,
)

APP_TITLE = "RF ADDA 综合测试 (Qt)"
DEFAULT_SAMPLES = 16384
MAX_TIME_PLOT_POINTS = 12000
MAX_FFT_PLOT_POINTS = 16000
DEC_RATIO_LABELS = ["1x", "2x", "4x"]
FIR_BANK_LABELS = ["Fs/8", "Fs/16", "CIC补偿", "全通"]  # 0x45 fir_sel 0..3
CAPTURE_MODE_LABELS = ["Snapshot", "Stream"]
_SPIN_UP_ARROW_URL = (Path(__file__).resolve().parent / "icons" / "spin_up.svg").as_posix()
_SPIN_DOWN_ARROW_URL = (Path(__file__).resolve().parent / "icons" / "spin_down.svg").as_posix()

_CAPTURE_CHART_LABELS: dict[str, str] = {
    "ADC 采集": "ADC capture",
    "环回测试": "Loopback test",
    "ADC 连续流": "ADC continuous stream",
}


def _chart_label(capture_label: str) -> str:
    return _CAPTURE_CHART_LABELS.get(capture_label, capture_label)


def _default_app_font() -> QtGui.QFont:
    """Pick a readable cross-platform UI font with robust CJK glyph coverage."""
    available = {f.casefold(): f for f in QtGui.QFontDatabase.families()}
    preferred = [
        # Windows
        "Microsoft YaHei UI",
        "Microsoft YaHei",
        # macOS
        "PingFang SC",
        "Hiragino Sans GB",
        # Linux/common CJK packs
        "Noto Sans CJK SC",
        "Noto Sans SC",
        "WenQuanYi Micro Hei",
        # Last resorts
        "Arial Unicode MS",
        "Sans Serif",
    ]
    for name in preferred:
        hit = available.get(name.casefold())
        if hit:
            return QtGui.QFont(hit, 10)
    return QtGui.QFont("Sans Serif", 10)


def _default_console_font(size: int = 9) -> QtGui.QFont:
    """Pick a monospace-first font with robust CJK fallback."""
    available = {f.casefold(): f for f in QtGui.QFontDatabase.families()}
    mono_preferred = [
        # Windows
        "Cascadia Mono",
        "Consolas",
        "Lucida Console",
        # macOS
        "Menlo",
        "Monaco",
        # Linux/common
        "DejaVu Sans Mono",
        "Noto Sans Mono",
        "Liberation Mono",
        # Generic fallback
        "Monospace",
    ]
    cjk_fallback = [
        "Microsoft YaHei UI",
        "Microsoft YaHei",
        "PingFang SC",
        "Hiragino Sans GB",
        "Noto Sans CJK SC",
        "Noto Sans SC",
        "WenQuanYi Micro Hei",
        "Arial Unicode MS",
    ]
    families: list[str] = []
    for name in mono_preferred + cjk_fallback:
        hit = available.get(name.casefold())
        if hit and hit not in families:
            families.append(hit)
    if not families:
        families = ["Monospace", "Sans Serif"]
    font = QtGui.QFont(families[0], size)
    font.setStyleHint(QtGui.QFont.StyleHint.Monospace, QtGui.QFont.StyleStrategy.PreferDefault)
    # Keep monospace preference, but let Qt fall back for missing CJK glyphs.
    font.setFamilies(families)
    return font


# label, ylabel, key, pen-color
FFT_MODE_OPTIONS: list[tuple[str, str, str, str]] = [
    ("dB", "magnitude (dB)", "db", "#2ca02c"),
    ("Magnitude", "magnitude (linear)", "linear", "#1f77b4"),
    ("Power %", "power (%)", "pct", "#ff7f0e"),
]
FFT_MODE_BY_KEY = {opt[2]: opt for opt in FFT_MODE_OPTIONS}

DAC_WAVE_CHOICES: list[tuple[str, str]] = [
    ("sine", "Sine"),
    ("square", "Square"),
    ("triangle", "Triangle"),
    ("ramp", "Ramp"),
    ("dc_test", "DC Test (I=1,Q=0)"),
]
DAC_WAVE_LABEL_TO_KEY = {label: key for key, label in DAC_WAVE_CHOICES}
DAC_WAVE_KEYS = [key for key, _ in DAC_WAVE_CHOICES]
DAC_WAVE_LABELS = [label for _, label in DAC_WAVE_CHOICES]

ANALYSIS_MODE_CHOICES: list[tuple[str, str]] = [
    ("i", "I路"),
    ("q", "Q路"),
    ("iq", "IQ并行"),
]
ANALYSIS_MODE_LABEL_TO_KEY = {label: key for key, label in ANALYSIS_MODE_CHOICES}
ANALYSIS_MODE_KEY_TO_LABEL = {key: label for key, label in ANALYSIS_MODE_CHOICES}
PLOT_ANALYSIS_MODE_LABELS = {"i": "I channel", "q": "Q channel", "iq": "IQ parallel"}

QUICK_SPI_DIR_CHOICES: list[tuple[str, str]] = [
    ("rx", "收(读)"),
    ("tx", "发(写)"),
]
QUICK_SPI_DIR_LABEL_TO_KEY = {label: key for key, label in QUICK_SPI_DIR_CHOICES}
QUICK_SPI_CHIP_CHOICES: list[tuple[int, str]] = [
    (CHIP_SI5340, "SI5340"),
    (CHIP_AD9640, "AD9640"),
    (CHIP_AD9117, "AD9117"),
]
QUICK_SPI_CHIP_LABEL_TO_ID = {label: chip for chip, label in QUICK_SPI_CHIP_CHOICES}


def _std(vals: list[float]) -> float:
    if len(vals) < 2:
        return 0.0
    m = sum(vals) / len(vals)
    return (sum((x - m) ** 2 for x in vals) / (len(vals) - 1)) ** 0.5


def _plot_stride(n_points: int, max_points: int) -> int:
    if n_points <= 0 or max_points <= 0:
        return 1
    return max(1, (n_points + max_points - 1) // max_points)


# ---------------------------------------------------------------------------
# pyqtgraph helpers
# ---------------------------------------------------------------------------
pg.setConfigOptions(antialias=True, background="#f3f4f6", foreground="#1a1d24")

_PEN_I = pg.mkPen("#1f77b4", width=1)
_PEN_Q = pg.mkPen("#ff7f0e", width=1)

# Theme tokens — light uses soft gray surfaces (not pure white).
_THEME_LIGHT = {
    "plot_bg": "#f3f4f6",
    "fg": "#1a1d24",
    "fg_secondary": "#3d4450",
    "fg_muted": "#5f6773",
    "ax": "#5f6773",
    "grid_alpha": 0.38,
    "metric": "#0b4f8a",
    "cur": "#0b4f8a",
    "cur_line": "#8891a0",
    "peak": "#b42318",
    "border": "#c8ced6",
    "input_bg": "#fcfcfd",
    "btn_bg": "#dce1e8",
    "btn_hover": "#cfd6e0",
    "btn_pressed": "#bcc4d0",
    "btn_checked": "#b8cce8",
    "highlight": "#2563eb",
}
_THEME_DARK = {
    "plot_bg": "#1e1e1e",
    "fg": "#e4e4e7",
    "fg_secondary": "#c4c4cc",
    "fg_muted": "#9ca3af",
    "ax": "#9ca3af",
    "grid_alpha": 0.28,
    "metric": "#60a5fa",
    "cur": "#60a5fa",
    "cur_line": "#6b7280",
    "peak": "#fca5a5",
    "border": "#4b5563",
    "input_bg": "#262626",
    "btn_bg": "#3a3a3a",
    "btn_hover": "#454545",
    "btn_pressed": "#525252",
    "btn_checked": "#1e3a5f",
    "highlight": "#3b82f6",
}


def _app_stylesheet(theme: dict[str, str]) -> str:
    """Global Qt widget styling for readable text on non-white surfaces."""
    t = theme
    return f"""
QWidget {{
    color: {t["fg"]};
}}
QMainWindow, QDialog {{
    background: {t["plot_bg"]};
}}
QGroupBox {{
    border: 1px solid {t["border"]};
    border-radius: 4px;
    margin-top: 8px;
    padding-top: 8px;
    font-weight: 600;
    color: {t["fg_secondary"]};
}}
QGroupBox::title {{
    subcontrol-origin: margin;
    left: 8px;
    padding: 0 4px;
    color: {t["fg_secondary"]};
}}
QLabel {{
    color: {t["fg"]};
}}
QPlainTextEdit, QTextEdit {{
    background: {t["input_bg"]};
    border: 1px solid {t["border"]};
    color: {t["fg"]};
    selection-background-color: {t["highlight"]};
    selection-color: #ffffff;
}}
QLineEdit, QComboBox, QSpinBox, QDoubleSpinBox, QPushButton {{
    min-height: 26px;
    max-height: 26px;
}}
QLineEdit, QComboBox {{
    background: {t["input_bg"]};
    border: 1px solid {t["border"]};
    border-radius: 3px;
    color: {t["fg"]};
    padding: 0 6px;
    selection-background-color: {t["highlight"]};
    selection-color: #ffffff;
}}
QSpinBox, QDoubleSpinBox {{
    background: {t["input_bg"]};
    border: 1px solid {t["border"]};
    border-radius: 3px;
    color: {t["fg"]};
    padding: 0 22px 0 6px;
    selection-background-color: {t["highlight"]};
    selection-color: #ffffff;
}}
QSpinBox::up-button, QSpinBox::down-button,
QDoubleSpinBox::up-button, QDoubleSpinBox::down-button {{
    width: 18px;
    border-left: 1px solid {t["border"]};
    background: {t["btn_bg"]};
}}
QSpinBox::up-button, QDoubleSpinBox::up-button {{
    subcontrol-origin: border;
    subcontrol-position: top right;
    border-top-right-radius: 3px;
    border-bottom: 1px solid {t["border"]};
}}
QSpinBox::down-button, QDoubleSpinBox::down-button {{
    subcontrol-origin: border;
    subcontrol-position: bottom right;
    border-bottom-right-radius: 3px;
}}
QSpinBox::up-button:hover, QSpinBox::down-button:hover,
QDoubleSpinBox::up-button:hover, QDoubleSpinBox::down-button:hover {{
    background: {t["btn_hover"]};
}}
QSpinBox::up-button:pressed, QSpinBox::down-button:pressed,
QDoubleSpinBox::up-button:pressed, QDoubleSpinBox::down-button:pressed {{
    background: {t["btn_pressed"]};
}}
QSpinBox::up-arrow, QDoubleSpinBox::up-arrow {{
    image: url("{_SPIN_UP_ARROW_URL}");
    width: 10px;
    height: 6px;
}}
QSpinBox::down-arrow, QDoubleSpinBox::down-arrow {{
    image: url("{_SPIN_DOWN_ARROW_URL}");
    width: 10px;
    height: 6px;
}}
QComboBox::drop-down {{
    border: none;
    width: 18px;
}}
QPushButton {{
    background: {t["btn_bg"]};
    border: 1px solid {t["border"]};
    border-radius: 3px;
    padding: 0 10px;
    color: {t["fg"]};
}}
QPushButton:hover {{
    background: {t["btn_hover"]};
}}
QPushButton:pressed {{
    background: {t["btn_pressed"]};
}}
QPushButton:checked {{
    background: {t["btn_checked"]};
    border-color: {t["highlight"]};
}}
QPushButton:disabled {{
    color: {t["fg_muted"]};
    background: {t["btn_bg"]};
}}
QSplitter::handle {{
    background: {t["border"]};
}}
"""


class CrosshairCursor:
    """MATLAB-style data tip: a crosshair that follows the mouse and a text
    label showing the cursor coordinates, attached to one PlotItem."""

    def __init__(self, plot: pg.PlotItem, *, x_unit: str = "", x_scale: float = 1.0,
                 fmt: str = "{x:.4g}{xu}, {y:.4g}") -> None:
        self.plot = plot
        self.x_unit = x_unit
        self.x_scale = x_scale
        self.fmt = fmt
        self.vline = pg.InfiniteLine(angle=90, movable=False,
                                     pen=pg.mkPen("#8891a0", width=1, style=QtCore.Qt.DashLine))
        self.hline = pg.InfiniteLine(angle=0, movable=False,
                                     pen=pg.mkPen("#8891a0", width=1, style=QtCore.Qt.DashLine))
        self.vline.setZValue(50)
        self.hline.setZValue(50)
        plot.addItem(self.vline, ignoreBounds=True)
        plot.addItem(self.hline, ignoreBounds=True)
        self.label = pg.TextItem(color="#0b4f8a", anchor=(0, 1))
        self.label.setZValue(60)
        plot.addItem(self.label, ignoreBounds=True)
        self._proxy = pg.SignalProxy(
            plot.scene().sigMouseMoved, rateLimit=60, slot=self._on_move
        )
        self.set_visible(False)

    def set_theme(self, label_color: str, line_color: str) -> None:
        pen = pg.mkPen(line_color, width=1, style=QtCore.Qt.DashLine)
        self.vline.setPen(pen)
        self.hline.setPen(pen)
        self.label.setColor(label_color)

    def set_visible(self, vis: bool) -> None:
        for it in (self.vline, self.hline, self.label):
            it.setVisible(vis)

    def _on_move(self, evt) -> None:
        pos = evt[0]
        vb = self.plot.vb
        if not self.plot.sceneBoundingRect().contains(pos):
            self.set_visible(False)
            return
        mp = vb.mapSceneToView(pos)
        x = mp.x()
        y = mp.y()
        self.vline.setPos(x)
        self.hline.setPos(y)
        self.label.setText(self.fmt.format(x=x * self.x_scale, y=y, xu=self.x_unit))
        self.label.setPos(x, y)
        self.set_visible(True)


# ---------------------------------------------------------------------------
# IQ constellation window
# ---------------------------------------------------------------------------
class IqConstellationWindow(QtWidgets.QWidget):
    def __init__(self, parent: QtWidgets.QWidget | None = None) -> None:
        super().__init__(parent)
        self.setWindowTitle("IQ 复平面")
        self.resize(720, 720)
        lay = QtWidgets.QVBoxLayout(self)
        lay.setContentsMargins(6, 6, 6, 6)
        self.glw = pg.GraphicsLayoutWidget()
        lay.addWidget(self.glw)
        self.plot = self.glw.addPlot()
        self.plot.setLabel("bottom", "I code")
        self.plot.setLabel("left", "Q code")
        self.plot.showGrid(x=True, y=True, alpha=0.3)
        self.plot.setAspectLocked(True)
        self._zero_x = self.plot.addLine(x=0, pen=pg.mkPen("#8891a0", width=1))
        self._zero_y = self.plot.addLine(y=0, pen=pg.mkPen("#8891a0", width=1))
        self.scatter = pg.ScatterPlotItem(size=4, pen=None,
                                          brush=pg.mkBrush(31, 119, 180, 90))
        self.plot.addItem(self.scatter)
        self.cursor = CrosshairCursor(self.plot, fmt="I={x:.0f}, Q={y:.0f}")
        self._fg = _THEME_LIGHT["fg"]

    def apply_theme(self, theme: dict[str, str]) -> None:
        bg = theme["plot_bg"]
        ax = theme["ax"]
        fg = theme["fg"]
        cur = theme["cur"]
        cur_line = theme["cur_line"]
        grid_alpha = theme["grid_alpha"]
        self._fg = fg
        self.setStyleSheet(_app_stylesheet(theme))
        self.glw.setBackground(bg)
        axpen = pg.mkPen(ax)
        zpen = pg.mkPen(cur_line, width=1)
        for axn in ("bottom", "left"):
            a = self.plot.getAxis(axn)
            a.setPen(axpen)
            a.setTextPen(axpen)
            a.setLabel(**{"color": ax})
        self._zero_x.setPen(zpen)
        self._zero_y.setPen(zpen)
        self.plot.showGrid(x=True, y=True, alpha=grid_alpha)
        self.cursor.set_theme(cur, cur_line)
        # Recolour the current title.
        self.plot.setTitle(self.plot.titleLabel.text, color=fg)

    def update_iq(self, si: list[int], sq: list[int]) -> None:
        if not si or not sq:
            self.scatter.clear()
            self.plot.setTitle("IQ constellation (await capture)", color=self._fg)
            return
        n = min(len(si), len(sq))
        max_pts = 20000
        stride = max(1, (n + max_pts - 1) // max_pts)
        ip = np.asarray(si[:n:stride], dtype=np.float64)
        qp = np.asarray(sq[:n:stride], dtype=np.float64)
        self.scatter.setData(ip, qp)
        lim = float(max(np.max(np.abs(ip)), np.max(np.abs(qp)), 1.0)) * 1.08
        self.plot.setXRange(-lim, lim, padding=0)
        self.plot.setYRange(-lim, lim, padding=0)
        self.plot.setTitle(
            f"IQ constellation  N={n}  shown={len(ip)}  "
            f"mean=({float(np.mean(ip)):.2f}, {float(np.mean(qp)):.2f})",
            color=self._fg,
        )


# ---------------------------------------------------------------------------
# Main window
# ---------------------------------------------------------------------------
class AddaTestApp(QtWidgets.QMainWindow):
    METRIC_KEYS = ("fund", "snr", "thd", "sinad", "enob", "sfdr", "spur")
    SIGNAL_METRIC_LABELS = {
        "fund": "Fundamental f0", "snr": "SNR", "thd": "THD", "sinad": "SINAD",
        "enob": "ENOB", "sfdr": "SFDR", "spur": "Main spur",
    }

    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle(APP_TITLE)
        self.resize(1280, 860)
        self.setWindowState(self.windowState() | QtCore.Qt.WindowMaximized)

        # ---- state (mirrors the Tkinter app) ----
        self._uart: RfAddaUart | None = None
        self._worker: threading.Thread | None = None
        self._stream_stop_evt = threading.Event()
        self._streaming = False
        self._msg_q: queue.Queue[tuple[str, object]] = queue.Queue()
        self._samples_raw: list[int] = []
        self._samples: list[int] = []
        self._capture_label = ""
        self._fft_cache: dict | None = None
        self._fft_mode_key = "db"
        self._window_key = DEFAULT_WINDOW
        self._dc_block = True
        self._dc_method = DEFAULT_DC_METHOD
        self._dc_mask_bins = DEFAULT_DC_MASK_BINS
        self._analysis_mode = "i"
        self._dac_on = False
        self._dac_wave = "sine"
        self._dac_freq_hz = DAC_TONE_FREQ_HZ
        self._dac_amp_pct = 50
        self._dec_ratio = 0
        self._capture_mode = CAPTURE_MODE_SNAPSHOT
        self._nco_freq_word = 0
        self._nco_freq_hz = 0.0
        self._iq_feature_on = False
        self._fir_feature_on = False
        self._fir_sel = 0
        self._iq_op1 = 0x4000
        self._iq_op2 = 0
        self._iq_off_i = 0
        self._iq_off_q = 0
        self._adc_decode_mode = "twos"
        self._adc_outfmt_reg14: int | None = None
        self._port_info: dict[str, dict] = {}
        self._selected_device: str | None = None
        self._iq_win: IqConstellationWindow | None = None
        self._action_buttons: list[QtWidgets.QAbstractButton] = []
        self._metric_value_labels: dict[str, QtWidgets.QLabel] = {}
        self._metric_name_labels: dict[str, QtWidgets.QLabel] = {}
        self._fft_peak_items: list = []
        # Theme state (light by default; toggled via the top-bar button).
        self._dark = False
        self._theme = _THEME_LIGHT
        self._fg = _THEME_LIGHT["fg"]
        self._peak_color = _THEME_LIGHT["peak"]
        self._cursors: list[CrosshairCursor] = []

        self._build_ui()
        self._apply_theme(self._dark)
        self._refresh_ports()

        self._timer = QtCore.QTimer(self)
        self._timer.timeout.connect(self._poll_queue)
        self._timer.start(40)

    # ================================================================= UI
    def _build_ui(self) -> None:
        central = QtWidgets.QWidget()
        self.setCentralWidget(central)
        root = QtWidgets.QVBoxLayout(central)
        root.setContentsMargins(8, 8, 8, 8)
        root.setSpacing(8)

        # ---- connection bar ----
        top = QtWidgets.QHBoxLayout()
        top.addWidget(QtWidgets.QLabel("串口:"))
        self.port_combo = QtWidgets.QComboBox()
        self.port_combo.setMinimumWidth(220)
        self.port_combo.currentIndexChanged.connect(self._on_port_selected)
        top.addWidget(self.port_combo)
        btn_refresh = QtWidgets.QPushButton("刷新")
        btn_refresh.clicked.connect(self._refresh_ports)
        top.addWidget(btn_refresh)
        top.addSpacing(8)
        top.addWidget(QtWidgets.QLabel("波特率:"))
        self.baud_combo = QtWidgets.QComboBox()
        for b in (921600, 460800, 115200, 57600):
            self.baud_combo.addItem(str(b), b)
        self.baud_combo.setCurrentIndex(0)  # default 921600
        top.addWidget(self.baud_combo)
        self.btn_connect = QtWidgets.QPushButton("连接")
        self.btn_connect.clicked.connect(self._toggle_connect)
        top.addWidget(self.btn_connect)

        top.addSpacing(12)
        top.addWidget(QtWidgets.QLabel("采样点数:"))
        self.n_spin = QtWidgets.QSpinBox()
        self.n_spin.setRange(64, MAX_SAMPLES)
        self.n_spin.setSingleStep(64)
        self.n_spin.setValue(DEFAULT_SAMPLES)
        top.addWidget(self.n_spin)

        top.addSpacing(12)
        top.addWidget(QtWidgets.QLabel("Fs (MHz):"))
        self.fs_spin = QtWidgets.QDoubleSpinBox()
        self.fs_spin.setDecimals(5)
        self.fs_spin.setRange(0.001, 100000.0)
        self.fs_spin.setValue(DEFAULT_ADC_FS_HZ / 1e6)
        self.fs_spin.valueChanged.connect(self._on_fs_changed)
        top.addWidget(self.fs_spin)

        self.status_label = QtWidgets.QLabel("未连接")
        top.addSpacing(16)
        top.addWidget(self.status_label)
        top.addStretch(1)
        self.btn_theme = QtWidgets.QPushButton("暗黑模式")
        self.btn_theme.setCheckable(True)
        self.btn_theme.setToolTip("切换 暗黑模式/白昼模式")
        self.btn_theme.clicked.connect(self._toggle_theme)
        top.addWidget(self.btn_theme)
        root.addLayout(top)

        # ---- operation group ----
        actions = QtWidgets.QGroupBox("操作")
        av = QtWidgets.QVBoxLayout(actions)
        av.setSpacing(5)
        root.addWidget(actions)

        # row0: system
        r0 = self._row(av, "系统:")
        self._abtn(r0, "Ping", self._do_ping)
        self._abtn(r0, "固件版本", self._do_fw_version)
        self._abtn(r0, "错误查询", self._do_error_query)
        self._abtn(r0, "Boot 状态", self._do_boot_status)
        self._abtn(r0, "运行 Boot", self._do_boot_run)
        self._abtn(r0, "读芯片 ID/版本", self._do_chip_ids)
        r0.addSpacing(10)
        r0.addWidget(QtWidgets.QLabel("快捷SPI"))
        self.quick_spi_dir_combo = QtWidgets.QComboBox()
        self.quick_spi_dir_combo.addItems([lbl for _, lbl in QUICK_SPI_DIR_CHOICES])
        self.quick_spi_dir_combo.currentIndexChanged.connect(self._on_quick_spi_dir_changed)
        r0.addWidget(self.quick_spi_dir_combo)
        self.quick_spi_chip_combo = QtWidgets.QComboBox()
        self.quick_spi_chip_combo.addItems([lbl for _, lbl in QUICK_SPI_CHIP_CHOICES])
        r0.addWidget(self.quick_spi_chip_combo)
        r0.addWidget(QtWidgets.QLabel("地址"))
        self.quick_spi_addr_edit = QtWidgets.QLineEdit("0x00")
        self.quick_spi_addr_edit.setFixedWidth(78)
        r0.addWidget(self.quick_spi_addr_edit)
        r0.addWidget(QtWidgets.QLabel("数值"))
        self.quick_spi_data_edit = QtWidgets.QLineEdit("0x00")
        self.quick_spi_data_edit.setFixedWidth(78)
        r0.addWidget(self.quick_spi_data_edit)
        self._abtn(r0, "发送", self._do_quick_spi)
        self._on_quick_spi_dir_changed()
        r0.addStretch(1)

        # ---- DAC group ----
        dac_box = QtWidgets.QGroupBox("DAC 发送")
        dav = QtWidgets.QVBoxLayout(dac_box)
        dav.setSpacing(5)
        av.addWidget(dac_box)

        # row1: DAC tone
        r1 = self._row(dav, "DAC:")
        r1.addWidget(QtWidgets.QLabel("波形"))
        self.dac_wave_combo = QtWidgets.QComboBox()
        self.dac_wave_combo.addItems(DAC_WAVE_LABELS)
        r1.addWidget(self.dac_wave_combo)
        r1.addWidget(QtWidgets.QLabel("频率(kHz)"))
        self.dac_freq_spin = QtWidgets.QDoubleSpinBox()
        self.dac_freq_spin.setDecimals(3)
        self.dac_freq_spin.setRange(0.0, 100000.0)
        self.dac_freq_spin.setValue(DAC_TONE_FREQ_HZ / 1e3)
        r1.addWidget(self.dac_freq_spin)
        r1.addWidget(QtWidgets.QLabel("幅度(%)"))
        self.dac_amp_spin = QtWidgets.QSpinBox()
        self.dac_amp_spin.setRange(0, 100)
        self.dac_amp_spin.setValue(50)
        r1.addWidget(self.dac_amp_spin)
        self.dac_hb_chk = QtWidgets.QCheckBox("半带插值")
        self.dac_hb_chk.setChecked(True)
        self.dac_hb_chk.setToolTip(
            "2× 半带 FIR 插值（默认开）。\n关闭则改用 sample-repeat（0x41 bit[7]=1）")
        r1.addWidget(self.dac_hb_chk)
        self._abtn(r1, "应用参数", self._do_dac_apply)
        self._abtn(r1, "启动波形", self._do_dac_on)
        self._abtn(r1, "停止波形", self._do_dac_off)
        r1.addStretch(1)

        # row1w: waveform player
        rw = self._row(dav, "波形文件:")
        self.wave_path_edit = QtWidgets.QLineEdit()
        self.wave_path_edit.setMinimumWidth(280)
        rw.addWidget(self.wave_path_edit)
        self._abtn(rw, "浏览…", self._do_wave_browse)
        rw.addWidget(QtWidgets.QLabel("loop_len"))
        self.wave_loop_spin = QtWidgets.QSpinBox()
        self.wave_loop_spin.setRange(0, 262144)
        self.wave_loop_spin.setSingleStep(1024)
        rw.addWidget(self.wave_loop_spin)
        self.wave_swap_chk = QtWidgets.QCheckBox("swap I/Q")
        self.wave_swap_chk.toggled.connect(self._do_wave_polarity)
        rw.addWidget(self.wave_swap_chk)
        self.wave_negq_chk = QtWidgets.QCheckBox("neg Q")
        self.wave_negq_chk.toggled.connect(self._do_wave_polarity)
        rw.addWidget(self.wave_negq_chk)
        self._abtn(rw, "上传 URAM", self._do_wave_upload)
        self._abtn(rw, "启动播放", self._do_wave_play_on)
        self._abtn(rw, "停止播放", self._do_wave_play_off)
        rw.addStretch(1)

        # ---- ADC group ----
        adc_box = QtWidgets.QGroupBox("ADC 接收")
        aav = QtWidgets.QVBoxLayout(adc_box)
        aav.setSpacing(5)
        av.addWidget(adc_box)

        # row2: ADC
        r2 = self._row(aav, "ADC:")
        r2.addWidget(QtWidgets.QLabel("Dec"))
        self.dec_combo = QtWidgets.QComboBox()
        self.dec_combo.addItems(DEC_RATIO_LABELS)
        self.dec_combo.currentIndexChanged.connect(self._sync_rx_chain_config)
        r2.addWidget(self.dec_combo)
        r2.addWidget(QtWidgets.QLabel("Mode"))
        self.mode_combo = QtWidgets.QComboBox()
        self.mode_combo.addItems(CAPTURE_MODE_LABELS)
        self.mode_combo.currentIndexChanged.connect(self._sync_rx_chain_config)
        r2.addWidget(self.mode_combo)
        self._abtn(r2, "ADC 采集", self._do_adc_capture)
        self.btn_stream_stop = QtWidgets.QPushButton("停止连续流")
        self.btn_stream_stop.clicked.connect(self._do_stream_stop)
        r2.addWidget(self.btn_stream_stop)
        self._abtn(r2, "环回测试(DAC+ADC+FFT)", self._do_loopback_test)
        r2.addStretch(1)

        # row2b: RX + NCO
        r2b = self._row(aav, "RX/NCO:")
        self.iq_feature_chk = QtWidgets.QCheckBox("IQ处理")
        self.iq_feature_chk.setChecked(False)
        self.iq_feature_chk.toggled.connect(self._sync_rx_chain_config)
        r2b.addWidget(self.iq_feature_chk)
        self.fir_feature_chk = QtWidgets.QCheckBox("FIR滤波")
        self.fir_feature_chk.setChecked(False)
        self.fir_feature_chk.toggled.connect(self._sync_rx_chain_config)
        r2b.addWidget(self.fir_feature_chk)
        self.fir_sel_combo = QtWidgets.QComboBox()
        self.fir_sel_combo.addItems(FIR_BANK_LABELS)
        self.fir_sel_combo.setToolTip("FIR 系数档 (fir_bypass=0 时生效)")
        self.fir_sel_combo.currentIndexChanged.connect(self._sync_rx_chain_config)
        r2b.addWidget(self.fir_sel_combo)
        self._abtn(r2b, "应用 RX 配置", self._do_apply_rx_cfg)
        r2b.addSpacing(8)
        r2b.addWidget(QtWidgets.QLabel("NCO(kHz)"))
        self.nco_freq_spin = QtWidgets.QDoubleSpinBox()
        self.nco_freq_spin.setDecimals(3)
        self.nco_freq_spin.setRange(-100000.0, 100000.0)
        r2b.addWidget(self.nco_freq_spin)
        self._abtn(r2b, "应用 NCO", self._do_apply_nco)
        self._abtn(r2b, "清零 NCO", self._do_nco_clear)
        r2b.addWidget(QtWidgets.QLabel("状态"))
        self.nco_state_label = QtWidgets.QLabel("unknown")
        r2b.addWidget(self.nco_state_label)
        r2b.addStretch(1)

        # row2c: IQ balance
        r2c = self._row(aav, "IQ平衡:")
        r2c.addWidget(QtWidgets.QLabel("OP1(hex)"))
        self.iq_op1_edit = QtWidgets.QLineEdit("0x4000")
        self.iq_op1_edit.setFixedWidth(80)
        r2c.addWidget(self.iq_op1_edit)
        r2c.addWidget(QtWidgets.QLabel("OP2(hex)"))
        self.iq_op2_edit = QtWidgets.QLineEdit("0x0000")
        self.iq_op2_edit.setFixedWidth(80)
        r2c.addWidget(self.iq_op2_edit)
        r2c.addWidget(QtWidgets.QLabel("off_I"))
        self.iq_offi_spin = QtWidgets.QSpinBox()
        self.iq_offi_spin.setRange(-8192, 8191)
        r2c.addWidget(self.iq_offi_spin)
        r2c.addWidget(QtWidgets.QLabel("off_Q"))
        self.iq_offq_spin = QtWidgets.QSpinBox()
        self.iq_offq_spin.setRange(-8192, 8191)
        r2c.addWidget(self.iq_offq_spin)
        self._abtn(r2c, "应用 IQ 平衡", self._do_apply_iq)
        self._abtn(r2c, "复位 IQ", self._do_reset_iq)
        self.iq_state_label = QtWidgets.QLabel("op1=0x4000 op2=0x0000 offI=0 offQ=0")
        r2c.addWidget(self.iq_state_label)
        r2c.addStretch(1)

        # row3: display controls
        r3 = self._row(av, "显示:")
        r3.addWidget(QtWidgets.QLabel("窗函数"))
        self.window_combo = QtWidgets.QComboBox()
        self.window_combo.addItems([lbl for _, lbl in WINDOW_CHOICES])
        self.window_combo.setCurrentText(WINDOW_KEY_TO_LABEL[self._window_key])
        self.window_combo.currentIndexChanged.connect(self._on_window_changed)
        r3.addWidget(self.window_combo)
        self.dc_block_chk = QtWidgets.QCheckBox("DC屏蔽")
        self.dc_block_chk.setChecked(self._dc_block)
        self.dc_block_chk.toggled.connect(self._on_dc_changed)
        r3.addWidget(self.dc_block_chk)
        self.dc_method_combo = QtWidgets.QComboBox()
        self.dc_method_combo.addItems([lbl for _, lbl in DC_METHOD_CHOICES])
        self.dc_method_combo.setCurrentText(DC_METHOD_KEY_TO_LABEL[self._dc_method])
        self.dc_method_combo.currentIndexChanged.connect(self._on_dc_changed)
        r3.addWidget(self.dc_method_combo)
        r3.addWidget(QtWidgets.QLabel("分析"))
        self.analysis_combo = QtWidgets.QComboBox()
        self.analysis_combo.addItems([lbl for _, lbl in ANALYSIS_MODE_CHOICES])
        self.analysis_combo.currentIndexChanged.connect(self._on_analysis_mode_changed)
        r3.addWidget(self.analysis_combo)
        self._abtn(r3, "IQ复平面", self._open_iq_constellation_window)
        r3.addWidget(QtWidgets.QLabel("FFT:"))
        for label, _yl, key, _c in FFT_MODE_OPTIONS:
            b = QtWidgets.QPushButton(label)
            b.clicked.connect(lambda _=False, k=key: self._plot_fft_mode(k))
            r3.addWidget(b)
            self._action_buttons.append(b)
        r3.addStretch(1)

        # row4: export tools
        r4 = self._row(av, "导出:")
        self._abtn(r4, "导入 IQ 文件分析", self._do_load_iq_file)
        self._abtn(r4, "保存 CSV", self._save_csv)
        self._abtn(r4, "导出 MATLAB BIN", self._save_matlab_bin)
        self._abtn(r4, "打开 MATLAB IFFT 脚本", self._open_matlab_ifft_script)
        r4.addStretch(1)

        self.summary_label = QtWidgets.QLabel("")
        self.summary_label.setWordWrap(True)
        av.addWidget(self.summary_label)

        # ---- center: plots | metrics ----
        center = QtWidgets.QHBoxLayout()
        center.setSpacing(8)
        root.addLayout(center, 1)

        plots_box = QtWidgets.QGroupBox("绘图")
        pv = QtWidgets.QVBoxLayout(plots_box)
        pv.setContentsMargins(4, 4, 4, 4)
        self.glw = pg.GraphicsLayoutWidget()
        pv.addWidget(self.glw)
        self._build_plots()
        center.addWidget(plots_box, 1)

        metrics_box = QtWidgets.QGroupBox("Dynamic metrics")
        mlay = QtWidgets.QGridLayout(metrics_box)
        mlay.setVerticalSpacing(2)
        btn_copy = QtWidgets.QPushButton("复制I/Q指标行")
        btn_copy.clicked.connect(self._copy_iq_metrics_row)
        mlay.addWidget(btn_copy, 0, 0)
        for i, key in enumerate(self.METRIC_KEYS):
            name = QtWidgets.QLabel(self.SIGNAL_METRIC_LABELS[key])
            val = QtWidgets.QLabel("—")
            val.setProperty("metricValue", True)  # theme styles these via _apply_theme
            val.setCursor(QtCore.Qt.PointingHandCursor)
            val.setTextInteractionFlags(QtCore.Qt.TextSelectableByMouse)
            val.mousePressEvent = (lambda _e, k=key: self._copy_metric_item(k))  # type: ignore[assignment]
            mlay.addWidget(name, 2 * i + 1, 0)
            mlay.addWidget(val, 2 * i + 2, 0)
            self._metric_name_labels[key] = name
            self._metric_value_labels[key] = val
        mlay.setRowStretch(2 * len(self.METRIC_KEYS) + 1, 1)
        metrics_box.setFixedWidth(220)
        center.addWidget(metrics_box, 0)

        # ---- log ----
        log_box = QtWidgets.QGroupBox("日志")
        lv = QtWidgets.QVBoxLayout(log_box)
        lv.setContentsMargins(4, 4, 4, 4)
        self.log = QtWidgets.QPlainTextEdit()
        self.log.setReadOnly(True)
        self.log.setMaximumBlockCount(2000)
        self.log.setFont(_default_console_font(9))
        self.log.setFixedHeight(self.log.fontMetrics().lineSpacing() * 6 + 12)
        lv.addWidget(self.log)
        root.addWidget(log_box)

        self._set_actions_enabled(False)
        self.btn_stream_stop.setEnabled(False)

    def _build_plots(self) -> None:
        self.plot_time = self.glw.addPlot(row=0, col=0)
        self.plot_time.setLabel("bottom", "time (µs)")
        self.plot_time.setLabel("left", "14-bit signed code")
        self.plot_time.showGrid(x=True, y=True, alpha=0.3)
        self._title(self.plot_time, "Time domain (await capture)")
        self.curve_time = self.plot_time.plot([], [], pen=_PEN_I)
        self.curve_time_q = self.plot_time.plot([], [], pen=_PEN_Q)
        self.cursor_time = CrosshairCursor(self.plot_time, x_unit=" µs",
                                           fmt="{x:.3f}{xu}, {y:.0f}")
        self._cursors.append(self.cursor_time)

        self.plot_fft = self.glw.addPlot(row=1, col=0)
        self.plot_fft.setLabel("bottom", "frequency (MHz)")
        self.plot_fft.setLabel("left", "magnitude (dB)")
        self.plot_fft.showGrid(x=True, y=True, alpha=0.3)
        self._title(self.plot_fft, "FFT (auto dB after capture)")
        self.curve_fft = self.plot_fft.plot([], [], pen=pg.mkPen("#2ca02c", width=1))
        self.curve_fft_q = self.plot_fft.plot([], [], pen=_PEN_Q)
        self.cursor_fft = CrosshairCursor(self.plot_fft, x_unit=" MHz",
                                          fmt="{x:.4f}{xu}, {y:.2f}")
        self._cursors.append(self.cursor_fft)
        # Draggable marker line (MATLAB-style movable data cursor) on the FFT.
        self.fft_marker = pg.InfiniteLine(
            angle=90, movable=True,
            pen=pg.mkPen("#d62728", width=1, style=QtCore.Qt.DashLine),
            label="", labelOpts={"position": 0.95, "color": "#d62728"},
        )
        self.fft_marker.setVisible(False)
        self.plot_fft.addItem(self.fft_marker, ignoreBounds=True)
        self.fft_marker.sigPositionChanged.connect(self._on_fft_marker_moved)
        # DAC tone reference line.
        self.dac_tone_line = pg.InfiniteLine(
            angle=90, movable=False,
            pen=pg.mkPen("#d62728", width=1, style=QtCore.Qt.DotLine))
        self.dac_tone_line.setVisible(False)
        self.plot_fft.addItem(self.dac_tone_line, ignoreBounds=True)

    # ---- small UI helpers ----
    def _row(self, parent_layout: QtWidgets.QVBoxLayout, label: str) -> QtWidgets.QHBoxLayout:
        h = QtWidgets.QHBoxLayout()
        h.setSpacing(6)
        if label:
            h.addWidget(QtWidgets.QLabel(label))
        parent_layout.addLayout(h)
        return h

    def _abtn(self, row: QtWidgets.QHBoxLayout, text: str, slot) -> QtWidgets.QPushButton:
        b = QtWidgets.QPushButton(text)
        b.clicked.connect(lambda _=False: slot())
        row.addWidget(b)
        self._action_buttons.append(b)
        return b

    def _set_actions_enabled(self, enabled: bool) -> None:
        for b in self._action_buttons:
            b.setEnabled(enabled)
        self.btn_stream_stop.setEnabled(self._streaming)

    def _log(self, msg: str) -> None:
        ts = time.strftime("%H:%M:%S")
        self.log.appendPlainText(f"[{ts}] {msg}")

    # ----------------------------------------------------------------- theme
    def _title(self, plot: pg.PlotItem, text: str) -> None:
        """Set a plot title in the current theme's foreground colour."""
        plot.setTitle(text, color=self._fg)

    @staticmethod
    def _dark_palette() -> QtGui.QPalette:
        Role = QtGui.QPalette.ColorRole
        Group = QtGui.QPalette.ColorGroup
        C = QtGui.QColor
        t = _THEME_DARK
        pal = QtGui.QPalette()
        pal.setColor(Role.Window, C(t["plot_bg"]))
        pal.setColor(Role.WindowText, C(t["fg"]))
        pal.setColor(Role.Base, C(t["input_bg"]))
        pal.setColor(Role.AlternateBase, C(t["btn_bg"]))
        pal.setColor(Role.ToolTipBase, C(t["btn_bg"]))
        pal.setColor(Role.ToolTipText, C(t["fg"]))
        pal.setColor(Role.Text, C(t["fg"]))
        pal.setColor(Role.Button, C(t["btn_bg"]))
        pal.setColor(Role.ButtonText, C(t["fg"]))
        pal.setColor(Role.BrightText, C(t["peak"]))
        pal.setColor(Role.Highlight, C(t["highlight"]))
        pal.setColor(Role.HighlightedText, C("#ffffff"))
        pal.setColor(Role.Link, C(t["metric"]))
        pal.setColor(Role.PlaceholderText, C(t["fg_muted"]))
        for role in (Role.Text, Role.ButtonText, Role.WindowText):
            pal.setColor(Group.Disabled, role, C(t["fg_muted"]))
        return pal

    @staticmethod
    def _light_palette() -> QtGui.QPalette:
        Role = QtGui.QPalette.ColorRole
        Group = QtGui.QPalette.ColorGroup
        C = QtGui.QColor
        t = _THEME_LIGHT
        pal = QtGui.QPalette()
        pal.setColor(Role.Window, C(t["plot_bg"]))
        pal.setColor(Role.WindowText, C(t["fg"]))
        pal.setColor(Role.Base, C(t["input_bg"]))
        pal.setColor(Role.AlternateBase, C(t["btn_bg"]))
        pal.setColor(Role.ToolTipBase, C(t["input_bg"]))
        pal.setColor(Role.ToolTipText, C(t["fg"]))
        pal.setColor(Role.Text, C(t["fg"]))
        pal.setColor(Role.Button, C(t["btn_bg"]))
        pal.setColor(Role.ButtonText, C(t["fg"]))
        pal.setColor(Role.BrightText, C(t["peak"]))
        pal.setColor(Role.Highlight, C(t["highlight"]))
        pal.setColor(Role.HighlightedText, C("#ffffff"))
        pal.setColor(Role.Link, C(t["metric"]))
        pal.setColor(Role.PlaceholderText, C(t["fg_muted"]))
        for role in (Role.Text, Role.ButtonText, Role.WindowText):
            pal.setColor(Group.Disabled, role, C(t["fg_muted"]))
        return pal

    def _toggle_theme(self) -> None:
        self._apply_theme(self.btn_theme.isChecked())

    def _apply_theme(self, dark: bool) -> None:
        self._dark = bool(dark)
        theme = _THEME_DARK if dark else _THEME_LIGHT
        self._theme = theme
        app = QtWidgets.QApplication.instance()
        pal = self._dark_palette() if dark else self._light_palette()
        self._peak_color = theme["peak"]
        self.btn_theme.setText("白昼模式" if dark else "暗黑模式")
        self.btn_theme.setChecked(dark)
        app.setPalette(pal)
        app.setStyleSheet(_app_stylesheet(theme))
        self._fg = theme["fg"]
        pg.setConfigOption("background", theme["plot_bg"])
        pg.setConfigOption("foreground", theme["fg"])

        self._theme_plots(
            self.glw, (self.plot_time, self.plot_fft),
            theme["plot_bg"], theme["ax"], theme["grid_alpha"],
        )
        for c in self._cursors:
            c.set_theme(theme["cur"], theme["cur_line"])
        for v in self._metric_value_labels.values():
            v.setStyleSheet(f"color:{theme['metric']}; font-weight:bold;")
        for v in self._metric_name_labels.values():
            v.setStyleSheet(f"color:{theme['fg_secondary']};")
        self.status_label.setStyleSheet(f"color:{theme['fg_muted']};")
        self.summary_label.setStyleSheet(f"color:{theme['fg_secondary']};")
        if self._iq_win is not None:
            self._iq_win.apply_theme(theme)

        # Re-render so titles / labels / peaks pick up the new colours.
        if self._samples:
            self._plot_time()
            self._render_fft_after_change()
        else:
            self._title(self.plot_time, "Time domain (await capture)")
            self._title(self.plot_fft, "FFT (auto dB after capture)")

    @staticmethod
    def _theme_plots(glw: pg.GraphicsLayoutWidget, plots, bg: str, ax: str,
                     grid_alpha: float) -> None:
        glw.setBackground(bg)
        axpen = pg.mkPen(ax)
        for p in plots:
            for axn in ("bottom", "left"):
                axis = p.getAxis(axn)
                axis.setPen(axpen)
                axis.setTextPen(axpen)
                axis.setLabel(**{"color": ax})  # keep text, recolour
            p.showGrid(x=True, y=True, alpha=grid_alpha)

    # ================================================================= ports / connect
    def _on_port_selected(self, _idx: int = -1) -> None:
        port = self._selected_port()
        if not port:
            return
        self._selected_device = port
        if not self._uart:
            info = self._port_info.get(port)
            if info:
                mark = "✓" if info["ok"] else "✗"
                self.status_label.setText(f"未连接 — 已选 {port} {mark}")

    def _selected_port(self) -> str | None:
        data = self.port_combo.currentData()
        if data:
            return normalize_com_port(str(data))
        return normalize_com_port(self.port_combo.currentText())

    def _refresh_ports(self) -> None:
        prev = self._selected_device or self._selected_port()
        self.status_label.setText("正在探测串口…")
        QtWidgets.QApplication.processEvents()
        rows = enumerate_ports(probe=True)
        self._port_info = {str(r["device"]): r for r in rows}
        self.port_combo.blockSignals(True)
        self.port_combo.clear()
        for r in rows:
            dev = str(r["device"])
            mark = "✓" if r["ok"] else "✗"
            desc = str(r["description"])[:40]
            self.port_combo.addItem(f"{dev} {mark} — {desc}", dev)
        self.port_combo.blockSignals(False)

        picked = prev if prev in self._port_info else pick_default_port(rows)
        if picked and picked in self._port_info:
            for i in range(self.port_combo.count()):
                if self.port_combo.itemData(i) == picked:
                    self.port_combo.setCurrentIndex(i)
                    break
            self._selected_device = picked
        ok_n = sum(1 for r in rows if r["ok"])
        if not self._uart:
            self.status_label.setText("未连接")
        if rows:
            self._log(f"串口探测: {ok_n}/{len(rows)} 可用 (✓=可连接, ✗=不可用)")
            for r in rows:
                mark = "✓" if r["ok"] else "✗"
                self._log(f"  {mark} {r['device']}\t{r['description']}")
            if picked:
                self._log(f"  当前选择: {picked}")
        else:
            self._log("未发现串口")

    def _toggle_connect(self) -> None:
        if self._uart and self._uart.is_open:
            self._disconnect()
            return
        if self._worker and self._worker.is_alive():
            QtWidgets.QMessageBox.information(self, APP_TITLE, "请等待当前操作完成")
            return
        port = self._selected_port()
        if not port:
            QtWidgets.QMessageBox.warning(self, APP_TITLE, "请选择串口")
            return
        self._selected_device = port
        info = self._port_info.get(port)
        if info and not info["ok"]:
            ans = QtWidgets.QMessageBox.question(
                self, APP_TITLE,
                f"{port} 探测为不可用，仍要尝试连接？\n\n"
                "CH340 双串口板请选较高编号且 ✓ 的端口（如 COM14）。")
            if ans != QtWidgets.QMessageBox.Yes:
                return
        baud = self.baud_combo.currentData()
        self._log(f"正在连接 {port} @ {baud} …")
        try:
            self._uart = RfAddaUart(port, baud=baud)
        except Exception as e:  # noqa: BLE001
            from rf_uart_client import format_serial_error
            QtWidgets.QMessageBox.critical(self, APP_TITLE, format_serial_error(e, port))
            self._log(f"连接失败 {port}: {e}")
            return
        self.btn_connect.setText("断开")
        self.port_combo.setEnabled(False)
        self.baud_combo.setEnabled(False)
        self.status_label.setText(f"已连接 {port} @ {baud}")
        self._log(f"已连接 {port}")
        self._refresh_adc_decode_mode(self._uart, source="连接")
        self._set_actions_enabled(True)

    def _disconnect(self) -> None:
        self._do_stream_stop()
        if self._worker and self._worker.is_alive():
            self._worker.join(timeout=1.0)
        if self._uart:
            try:
                if self._dac_on:
                    self._uart.dac_tone_enable(False)
            except Exception:
                pass
            self._uart.close()
        self._uart = None
        self._dac_on = False
        self.btn_connect.setText("连接")
        self.port_combo.setEnabled(True)
        self.baud_combo.setEnabled(True)
        self.status_label.setText("未连接")
        self._log("已断开")
        self._set_actions_enabled(False)

    def _uart_live(self) -> RfAddaUart:
        if not self._uart or not self._uart.is_open:
            raise RuntimeError("请先连接串口")
        return self._uart

    # ================================================================= async / queue
    def _run_async(self, label: str, fn) -> None:
        if not self._uart or not self._uart.is_open:
            QtWidgets.QMessageBox.warning(self, APP_TITLE, "请先连接串口")
            return
        if self._worker and self._worker.is_alive():
            QtWidgets.QMessageBox.information(self, APP_TITLE, "上一操作仍在进行，请稍候")
            return
        self._set_actions_enabled(False)
        self.status_label.setText(f"进行中: {label}...")

        def target() -> None:
            try:
                fn()
                self._msg_q.put(("done", label))
            except Exception as e:  # noqa: BLE001
                self._msg_q.put(("error", str(e)))

        self._worker = threading.Thread(target=target, daemon=True)
        self._worker.start()

    def _poll_queue(self) -> None:
        try:
            while True:
                kind, payload = self._msg_q.get_nowait()
                if kind == "done":
                    self.status_label.setText(f"完成: {payload}")
                    self._set_actions_enabled(True)
                elif kind == "error":
                    self.status_label.setText("错误")
                    self._set_actions_enabled(True)
                    self._log(f"错误: {payload}")
                    QtWidgets.QMessageBox.critical(self, APP_TITLE, str(payload))
                elif kind == "log":
                    self._log(str(payload))
                elif kind == "samples":
                    self._samples_raw, self._capture_label = payload  # type: ignore[misc]
                    self._samples = self._analysis_samples()
                    self._fft_cache = None
                    self._plot_time()
                    self._refresh_iq_constellation()
                    if self._capture_label == "ADC 连续流":
                        self._clear_fft_plot()
                        self._update_summary()
                    else:
                        self._plot_fft_mode("db")
                elif kind == "dac":
                    self._dac_on = bool(payload)
                elif kind == "dac_freq":
                    self._dac_freq_hz = float(payload)
                elif kind == "nco":
                    word, hz = payload  # type: ignore[misc]
                    self._set_nco_state(int(word), float(hz))
                elif kind == "iq_feature_on":
                    self.iq_feature_chk.setChecked(bool(payload))
                elif kind == "stream_state":
                    self._streaming = bool(payload)
                    self._set_actions_enabled(
                        self._uart is not None and self._uart.is_open and not self._streaming)
        except queue.Empty:
            pass

    # ================================================================= config sync
    def _n_samples(self) -> int:
        return int(self.n_spin.value())

    def _fs_hz(self) -> float:
        return float(self.fs_spin.value()) * 1e6

    def _on_fs_changed(self, _v: float = 0.0) -> None:
        if self._fft_cache is not None:
            self._fft_cache = None
            self._clear_fft_plot()
            self._update_summary()

    def _dc_kwargs(self) -> dict:
        return {"dc_block": self._dc_block, "dc_method": self._dc_method,
                "dc_mask_bins": self._dc_mask_bins}

    def _on_window_changed(self, _i: int = -1) -> None:
        key = WINDOW_LABEL_TO_KEY.get(self.window_combo.currentText(), DEFAULT_WINDOW)
        if key == self._window_key:
            return
        self._window_key = key
        self._log(f"窗函数切换为: {self.window_combo.currentText()}")
        if self._samples:
            self._fft_cache = None
            self._update_summary()
            self._render_fft_after_change()

    def _on_dc_changed(self, _v=None) -> None:
        self._dc_block = bool(self.dc_block_chk.isChecked())
        self._dc_method = DC_METHOD_LABEL_TO_KEY.get(
            self.dc_method_combo.currentText(), DEFAULT_DC_METHOD)
        self._log(f"DC屏蔽={self._onoff(self._dc_block)}, 方法={self.dc_method_combo.currentText()}")
        if self._samples:
            self._fft_cache = None
            self._update_summary()
            self._render_fft_after_change()

    def _on_analysis_mode_changed(self, _i: int = -1) -> None:
        key = ANALYSIS_MODE_LABEL_TO_KEY.get(self.analysis_combo.currentText(), "i")
        if key == self._analysis_mode:
            return
        self._analysis_mode = key
        self._samples = self._analysis_samples()
        self._fft_cache = None
        self._clear_fft_plot()
        self._update_summary()
        self._plot_time()
        self._refresh_iq_constellation()
        self._log(f"分析模式切换为: {ANALYSIS_MODE_KEY_TO_LABEL.get(key, key)}")

    def _sync_rx_chain_config(self, *_a) -> None:
        self._dec_ratio = max(0, min(2, self.dec_combo.currentIndex()))
        self._capture_mode = (CAPTURE_MODE_STREAM if self.mode_combo.currentIndex() == 1
                              else CAPTURE_MODE_SNAPSHOT)
        self._iq_feature_on = bool(self.iq_feature_chk.isChecked())
        self._fir_feature_on = bool(self.fir_feature_chk.isChecked())
        self._fir_sel = max(0, min(3, self.fir_sel_combo.currentIndex()))

    def _sync_dac_params(self) -> None:
        idx = self.dac_wave_combo.currentIndex()
        self._dac_wave = DAC_WAVE_KEYS[idx] if 0 <= idx < len(DAC_WAVE_KEYS) else "sine"
        self._dac_freq_hz = float(self.dac_freq_spin.value()) * 1e3
        self._dac_amp_pct = int(self.dac_amp_spin.value())
        self._dac_hb_bypass = not bool(self.dac_hb_chk.isChecked())

    def _dac_params(self) -> tuple[str, float, int, bool]:
        self._sync_dac_params()
        return self._dac_wave, self._dac_freq_hz, self._dac_amp_pct, self._dac_hb_bypass

    def _parse_int_field(self, text: str) -> int:
        s = str(text).strip()
        if not s:
            raise ValueError("empty")
        base = 16 if s.lower().startswith("0x") else 10
        return int(s, base)

    def _on_quick_spi_dir_changed(self, _i: int = -1) -> None:
        mode = QUICK_SPI_DIR_LABEL_TO_KEY.get(self.quick_spi_dir_combo.currentText(), "rx")
        write_mode = (mode == "tx")
        self.quick_spi_data_edit.setEnabled(write_mode)
        if write_mode:
            self.quick_spi_data_edit.setPlaceholderText("0x00")
        else:
            self.quick_spi_data_edit.setPlaceholderText("读模式忽略")

    def _sync_iq_balance(self) -> None:
        try:
            self._iq_op1 = self._parse_int_field(self.iq_op1_edit.text()) & 0xFFFF
        except Exception:
            self._iq_op1 = 0x4000
        try:
            self._iq_op2 = self._parse_int_field(self.iq_op2_edit.text()) & 0xFFFF
        except Exception:
            self._iq_op2 = 0
        self._iq_off_i = max(-8192, min(8191, int(self.iq_offi_spin.value())))
        self._iq_off_q = max(-8192, min(8191, int(self.iq_offq_spin.value())))
        self._refresh_iq_state_label()

    def _refresh_iq_state_label(self) -> None:
        self.iq_state_label.setText(
            f"op1=0x{self._iq_op1:04X} op2=0x{self._iq_op2:04X} "
            f"offI={self._iq_off_i} offQ={self._iq_off_q}")

    def _set_nco_state(self, word: int, hz: float) -> None:
        self._nco_freq_word = int(word) & 0xFFFF
        self._nco_freq_hz = float(hz)
        self.nco_state_label.setText(
            f"{self._nco_freq_hz/1e3:.2f} kHz (0x{self._nco_freq_word:04X})")

    def _refresh_adc_decode_mode(self, u: RfAddaUart, *, source: str) -> None:
        self._adc_decode_mode = "twos"
        try:
            reg14 = u.spi_read(CHIP_AD9640, 0x14)
        except Exception as e:  # noqa: BLE001
            self._log(f"ADC解码固定为 two's-complement; AD9640[0x14] 读取失败 ({source}): {e}")
            return
        self._adc_outfmt_reg14 = reg14 & 0xFF
        chip_mode = "two's-complement" if (self._adc_outfmt_reg14 & 0x01) else "offset-binary"
        self._log(f"ADC解码固定为 two's-complement ({source}): "
                  f"AD9640[0x14]=0x{self._adc_outfmt_reg14:02X} 芯片侧={chip_mode}")

    def _decode_adc_samples_auto(self, samples: list[int], *, bits: int = 14) -> list[int]:
        return samples_to_signed(samples, bits=bits)

    # ================================================================= sample views
    def _analysis_samples(self) -> list[int]:
        s = self._samples_raw
        if not s:
            return []
        if self._analysis_mode == "iq":
            return s[0::2]
        return s

    def _iq_samples_pair(self) -> tuple[list[int], list[int]]:
        s = self._samples_raw
        if not s:
            return [], []
        return s[0::2], s[1::2]

    def _is_iq_parallel(self) -> bool:
        return self._analysis_mode == "iq"

    def _analysis_mode_plot_label(self) -> str:
        return PLOT_ANALYSIS_MODE_LABELS.get(self._analysis_mode, self._analysis_mode)

    # ================================================================= system jobs
    def _do_quick_spi(self) -> None:
        mode = QUICK_SPI_DIR_LABEL_TO_KEY.get(self.quick_spi_dir_combo.currentText(), "rx")
        chip_label = self.quick_spi_chip_combo.currentText()
        chip = QUICK_SPI_CHIP_LABEL_TO_ID.get(chip_label, CHIP_AD9640)
        try:
            addr = self._parse_int_field(self.quick_spi_addr_edit.text())
        except Exception as e:  # noqa: BLE001
            QtWidgets.QMessageBox.warning(self, APP_TITLE, f"寄存器地址格式错误: {e}")
            return
        if not (0 <= addr <= 0xFF):
            QtWidgets.QMessageBox.warning(self, APP_TITLE, "寄存器地址范围应为 0x00~0xFF")
            return

        data = 0
        if mode == "tx":
            try:
                data = self._parse_int_field(self.quick_spi_data_edit.text())
            except Exception as e:  # noqa: BLE001
                QtWidgets.QMessageBox.warning(self, APP_TITLE, f"写入数值格式错误: {e}")
                return
            if not (0 <= data <= 0xFF):
                QtWidgets.QMessageBox.warning(self, APP_TITLE, "写入数值范围应为 0x00~0xFF")
                return

        def job():
            u = self._uart_live()
            if mode == "rx":
                value = u.spi_read(chip, addr)
                self._msg_q.put(("log", f"快捷SPI 读 {chip_label}[0x{addr:02X}] => 0x{value:02X}"))
            else:
                ack = u.spi_write(chip, addr, data)
                self._msg_q.put(("log",
                                 f"快捷SPI 写 {chip_label}[0x{addr:02X}] <= 0x{data:02X}, ACK=0x{ack:02X}"))

        self._run_async("快捷SPI", job)

    def _do_ping(self) -> None:
        def job():
            d = self._uart_live().ping()
            self._msg_q.put(("log", f"Ping OK, ACK data=0x{d:02X}"))
        self._run_async("Ping", job)

    def _do_fw_version(self) -> None:
        def job():
            ver = self._uart_live().firmware_version()
            self._msg_q.put(("log", f"FW version=0x{ver:02X} ({ver})"))
        self._run_async("固件版本", job)

    def _do_error_query(self) -> None:
        def job():
            err = self._uart_live().error_query()
            self._msg_q.put(("log", f"Last error=0x{err:02X}"))
        self._run_async("错误查询", job)

    def _do_boot_status(self) -> None:
        def job():
            st = self._uart_live().boot_status()
            self._msg_q.put(("log", f"Boot status=0x{st:02X} busy={(st>>7)&1} "
                                    f"done={(st>>6)&1} chip={st & 0x0F}"))
        self._run_async("Boot 状态", job)

    def _do_boot_run(self) -> None:
        def job():
            self._msg_q.put(("log", "Boot 启动 (可能需数十秒)..."))
            u = self._uart_live()
            d = u.boot_run(ack_timeout=60.0)
            self._msg_q.put(("log", f"Boot 完成, ACK data=0x{d:02X}"))
            self._refresh_adc_decode_mode(u, source="Boot后")
        self._run_async("Boot", job)

    def _do_chip_ids(self) -> None:
        def job():
            v = self._uart_live().read_common_chip_info()
            self._msg_q.put(("log",
                "Chip IDs: "
                f"SI5340[02]=0x{v['si5340_pn_hi']:02X}, "
                f"SI5340[03]=0x{v['si5340_pn_lo']:02X}, "
                f"SI5340[0C]=0x{v['si5340_grade']:02X}, "
                f"AD9640[01]=0x{v['ad9640_chip_id']:02X}, "
                f"AD9117[1F]=0x{v['ad9117_version']:02X}"))
        self._run_async("读芯片 ID/版本", job)

    # ================================================================= DAC jobs
    def _do_dac_apply(self) -> None:
        wave, freq_hz, amp_pct, hb_bypass = self._dac_params()

        def job():
            u = self._uart_live()
            info = u.dac_config(wave=wave, freq_hz=freq_hz, amp_pct=amp_pct, hb_bypass=hb_bypass)
            fw = int(info.get("freq_word", 0))
            actual = float(info.get("freq_hz", 0.0))
            hb_str = " [半带OFF]" if hb_bypass else ""
            self._msg_q.put(("log",
                f"DAC 参数已应用: wave={wave}, freq_req={freq_hz/1e3:.3f}kHz, "
                f"word=0x{fw:04X}, freq_act={actual/1e3:.3f}kHz, amp={amp_pct}%{hb_str}"))
            self._msg_q.put(("dac_freq", actual))
        self._run_async("DAC 应用参数", job)

    def _do_dac_on(self) -> None:
        wave, freq_hz, amp_pct, hb_bypass = self._dac_params()

        def job():
            u = self._uart_live()
            info = u.dac_config(wave=wave, freq_hz=freq_hz, amp_pct=amp_pct, hb_bypass=hb_bypass)
            d = u.dac_tone_enable(True)
            actual = float(info.get("freq_hz", dac_freq_word_to_hz(hz_to_dac_freq_word(freq_hz))))
            hb_str = " [半带OFF]" if hb_bypass else ""
            self._msg_q.put(("log",
                f"DAC 已启动: wave={wave}, f={actual/1e3:.3f}kHz, amp={amp_pct}%, ACK=0x{d:02X}{hb_str}"))
            self._msg_q.put(("dac", True))
            self._msg_q.put(("dac_freq", actual))
        self._run_async("DAC 启动", job)

    def _do_dac_off(self) -> None:
        def job():
            d = self._uart_live().dac_tone_enable(False)
            self._msg_q.put(("log", f"DAC 已停止, ACK=0x{d:02X}"))
            self._msg_q.put(("dac", False))
        self._run_async("DAC 停止", job)

    # ================================================================= waveform player
    def _do_wave_browse(self) -> None:
        path, _ = QtWidgets.QFileDialog.getOpenFileName(
            self, "选择 IQ 波形文件", "",
            "Waveform/binary (*.WAVEFORM *.waveform *.bin);;All files (*.*)")
        if path:
            self.wave_path_edit.setText(path)

    def _do_wave_polarity(self, _checked=False) -> None:
        if not (self._uart and self._uart.is_open):
            return
        swap = self.wave_swap_chk.isChecked()
        neg = self.wave_negq_chk.isChecked()

        def job():
            d = self._uart_live().wave_set_polarity(swap_iq=swap, neg_q=neg)
            self._msg_q.put(("log",
                f"波形极性: SWAP_IQ={self._onoff(swap)} NEG_Q={self._onoff(neg)}, ACK=0x{d:02X}"))
        self._run_async("波形极性", job)

    def _do_wave_upload(self) -> None:
        path = self.wave_path_edit.text().strip()
        if not path:
            self._log("请先选择波形文件 (.WAVEFORM 或 .bin)")
            return
        try:
            data = RfAddaUart.wave_read_file(path, endian="auto")
        except Exception as e:  # noqa: BLE001
            self._log(f"读取波形文件失败: {e}")
            return
        n_samples = len(data) // 4
        if n_samples == 0:
            self._log("波形文件为空")
            return
        loop_req = int(self.wave_loop_spin.value())
        loop_len = loop_req if loop_req > 0 else n_samples
        swap = self.wave_swap_chk.isChecked()
        neg = self.wave_negq_chk.isChecked()

        def job():
            u = self._uart_live()
            u.wave_enable(False)
            self._msg_q.put(("log",
                f"波形上传: file={os.path.basename(path)} samples={n_samples} "
                f"loop={loop_len} SWAP_IQ={self._onoff(swap)} NEG_Q={self._onoff(neg)}"))
            t0 = time.time()
            n_chunks_total = (len(data) + 1023) // 1024

            def progress(done, total):
                if done % 64 == 0 or done == total:
                    pct = 100.0 * done / total
                    rate = done * 1024 / max(time.time() - t0, 1e-3)
                    self._msg_q.put(("log", f"  上传 {done}/{total} {pct:5.1f}% {rate/1024:.1f} KiB/s"))
            u.wave_upload_bytes(data, progress=progress)
            self._msg_q.put(("log", f"波形上传完成: {n_chunks_total} chunks, {time.time()-t0:.1f}s"))
            u.wave_set_polarity(swap_iq=swap, neg_q=neg)
            u.wave_set_loop_len(loop_len)
            self._msg_q.put(("log", f"波形参数已写入: loop_len={loop_len} — 点击「启动播放」"))
        self._run_async("波形上传", job)

    def _do_wave_play_on(self) -> None:
        loop_req = int(self.wave_loop_spin.value())

        def job():
            u = self._uart_live()
            if loop_req > 0:
                u.wave_set_loop_len(loop_req)
            d = u.wave_enable(True)
            self._msg_q.put(("log", f"波形播放已启动, ACK=0x{d:02X}"
                             + (f" (loop_len={loop_req})" if loop_req > 0 else "")))
            self._msg_q.put(("dac", True))
        self._run_async("波形启动", job)

    def _do_wave_play_off(self) -> None:
        def job():
            d = self._uart_live().wave_enable(False)
            self._msg_q.put(("log", f"波形播放已停止, ACK=0x{d:02X}"))
            self._msg_q.put(("dac", False))
        self._run_async("波形停止", job)

    # ================================================================= capture
    def _capture(self, label: str, *, ensure_dac: bool | None = None) -> None:
        n = self._n_samples()
        dac_params = self._dac_params() if ensure_dac is True else None

        def job():
            u = self._uart_live()
            self._sync_rx_chain_config()
            u.set_rx_config(dec_ratio=self._dec_ratio, capture_mode=self._capture_mode,
                            fir_bypass=not self._fir_feature_on,
                            iq_bypass=not self._iq_feature_on,
                            fir_sel=self._fir_sel)
            if ensure_dac is True:
                assert dac_params is not None
                wave, freq_hz, amp_pct, hb_bypass = dac_params
                info = u.dac_config(wave=wave, freq_hz=freq_hz, amp_pct=amp_pct, hb_bypass=hb_bypass)
                u.dac_tone_enable(True)
                self._msg_q.put(("dac", True))
                self._msg_q.put(("dac_freq", float(info.get("freq_hz", freq_hz))))
                time.sleep(0.05)
            elif ensure_dac is False:
                u.dac_tone_enable(False)
                self._msg_q.put(("dac", False))
                time.sleep(0.05)
            self._msg_q.put(("log", f"{label}: arm N={n}..."))
            t0 = time.perf_counter()
            if self._analysis_mode == "iq":
                si, sq = u.capture_iq(n)
                si = self._decode_adc_samples_auto(si)
                sq = self._decode_adc_samples_auto(sq)
                samples = [v for pair in zip(si, sq) for v in pair]
            elif self._analysis_mode == "q":
                samples = self._decode_adc_samples_auto(u.capture_all(n, channel=ADC_CHAN_Q))
            else:
                samples = self._decode_adc_samples_auto(u.capture_all(n, channel=ADC_CHAN_I))
            dt = time.perf_counter() - t0
            self._msg_q.put(("log", f"{label}: 完成 {len(samples)} 点, {dt:.2f}s"))
            self._msg_q.put(("samples", (samples, label)))
        self._run_async(label, job)

    def _do_adc_capture(self) -> None:
        self._sync_rx_chain_config()
        if self._capture_mode == CAPTURE_MODE_STREAM:
            self._do_stream_start()
            return
        self._capture("ADC 采集")

    def _do_loopback_test(self) -> None:
        self._capture("环回测试", ensure_dac=True)

    def _do_stream_start(self) -> None:
        if not (self._uart and self._uart.is_open):
            QtWidgets.QMessageBox.warning(self, APP_TITLE, "请先连接串口")
            return
        if self._streaming:
            QtWidgets.QMessageBox.information(self, APP_TITLE, "连续流已在运行")
            return
        if self._worker and self._worker.is_alive():
            QtWidgets.QMessageBox.information(self, APP_TITLE, "上一操作仍在进行，请稍候")
            return
        self._stream_stop_evt.clear()
        self._set_actions_enabled(False)
        self.status_label.setText("进行中: 连续流...")

        def target():
            try:
                self._stream_job()
                self._msg_q.put(("done", "连续流"))
            except Exception as e:  # noqa: BLE001
                self._msg_q.put(("error", str(e)))
        self._worker = threading.Thread(target=target, daemon=True)
        self._worker.start()

    def _do_stream_stop(self) -> None:
        if self._streaming:
            self._stream_stop_evt.set()
            self.status_label.setText("停止中: 连续流...")

    def _stream_job(self) -> None:
        u = self._uart_live()
        self._sync_rx_chain_config()
        u.set_rx_config(dec_ratio=self._dec_ratio, capture_mode=CAPTURE_MODE_STREAM,
                        fir_bypass=not self._fir_feature_on,
                        iq_bypass=not self._iq_feature_on,
                        fir_sel=self._fir_sel)
        win_n = max(256, self._n_samples())
        ring_i: deque[int] = deque(maxlen=win_n)
        ring_q: deque[int] = deque(maxlen=win_n)
        carry = bytearray()
        last_push = time.perf_counter()
        pushed = 0
        self._msg_q.put(("stream_state", True))
        self._msg_q.put(("log", f"连续流启动: 窗口={win_n} 点，停止请点“停止连续流”"))
        u.adc_stream_start_continuous()
        try:
            while not self._stream_stop_evt.is_set():
                chunk = u.adc_stream_read_bytes(4096, timeout=0.1)
                if not chunk:
                    continue
                carry.extend(chunk)
                usable = (len(carry) // 4) * 4
                if usable <= 0:
                    continue
                payload = bytes(carry[:usable])
                del carry[:usable]
                si_u, sq_u = decode_stream_iq_payload(payload)
                ring_i.extend(self._decode_adc_samples_auto(si_u))
                ring_q.extend(self._decode_adc_samples_auto(sq_u))
                pushed += len(si_u)
                now = time.perf_counter()
                if now - last_push >= 0.2 and ring_i:
                    self._msg_q.put(("samples", (self._ring_to_samples(ring_i, ring_q), "ADC 连续流")))
                    last_push = now
        finally:
            tail, (status, xor_rx, _ck) = u.adc_stream_stop_and_drain(
                idle_timeout=0.15, overall_timeout=2.0)
            if tail:
                carry.extend(tail)
                usable = (len(carry) // 4) * 4
                if usable > 0:
                    si_u, sq_u = decode_stream_iq_payload(bytes(carry[:usable]))
                    ring_i.extend(self._decode_adc_samples_auto(si_u))
                    ring_q.extend(self._decode_adc_samples_auto(sq_u))
            if ring_i:
                self._msg_q.put(("samples", (self._ring_to_samples(ring_i, ring_q), "ADC 连续流")))
            self._msg_q.put(("log",
                f"连续流已停止: payload样点≈{pushed}, status=0x{status:02X}, xor=0x{xor_rx:02X}"))
            self._msg_q.put(("stream_state", False))

    def _ring_to_samples(self, ring_i: deque, ring_q: deque) -> list[int]:
        if self._analysis_mode == "iq":
            return [v for pair in zip(ring_i, ring_q) for v in pair]
        if self._analysis_mode == "q":
            return list(ring_q)
        return list(ring_i)

    # ================================================================= NCO / RX / IQ
    def _do_nco_clear(self) -> None:
        def job():
            u = self._uart_live()
            u.set_nco_freq_word(0)
            self._msg_q.put(("nco", (0, 0.0)))
            self._msg_q.put(("log", "NCO 已清零: word=0x0000, freq=0.00 kHz"))
        self._run_async("清零 NCO", job)

    def _do_apply_nco(self) -> None:
        freq_hz = float(self.nco_freq_spin.value()) * 1e3
        adc_fs_hz = self._fs_hz()

        def job():
            u = self._uart_live()
            word, actual_hz = u.set_nco_frequency_hz(freq_hz, adc_fs_hz=adc_fs_hz)
            self._msg_q.put(("nco", (word, actual_hz)))
            self._msg_q.put(("log",
                f"NCO 设定: req={freq_hz/1e3:.2f}kHz → word=0x{word:04X}, actual={actual_hz/1e3:.2f}kHz"))
        self._run_async("应用 NCO", job)

    def _do_apply_rx_cfg(self) -> None:
        self._sync_rx_chain_config()
        dec, cm = self._dec_ratio, self._capture_mode
        iq_on, fir_on = self._iq_feature_on, self._fir_feature_on
        fir_sel = self._fir_sel

        def job():
            u = self._uart_live()
            data = u.set_rx_config(dec_ratio=dec, capture_mode=cm,
                                   fir_bypass=not fir_on, iq_bypass=not iq_on,
                                   fir_sel=fir_sel)
            self._msg_q.put(("log",
                f"RX cfg 应用: dec={dec} mode={cm} FIR={self._onoff(fir_on)} "
                f"bank={FIR_BANK_LABELS[fir_sel]} "
                f"IQ={self._onoff(iq_on)} ACK=0x{data:02X}"))
        self._run_async("应用 RX 配置", job)

    def _do_apply_iq(self) -> None:
        self._sync_iq_balance()
        op1, op2, oi, oq = self._iq_op1, self._iq_op2, self._iq_off_i, self._iq_off_q

        def job():
            u = self._uart_live()
            self._sync_rx_chain_config()
            if not self._iq_feature_on:
                self._iq_feature_on = True
                u.set_rx_config(dec_ratio=self._dec_ratio, capture_mode=self._capture_mode,
                                fir_bypass=not self._fir_feature_on, iq_bypass=False,
                                fir_sel=self._fir_sel)
                self._msg_q.put(("iq_feature_on", True))
                self._msg_q.put(("log", "检测到 IQ处理=OFF，已自动切换为 ON 并重下发 RX 配置"))
            u.set_iq_op1(op1)
            u.set_iq_op2(op2)
            u.set_iq_offset_i(oi)
            u.set_iq_offset_q(oq)
            self._msg_q.put(("log", f"IQ 平衡写入: op1=0x{op1:04X} op2=0x{op2:04X} offI={oi} offQ={oq}"))
        self._run_async("应用 IQ 平衡", job)

    def _do_reset_iq(self) -> None:
        self.iq_op1_edit.setText("0x4000")
        self.iq_op2_edit.setText("0x0000")
        self.iq_offi_spin.setValue(0)
        self.iq_offq_spin.setValue(0)
        self._iq_op1, self._iq_op2, self._iq_off_i, self._iq_off_q = 0x4000, 0, 0, 0
        self._refresh_iq_state_label()

        def job():
            u = self._uart_live()
            u.set_iq_op1(0x4000)
            u.set_iq_op2(0)
            u.set_iq_offset_i(0)
            u.set_iq_offset_q(0)
            self._msg_q.put(("log", "IQ 平衡复位: op1=0x4000 op2=0 offI=0 offQ=0"))
        self._run_async("复位 IQ", job)

    # ================================================================= plots
    def _plot_time(self) -> None:
        if not self._samples:
            return
        fs = self._fs_hz()
        dt_us = 1e6 / fs if fs > 0 else 1.0
        chart = _chart_label(self._capture_label) or "Time domain"
        if self._is_iq_parallel():
            si, sq = self._iq_samples_pair()
            n = min(len(si), len(sq))
            if n <= 0:
                return
            stride = _plot_stride(n, MAX_TIME_PLOT_POINTS)
            x = np.arange(0, n, stride, dtype=np.float64) * dt_us
            self.curve_time.setData(x, np.asarray(si[:n:stride]))
            self.curve_time_q.setData(x, np.asarray(sq[:n:stride]))
            self.curve_time_q.setVisible(True)
            self._title(self.plot_time,
                f"{chart} [IQ parallel]  I[{min(si)}..{max(si)}]  Q[{min(sq)}..{max(sq)}]  "
                f"shown={len(x)}/{n}")
        else:
            s = self._samples
            n = len(s)
            stride = _plot_stride(n, MAX_TIME_PLOT_POINTS)
            x = np.arange(0, n, stride, dtype=np.float64) * dt_us
            self.curve_time.setData(x, np.asarray(s[::stride]))
            self.curve_time_q.setVisible(False)
            if n > 1:
                v = samples_to_volts(s)
                self._title(self.plot_time,
                    f"{chart}  std={_std(v):.4f}  unique={len(set(s))}  [{min(s)}..{max(s)}]  "
                    f"shown={len(x)}/{n}")
            else:
                self._title(self.plot_time, chart)

    def _ensure_fft_cache(self) -> bool:
        if not self._samples:
            QtWidgets.QMessageBox.information(self, APP_TITLE, "尚无采集数据")
            return False
        if self._fft_cache is not None:
            return True
        try:
            if self._is_iq_parallel():
                si, sq = self._iq_samples_pair()
                fi, mi, mdi, ppi = compute_fft_spectrum(
                    si, fs_hz=self._fs_hz(), window=self._window_key, **self._dc_kwargs())
                fq, mq, mdq, ppq = compute_fft_spectrum(
                    sq, fs_hz=self._fs_hz(), window=self._window_key, **self._dc_kwargs())
                self._fft_cache = {
                    "mode": "iq",
                    "i": {"freqs": fi, "mag": mi, "mag_db": mdi, "power_pct": ppi},
                    "q": {"freqs": fq, "mag": mq, "mag_db": mdq, "power_pct": ppq}}
                return True
            freqs, mag, mag_db, power_pct = compute_fft_spectrum(
                self._samples, fs_hz=self._fs_hz(), window=self._window_key, **self._dc_kwargs())
        except Exception as e:  # noqa: BLE001
            QtWidgets.QMessageBox.critical(self, APP_TITLE, str(e))
            return False
        self._fft_cache = {"freqs": freqs, "mag": mag, "mag_db": mag_db, "power_pct": power_pct}
        return True

    def _fft_series(self, mode_key: str):
        assert self._fft_cache is not None
        _lbl, ylabel, key, color = FFT_MODE_BY_KEY.get(mode_key, FFT_MODE_OPTIONS[0])
        if key == "linear":
            return self._fft_cache["mag"], ylabel, key, color
        if key == "pct":
            return self._fft_cache["power_pct"], ylabel, key, color
        return self._fft_cache["mag_db"], ylabel, key, color

    def _clear_fft_peaks(self) -> None:
        for it in self._fft_peak_items:
            self.plot_fft.removeItem(it)
        self._fft_peak_items = []

    def _annotate_fft_peaks(self, freqs, y_data, *, n_peaks=5, dc_bins=2, suppress=10) -> None:
        if not y_data or len(y_data) <= dc_bins:
            return
        work = list(y_data)
        total = len(work)
        xs, ys = [], []
        for _ in range(n_peaks):
            start = max(0, dc_bins)
            if start >= total:
                break
            idx = max(range(start, total), key=lambda i: work[i])
            py = work[idx]
            if py < -180.0:
                break
            pf = freqs[idx] / 1e6
            xs.append(pf)
            ys.append(py)
            txt = pg.TextItem(f"{pf:.3f}MHz\n{py:.1f}dB", color=self._peak_color, anchor=(0.5, 1.1))
            txt.setPos(pf, py)
            self.plot_fft.addItem(txt)
            self._fft_peak_items.append(txt)
            lo, hi = max(0, idx - suppress), min(total - 1, idx + suppress)
            for i in range(lo, hi + 1):
                work[i] = -200.0
        if xs:
            sc = pg.ScatterPlotItem(xs, ys, symbol="t", size=11,
                                    brush=pg.mkBrush("#d62728"), pen=None)
            self.plot_fft.addItem(sc)
            self._fft_peak_items.append(sc)

    def _render_fft_plot(self, mode_key: str | None = None) -> None:
        if self._fft_cache is None:
            return
        mode_key = mode_key or self._fft_mode_key
        self._fft_mode_key = mode_key
        self._clear_fft_peaks()
        _lbl, ylabel, key, color = FFT_MODE_BY_KEY.get(mode_key, FFT_MODE_OPTIONS[0])
        self.plot_fft.setLabel("left", ylabel, color=self._fg)
        chart = _chart_label(self._capture_label)

        if self._fft_cache.get("mode") == "iq":
            ic, qc = self._fft_cache["i"], self._fft_cache["q"]
            yi = ic["mag"] if key == "linear" else ic["power_pct"] if key == "pct" else ic["mag_db"]
            yq = qc["mag"] if key == "linear" else qc["power_pct"] if key == "pct" else qc["mag_db"]
            fi_all = np.asarray(ic["freqs"], dtype=np.float64) / 1e6
            fq_all = np.asarray(qc["freqs"], dtype=np.float64) / 1e6
            stride_i = _plot_stride(len(fi_all), MAX_FFT_PLOT_POINTS)
            stride_q = _plot_stride(len(fq_all), MAX_FFT_PLOT_POINTS)
            self.curve_fft.setData(fi_all[::stride_i], np.asarray(yi[::stride_i]))
            self.curve_fft.setPen(_PEN_I)
            self.curve_fft_q.setData(fq_all[::stride_q], np.asarray(yq[::stride_q]))
            self.curve_fft_q.setVisible(True)
            pi = int(np.argmax(yi)) if len(yi) else 0
            pq = int(np.argmax(yq)) if len(yq) else 0
            self._title(self.plot_fft,
                f"FFT ({_lbl}) {chart}  I:{ic['freqs'][pi]/1e3:.2f}kHz  Q:{qc['freqs'][pq]/1e3:.2f}kHz  "
                f"shown~{len(fi_all[::stride_i])}/{len(fi_all)}")
            if key == "db":
                self._annotate_fft_peaks(ic["freqs"], yi)
                self._annotate_fft_peaks(qc["freqs"], yq)
        else:
            freqs = self._fft_cache["freqs"]
            y_data, ylabel, key, color = self._fft_series(mode_key)
            fx_all = np.asarray(freqs, dtype=np.float64) / 1e6
            stride = _plot_stride(len(fx_all), MAX_FFT_PLOT_POINTS)
            self.curve_fft.setData(fx_all[::stride], np.asarray(y_data[::stride]))
            self.curve_fft.setPen(pg.mkPen(color, width=1))
            self.curve_fft_q.setVisible(False)
            pidx = int(np.argmax(y_data)) if y_data else 0
            pf_khz = freqs[pidx] / 1e3
            py = y_data[pidx] if y_data else 0.0
            if key == "db":
                ptxt = f"peak={pf_khz:.2f}kHz ({py:.1f}dB)"
            elif key == "linear":
                ptxt = f"peak={pf_khz:.2f}kHz (mag={py:.3g})"
            else:
                ptxt = f"peak={pf_khz:.2f}kHz ({py:.2f}%)"
            self._title(self.plot_fft, f"FFT ({_lbl}) {chart}  {ptxt}  shown~{len(fx_all[::stride])}/{len(fx_all)}")
            if key == "db":
                self._annotate_fft_peaks(freqs, y_data)

        # DAC tone reference marker.
        if self._dac_on or self._capture_label == "环回测试":
            self.dac_tone_line.setPos(self._dac_freq_hz / 1e6)
            self.dac_tone_line.setVisible(True)
        else:
            self.dac_tone_line.setVisible(False)

        self.plot_fft.enableAutoRange(axis="xy", enable=True)

    def _on_fft_marker_moved(self) -> None:
        if self._fft_cache is None:
            return
        x_mhz = self.fft_marker.value()
        if self._fft_cache.get("mode") == "iq":
            freqs = self._fft_cache["i"]["freqs"]
            y = self._fft_cache["i"]["mag_db"]
        else:
            freqs = self._fft_cache["freqs"]
            y = self._fft_cache.get(
                {"linear": "mag", "pct": "power_pct"}.get(self._fft_mode_key, "mag_db"))
        if not freqs or y is None:
            return
        fx = np.asarray(freqs) / 1e6
        idx = int(np.argmin(np.abs(fx - x_mhz)))
        self.fft_marker.label.setFormat(f"{fx[idx]:.4f} MHz\n{y[idx]:.2f}")

    def _plot_fft_mode(self, mode_key: str) -> None:
        if not self._ensure_fft_cache():
            return
        if not self.fft_marker.isVisible():
            # Park the draggable marker at the current peak on first render.
            self.fft_marker.setVisible(True)
        self._render_fft_plot(mode_key)
        self._update_summary()

    def _render_fft_after_change(self) -> None:
        if not self._samples:
            return
        if not self._ensure_fft_cache():
            return
        self._render_fft_plot(self._fft_mode_key)

    def _clear_fft_plot(self) -> None:
        self._clear_fft_peaks()
        self.curve_fft.setData([], [])
        self.curve_fft_q.setData([], [])
        self.curve_fft_q.setVisible(False)
        self.dac_tone_line.setVisible(False)
        self._title(self.plot_fft, "FFT (auto dB after capture; 用 dB/Magnitude/Power% 切换)")

    # ================================================================= IQ constellation
    def _open_iq_constellation_window(self) -> None:
        if self._iq_win is None:
            self._iq_win = IqConstellationWindow(self)
            # Match the main window's current theme.
            self._apply_theme(self._dark)
        self._iq_win.show()
        self._iq_win.raise_()
        self._iq_win.activateWindow()
        self._refresh_iq_constellation()

    def _refresh_iq_constellation(self) -> None:
        if self._iq_win is None or not self._iq_win.isVisible():
            return
        si, sq = self._iq_samples_pair()
        self._iq_win.update_iq(si, sq)

    # ================================================================= summary / metrics
    def _update_summary(self) -> None:
        if not self._samples_raw:
            self.summary_label.setText("")
            self._clear_metrics()
            return
        cap = _chart_label(self._capture_label)
        if self._is_iq_parallel():
            si, sq = self._iq_samples_pair()
            if not si or not sq:
                self.summary_label.setText(f"{cap} [IQ parallel]  insufficient data")
                self._clear_metrics()
                return
            base = (f"{cap} [IQ parallel]  "
                    f"I:N={len(si)} unique={len(set(si))} [{min(si)}..{max(si)}]  "
                    f"Q:N={len(sq)} unique={len(set(sq))} [{min(sq)}..{max(sq)}]")
        else:
            s = self._samples
            base = (f"{cap} [{self._analysis_mode_plot_label()}]  N={len(s)}  "
                    f"unique={len(set(s))}  min={min(s)} max={max(s)}")
        if self._fft_cache is None:
            self.summary_label.setText(base)
            self._update_metrics()
            return
        if self._fft_cache.get("mode") == "iq":
            ic, qc = self._fft_cache.get("i"), self._fft_cache.get("q")
            if isinstance(ic, dict) and isinstance(qc, dict):
                ii = spectrum_summary(ic["freqs"], ic["mag_db"])
                qi = spectrum_summary(qc["freqs"], qc["mag_db"])
                base += (f"  I peak~{ii['peak_hz']/1e3:.1f}kHz({ii['peak_db']:.1f}dB)"
                         f"  Q peak~{qi['peak_hz']/1e3:.1f}kHz({qi['peak_db']:.1f}dB)")
        elif "freqs" in self._fft_cache:
            info = spectrum_summary(self._fft_cache["freqs"], self._fft_cache["mag_db"])
            base += (f"  FFT peak~{info['peak_hz']/1e3:.1f}kHz({info['peak_db']:.1f}dB)"
                     f"  floor~{info['floor_db']:.1f}dB")
        self.summary_label.setText(base)
        self._update_metrics()

    def _set_metric_labels(self, mapping: dict[str, str]) -> None:
        for key, text in mapping.items():
            if key in self._metric_name_labels:
                self._metric_name_labels[key].setText(text)

    def _clear_metrics(self) -> None:
        for v in self._metric_value_labels.values():
            v.setText("—")
        self._set_metric_labels(self.SIGNAL_METRIC_LABELS)

    def _fmt_hz(self, hz: float) -> str:
        return f"{hz/1e6:.4f} MHz" if abs(hz) >= 1e6 else f"{hz/1e3:.2f} kHz"

    def _fmt_iq_pair(self, i_val: str, q_val: str) -> str:
        return f"I:{i_val}\nQ:{q_val}"

    @staticmethod
    def _onoff(flag: bool) -> str:
        return "ON" if bool(flag) else "OFF"

    def _update_metrics(self) -> None:
        if not self._samples_raw:
            return
        self._set_metric_labels(self.SIGNAL_METRIC_LABELS)
        if self._is_iq_parallel():
            si, sq = self._iq_samples_pair()
            try:
                mi = compute_dynamic_metrics(si, fs_hz=self._fs_hz(), window=self._window_key, **self._dc_kwargs())
                mq = compute_dynamic_metrics(sq, fs_hz=self._fs_hz(), window=self._window_key, **self._dc_kwargs())
            except Exception as e:  # noqa: BLE001
                self._clear_metrics()
                self._metric_value_labels["snr"].setText(f"err: {e}")
                return
            self._metric_value_labels["fund"].setText(self._fmt_iq_pair(self._fmt_hz(mi["fund_hz"]), self._fmt_hz(mq["fund_hz"])))
            self._metric_value_labels["snr"].setText(self._fmt_iq_pair(f"{mi['snr_db']:.2f}dB", f"{mq['snr_db']:.2f}dB"))
            self._metric_value_labels["thd"].setText(self._fmt_iq_pair(f"{mi['thd_db']:.2f}dB", f"{mq['thd_db']:.2f}dB"))
            self._metric_value_labels["sinad"].setText(self._fmt_iq_pair(f"{mi['sinad_db']:.2f}dB", f"{mq['sinad_db']:.2f}dB"))
            self._metric_value_labels["enob"].setText(self._fmt_iq_pair(f"{mi['enob_bits']:.2f}b", f"{mq['enob_bits']:.2f}b"))
            self._metric_value_labels["sfdr"].setText(self._fmt_iq_pair(f"{mi['sfdr_db']:.2f}dB", f"{mq['sfdr_db']:.2f}dB"))
            self._metric_value_labels["spur"].setText(self._fmt_iq_pair(self._fmt_hz(mi["spur_hz"]), self._fmt_hz(mq["spur_hz"])))
            return
        try:
            m = compute_dynamic_metrics(self._samples, fs_hz=self._fs_hz(),
                                        window=self._window_key, **self._dc_kwargs())
        except Exception as e:  # noqa: BLE001
            self._clear_metrics()
            self._metric_value_labels["snr"].setText(f"err: {e}")
            return
        self._metric_value_labels["fund"].setText(self._fmt_hz(m["fund_hz"]))
        self._metric_value_labels["snr"].setText(f"{m['snr_db']:.2f} dB")
        self._metric_value_labels["thd"].setText(f"{m['thd_db']:.2f} dB")
        self._metric_value_labels["sinad"].setText(f"{m['sinad_db']:.2f} dB")
        self._metric_value_labels["enob"].setText(f"{m['enob_bits']:.2f} bit")
        self._metric_value_labels["sfdr"].setText(f"{m['sfdr_db']:.2f} dB")
        self._metric_value_labels["spur"].setText(self._fmt_hz(m["spur_hz"]))

    def _copy_metric_item(self, key: str) -> None:
        lbl = self._metric_name_labels.get(key)
        val = self._metric_value_labels.get(key)
        if lbl is None or val is None:
            return
        text = val.text().strip()
        if not text or text == "—":
            self.status_label.setText("该指标暂无可复制数据")
            return
        flat = " ".join(ln.strip() for ln in text.splitlines() if ln.strip())
        QtWidgets.QApplication.clipboard().setText(f"{lbl.text()}: {flat}")
        self.status_label.setText(f"已复制: {lbl.text()} = {flat}")

    def _copy_iq_metrics_row(self) -> None:
        cells = []
        for key in self.METRIC_KEYS:
            v = self._metric_value_labels[key].text().strip()
            cells.append(" ".join(ln.strip() for ln in v.splitlines() if ln.strip()))
        row = "\t".join(cells)
        QtWidgets.QApplication.clipboard().setText(row)
        self.status_label.setText("已复制指标行（Tab分隔）")

    # ================================================================= save / export
    def _load_iq_samples_from_file(self, path: str) -> tuple[list[int], str]:
        ext = Path(path).suffix.lower()
        raw = RfAddaUart.wave_read_file(path, endian="auto")
        if len(raw) < 4:
            raise ValueError("文件数据不足（需要至少 1 组 IQ）")
        words = np.frombuffer(raw, dtype="<i2")
        if words.size < 2:
            raise ValueError("文件数据不足（需要至少 2 个 int16）")
        if words.size % 2 != 0:
            words = words[:-1]
        prefer_shift2 = ext in (".iqfftbin", ".fftbin")
        s14, decode_desc = iq_words_to_s14(words, prefer_shift2=prefer_shift2)
        # .bin/.WAVEFORM are DAC playback files (now s14-direct; legacy s16 also
        # possible) -> always use the DAC per-channel playback rate for analysis.
        if ext in (".waveform", ".bin"):
            if self.fs_spin.value() != DAC_WAVE_FS_HZ / 1e6:
                self.fs_spin.setValue(DAC_WAVE_FS_HZ / 1e6)
                self._log(f"采样率已设为 DAC 波形 {DAC_WAVE_FS_HZ/1e6:.2f} MHz")
        i_part = s14[0::2]
        q_part = s14[1::2]
        if i_part.size == 0 or q_part.size == 0:
            raise ValueError("IQ 数据为空")
        n = min(i_part.size, q_part.size)
        iq = np.empty(n * 2, dtype=np.int16)
        iq[0::2] = i_part[:n]
        iq[1::2] = q_part[:n]
        return iq.astype(np.int32, copy=False).tolist(), decode_desc

    def _do_load_iq_file(self) -> None:
        path, _ = QtWidgets.QFileDialog.getOpenFileName(
            self,
            "选择 IQFFTBIN/WAVEFORM 文件",
            "",
            "IQ files (*.iqfftbin *.IQFFTBIN *.WAVEFORM *.waveform *.bin *.BIN);;All files (*.*)",
        )
        if not path:
            return
        try:
            samples, decode_desc = self._load_iq_samples_from_file(path)
        except Exception as e:  # noqa: BLE001
            QtWidgets.QMessageBox.critical(self, APP_TITLE, f"载入文件失败: {e}")
            return

        self._samples_raw = samples
        self._samples = self._analysis_samples()
        self._capture_label = f"文件导入({Path(path).suffix or 'unknown'})"
        self._fft_cache = None
        self._plot_time()
        self._refresh_iq_constellation()
        self._plot_fft_mode("db")
        self._log(
            f"已导入 {Path(path).name}: IQ样点={len(samples)//2}, 分析模式={self._analysis_mode_plot_label()}, 解码={decode_desc}"
        )

    def _save_csv(self) -> None:
        if not self._samples:
            QtWidgets.QMessageBox.information(self, APP_TITLE, "尚无采集数据")
            return
        ts = time.strftime("%Y%m%d_%H%M%S")
        path, _ = QtWidgets.QFileDialog.getSaveFileName(
            self, "保存 CSV", f"adc_capture_{ts}.csv", "CSV (*.csv);;All (*.*)")
        if not path:
            return
        with Path(path).open("w", encoding="utf-8") as f:
            f.write("index,sample14,sample_hex,voltage\n")
            for i, (s, v) in enumerate(zip(self._samples, samples_to_volts(self._samples))):
                f.write(f"{i},{s},0x{s & 0xFFFF:04X},{v:.8f}\n")
        self._log(f"已保存 {path}")

    def _save_matlab_bin(self) -> None:
        if not self._samples:
            QtWidgets.QMessageBox.information(self, APP_TITLE, "尚无采集数据")
            return
        ts = time.strftime("%Y%m%d_%H%M%S")
        path, _ = QtWidgets.QFileDialog.getSaveFileName(
            self, "导出 MATLAB BIN", f"adc_capture_{ts}.bin", "BIN (*.bin);;All (*.*)")
        if not path:
            return
        export_matlab_ifft_bin(path, self._samples)
        self._log(f"已导出 MATLAB BIN: {path}")

    def _open_matlab_ifft_script(self) -> None:
        base = Path(__file__).resolve()
        script = base.parent.parent / "adc" / "adc_ifft_analysis.m"
        if not script.exists():
            # Backward-compatible fallback for older layouts.
            script = base.with_name("adc_ifft_analysis.m")
        if not script.exists():
            QtWidgets.QMessageBox.critical(self, APP_TITLE, f"脚本不存在:\n{script}")
            return
        matlab = os.environ.get("MATLAB_EXE", "matlab")
        sp = str(script).replace("\\", "/")
        try:
            subprocess.Popen([matlab, "-nosplash", "-r", f"try, edit('{sp}'); catch, end"])
            self._log(f"已启动 MATLAB 并打开脚本: {script}")
            return
        except Exception as e:  # noqa: BLE001
            self._log(f"调用 matlab 失败: {e}; 尝试系统关联打开")
        try:
            os.startfile(str(script))  # type: ignore[attr-defined]
        except Exception as e:  # noqa: BLE001
            QtWidgets.QMessageBox.critical(self, APP_TITLE, f"无法打开 MATLAB 脚本: {e}")

    def closeEvent(self, event) -> None:  # noqa: N802
        try:
            self._do_stream_stop()
            if self._worker and self._worker.is_alive():
                self._worker.join(timeout=1.0)
            if self._uart:
                self._uart.close()
        except Exception:
            pass
        super().closeEvent(event)


def main() -> int:
    app = QtWidgets.QApplication(sys.argv)
    app.setApplicationName(APP_TITLE)
    app.setFont(_default_console_font(10))
    win = AddaTestApp()
    win.show()
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
