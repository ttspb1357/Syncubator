import time
import math
import threading
import subprocess
import os
import signal
import logging
import json
import copy
import glob
import select
import termios
from collections import deque
import numpy as np
from flask import Flask, jsonify, request, Response
import RPi.GPIO as GPIO
import board
import busio
from hx711 import HX711
import adafruit_tmp117
import adafruit_bme680
import adafruit_vl53l4cd
from adafruit_bus_device.i2c_device import I2CDevice
from adafruit_ads1x15.ads1115 import ADS1115
from adafruit_ads1x15.analog_in import AnalogIn

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger("syncubator")

app = Flask(__name__)

# ============================================================
# GPIO PIN CONFIGURATION (BCM)
# ============================================================
DT_PINS = [22, 5, 19, 21]
SCK_PIN = 17
HEATER_PIN_A, HEATER_PIN_B, HUMIDIFIER_PIN = 23, 24, 16
MOTOR_UP_PIN, MOTOR_DOWN_PIN = 25, 26
OXYGEN_SERVO_PIN = 18

# CONSTANTS & CALIBRATION
# ============================================================
CAL_FACTORS = [103.20,109.49,93.19,126.30]

ZERO_OFFSETS = [
    -56439.01,
    -317680.41,
    253525.71,
    -111909.54
]

RELAY_ACTIVE_LOW = True

TEMP_HYSTERESIS = 1.5
HUM_HYSTERESIS = 1.5
OXYGEN_HYSTERESIS = 1.5  # percentage points, on the measured O2 reading

# ---- Alarm engine tuning (see ALARM ENGINE section below) ----
# Lid actuator on the bed motor's L298N, second channel (IN3/IN4). Tapping Open retracts it
# for LID_OPEN_S (lid opens), tapping Close extends it for LID_CLOSE_S (lid closes). Open is
# refused until the lid has been closed again, so the lid can never be opened too far.
# If the actuator runs the wrong way, swap the two pin numbers.
LID_RETRACT_PIN, LID_EXTEND_PIN = 12, 20   # L298N IN3, IN4
LID_OPEN_S, LID_CLOSE_S = 6.0, 6.0
# Phototherapy light: the 4th relay channel (IN wired to GPIO 4, physical pin 7). The light's black
# wire is on the relay's COM and the buck converter's OUT- on NO, so the light is on only while the
# relay is on. Always off at start-up; the on/off state is deliberately not saved.
PHOTO_PIN = 4
# Smoke sensor (MQ-2 "flying fish" module): its DO output goes LOW when smoke is detected. DO is wired
# through a resistor divider (5 V -> 3.3 V) to GPIO 9 (physical pin 21), with the divider's bottom to GND.
# The sensor's heater needs about 2 minutes before its output means anything.
SMOKE_PIN = 9
SMOKE_WARMUP_S = 120
BUZZER_PIN = 27                 # free BCM pin; harmless to drive with nothing attached
ALARM_ONSET_DELAY_S = 10        # condition must hold this long before firing
ALARM_SILENCE_S = 120           # audio pause after acknowledge, then re-sounds
# Alarms that must not wait the full onset delay (smoke should sound within about a second)
ALARM_ONSET_OVERRIDE_S = {"smoke": 1.0}
HEATER_RUNAWAY_MARGIN_C = 3.0   # above target before the heater is called stuck-on

# Buzzer cadence per priority: (on_seconds, off_seconds)
BUZZER_PATTERNS = {"high": (0.15, 0.15), "medium": (0.30, 0.70), "low": (0.25, 3.0)}

# Operator-tunable thresholds, persisted to config.json via /alarms/limits.
alarm_limits = {
    "air_temp_low": 30.0,  "air_temp_high": 38.0,
    "humidity_low": 30.0,  "humidity_high": 85.0,
    "o2_low": 18.0,        "o2_high": 40.0,
    # SpO2 / pulse: newborn placeholders -- to be set by the clinical advisor.
    "spo2_low": 90.0,      "spo2_high": 98.0,
    "pulse_low": 100.0,    "pulse_high": 180.0,
    # Skin temperature (YSI-400 probe): placeholders -- to be set by the clinical advisor.
    "skin_temp_low": 36.0, "skin_temp_high": 37.5,
}

# Bed Distance Bounds (cm)
DIST_UP_MIN, DIST_UP_MAX, DIST_UP_TARGET = 8.0, 15.0, 19.2
DIST_DOWN_MIN, DIST_DOWN_MAX, DIST_DOWN_TARGET = 15.0, 25.0, 12.0

# Safety: max time a bed motor is allowed to run before we force-stop it
BED_MOVE_TIMEOUT_S = 20.0

# Oxygen valve servo: level 0-7 maps to a servo angle
OXYGEN_LEVEL_MIN, OXYGEN_LEVEL_MAX = 0, 7
OXYGEN_ANGLE_BASE, OXYGEN_ANGLE_STEP = 65, 10  # angle = BASE + STEP * level

# Oxygen SENSOR (ADS1115 + analog O2 cell) calibration
# This is a separate device from the valve servo above — it measures the
# actual O2 concentration (%) inside the incubator rather than setting flow.
OXYGEN_SENSOR_ADDRESS = 0x4A
OXYGEN_SENSOR_CHANNEL = 0

# Skin temperature probe: YSI-400 thermistor (2252 ohm at 25 C) on the same ADS1115, channel A3.
# Wiring: 3.3 V -> SKIN_R_REF (five 2.2 k in series) -> A3 -> probe (jack tip) -> GND (jack sleeve).
# SKIN_R_REF should be the MEASURED resistance of that string, not the nominal 11000.
SKIN_CHANNEL = 3
SKIN_R_REF = 11000.0
SKIN_VDD = 3.3            # supply the divider is fed from
SKIN_VDD_CHANNEL = None   # set to 1 if ADS A1 is wired to that 3.3 V, so the supply is measured, not assumed
SKIN_SAMPLES = 8          # readings per second; the median is used
SKIN_R_SHORT = 150.0      # below this the probe lead is shorted (a YSI-400 is still ~150 ohm at 100 C)
SKIN_RANGE_C = (5.0, 60.0)  # readings outside this are not a skin temperature
# Steinhart-Hart coefficients for the YSI-400 curve (checks: 2252 ohm = 25.0 C, 1355 ohm = 37.0 C)
SKIN_SH_A, SKIN_SH_B, SKIN_SH_C = 1.468e-3, 2.383e-4, 1.007e-7
O2_V_ZERO = 0.0
O2_ZERO_PCT = 0.0
O2_V_AIR = 1.4
O2_AIR_PCT = 20.9
O2_SLOPE = (O2_AIR_PCT - O2_ZERO_PCT) / (O2_V_AIR - O2_V_ZERO)  # %/V

# SpO2: Contec CMS60C pulse oximeter on USB (Silicon Labs CP2102 USB-serial bridge).
# Protocol, checked on our unit 2026-10-13: 115200 baud 8N1. Commands are 9 bytes,
# 7D 81 <cmd> 80 80 80 80 80 80 (A1 = start live data, A2 = stop, AF = keep-alive).
# Live data arrives as 9-byte frames at 60 per second: 0x01, one byte holding the top
# bit of each of the next seven bytes, then seven data bytes (bit 7 always set).
SPO2_PORT_GLOB = "/dev/serial/by-id/usb-Silicon_Labs_CP210*"  # stable name for the oximeter
SPO2_PORT_FALLBACK = "/dev/ttyUSB0"
SPO2_KEEPALIVE_S = 4.0        # Contec devices can stop streaming without a keep-alive
SPO2_NO_DATA_S = 3.0          # no frame for this long -> NO_DATA, resend start
SPO2_REOPEN_S = 10.0          # still nothing -> close and reopen the port
SPO2_PLETH_POINTS = 60        # 1 s of pulse waveform sent to the app
# Readings outside these ranges mean "no valid reading" (the device sends 0 with no finger)
SPO2_VALID_RANGE = (35, 100)
PULSE_VALID_RANGE = (25, 250)

# ============================================================
# HARDWARE INITIALIZATION
# ============================================================
GPIO.setwarnings(False)
GPIO.setmode(GPIO.BCM)
for pin in [HEATER_PIN_A, HEATER_PIN_B, HUMIDIFIER_PIN, MOTOR_UP_PIN, MOTOR_DOWN_PIN]:
    GPIO.setup(pin, GPIO.OUT)

def relay_write(pin, on):
    level = (GPIO.LOW if on else GPIO.HIGH) if RELAY_ACTIVE_LOW else (GPIO.HIGH if on else GPIO.LOW)
    GPIO.output(pin, level)

# Initial state: All OFF
for p in [HEATER_PIN_A, HEATER_PIN_B, HUMIDIFIER_PIN, MOTOR_UP_PIN, MOTOR_DOWN_PIN]:
    relay_write(p, False)

# Oxygen valve servo (PWM)
GPIO.setup(OXYGEN_SERVO_PIN, GPIO.OUT)
oxygen_servo = GPIO.PWM(OXYGEN_SERVO_PIN, 50)
oxygen_servo.start(0)
oxygen_lock = threading.Lock()  # serializes servo moves separately from the state lock

# Alarm buzzer (plain on/off active buzzer, not PWM). Safe to configure and
# drive even with nothing wired to the pin yet.
GPIO.setup(BUZZER_PIN, GPIO.OUT)
GPIO.output(BUZZER_PIN, GPIO.LOW)

# Smoke sensor input (external divider, no internal pull)
GPIO.setup(SMOKE_PIN, GPIO.IN)

# Phototherapy relay: driven to "off" in the same call that makes the pin an output, so it never clicks on.
GPIO.setup(PHOTO_PIN, GPIO.OUT, initial=GPIO.HIGH if RELAY_ACTIVE_LOW else GPIO.LOW)

# Lid actuator: both inputs low = stopped
for _p in (LID_RETRACT_PIN, LID_EXTEND_PIN):
    GPIO.setup(_p, GPIO.OUT)
    GPIO.output(_p, GPIO.LOW)

def oxygen_level_to_angle(level):
    return OXYGEN_ANGLE_BASE + OXYGEN_ANGLE_STEP * level

def set_servo_angle(angle):
    duty = 2.5 + angle / 18
    oxygen_servo.ChangeDutyCycle(duty)
    time.sleep(0.8)
    oxygen_servo.ChangeDutyCycle(0)  # stop sending pulses once the servo has settled

i2c = busio.I2C(board.SCL, board.SDA)
tmp1, tmp2, bme, ms8607_hum, tof = None, None, None, None, None
scales = [None] * len(DT_PINS)   # filled in by init_scales()
o2_chan = None
ads = None
skin_chan = None
# One ADS1115 serves both the O2 cell and the skin probe; its input multiplexer is shared,
# so every conversion must hold this lock.
ads_lock = threading.Lock()

def init_hardware():
    global tmp1, tmp2, bme, ms8607_hum, tof, scales, o2_chan, ads, skin_chan
    log.info("--- Initializing Hardware ---")
    try:
        tmp1 = adafruit_tmp117.TMP117(i2c, address=0x48)
        log.info("[OK] TMP117 #1")
    except Exception as e:
        log.warning(f"[ERR] TMP117 #1: {e}")

    try:
        tmp2 = adafruit_tmp117.TMP117(i2c, address=0x49)
        log.info("[OK] TMP117 #2")
    except Exception as e:
        log.warning(f"[ERR] TMP117 #2: {e}")

    try:
        try:
            bme = adafruit_bme680.Adafruit_BME680_I2C(i2c, address=0x77)
        except Exception:
            bme = adafruit_bme680.Adafruit_BME680_I2C(i2c, address=0x76)
        log.info("[OK] BME68x")
    except Exception as e:
        log.warning(f"[ERR] BME68x: {e}")

    try:
        ms8607_hum = I2CDevice(i2c, 0x40)
        log.info("[OK] MS8607")
    except Exception as e:
        log.warning(f"[ERR] MS8607: {e}")

    try:
        tof = adafruit_vl53l4cd.VL53L4CD(i2c)
        tof.start_ranging()
        log.info("[OK] VL53L4CD (Bed Distance)")
    except Exception as e:
        tof = None
        log.warning(f"[ERR] VL53L4CD: {e}")

    try:
        ads = ADS1115(i2c, address=OXYGEN_SENSOR_ADDRESS)
        o2_chan = AnalogIn(ads, OXYGEN_SENSOR_CHANNEL)
        skin_chan = AnalogIn(ads, SKIN_CHANNEL)
        log.info("[OK] ADS1115 O2 Sensor + skin probe")
    except Exception as e:
        log.warning(f"[ERR] ADS1115 O2 Sensor: {e}")


# The HX711 library retries a read forever when a load-cell board doesn't
# answer, so setting the scales up here used to block the whole app (no
# /status, no alarms) whenever a board was missing. They are now set up in
# their own thread (started with the other loops) and a missing one simply
# stays at 0. All four boards share one clock pin, so scale_lock keeps the
# setup and weight_loop() from clocking them at the same time.
scale_lock = threading.Lock()

def init_scales():
    log.info("Initializing Weight Scales (in the background)...")
    for i, dt in enumerate(DT_PINS):
        with scale_lock:
            try:
                s = HX711(dt, SCK_PIN)
                s.reset()
                scales[i] = s
                log.info(f"[OK] Scale {i+1}")
            except Exception as e:
                scales[i] = None
                log.warning(f"[ERR] Scale {i+1}: {e}")

init_hardware()

# ============================================================
# SHARED STATE
# ============================================================
lock = threading.Lock()
state = {
    "weight": {"total": 0, "cells": [0, 0, 0, 0], "unit": "g", "status": "OK"},
    "climate": {
        "temp": 0, "humidity": 0, "pressure": 0,
        "target_temp": 30.0, "target_hum": 60.0,
        "control_enabled": False, "active_heater": 1,
        "heater_on": False, "humidifier_on": False,
        # Lets the alarm engine tell a real low temperature apart from a
        # dead sensor reporting 0 -- see climate_loop().
        "sensor_status": "OK"
    },
    "bed": {
        "distance": 0, "status": "idle", "moving": False,
        # NEW: lets the app tell "sensor not connected / no reading yet"
        # apart from a genuine 0cm reading, instead of both looking like 0.
        "connected": False
    },
    "oxygen": {
        # Valve control (servo, flow level 0-7)
        "level": 0, "angle": oxygen_level_to_angle(0), "moving": False,
        # Live sensor reading (ADS1115 + analog O2 cell)
        "measured_percent": 0.0, "voltage": 0.0, "sensor_status": "OK",
        # Automatic inflow control (hysteresis band around target_percent,
        # same on/off pattern as the climate heater/humidifier -- see
        # oxygen_sensor_loop())
        "target_percent": 25.0, "control_enabled": False
    },
    "spo2": {
        # Operator switch (persisted). Off: live data is still shown, but no
        # SpO2 / pulse / probe alarms are raised -- for when no baby is connected.
        "monitoring_enabled": False,
        # OK, NO_FINGER (probe empty or no valid reading), NO_DATA (port open
        # but nothing arriving), NOT_CONNECTED (no oximeter on USB)
        "status": "NOT_CONNECTED",
        "spo2": None, "pulse": None, "pi": None,   # None when not valid
        "signal": 0,                               # 0-15 signal strength
        "pleth": [],                               # last 1 s of waveform, 0-127
        "flags": None,                             # raw status bytes, for checking
        "updated": None                            # time.time() of the last frame
    }
}

# ============================================================
# SETTINGS PERSISTENCE
# ============================================================
# Everything in `state` above is in-memory only, so a restart or a power
# blip silently reverted every operator setting back to the hardcoded
# defaults -- targets, control enables, and the weight calibration
# constants alike. That made recalibration a source edit rather than
# something the running system could own, and meant a reboot quietly
# undid however the incubator had been configured.
#
# Only deliberate operator settings are persisted here. Live readings and
# transient runtime flags (`moving`, `heater_on`, `inflow` state) are
# deliberately NOT saved -- those must always start fresh from real
# hardware state on boot rather than being restored from a stale file.
CONFIG_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "config.json")

# Lid: "position" is "closed" or "open" (persisted). It turns "open" as soon as an
# open starts and "closed" only when a close finishes. "moving" is None, "opening"
# or "closing".
state["lid"] = {"position": "closed", "moving": None}

# Smoke: WARMING_UP (first SMOKE_WARMUP_S after start), OK, or SMOKE
state["smoke"] = {"status": "WARMING_UP", "warmup_left": SMOKE_WARMUP_S}

# Phototherapy light: "on" is what the relay is told to do (there is no light sensor).
state["photo"] = {"on": False}

# Skin temperature (YSI-400 on ADS1115 A3). status: OK, PROBE_OFF (nothing in the jack),
# SHORT, RANGE (reading is not a skin temperature) or NOT_CONNECTED (ADS1115 not answering).
# Like SpO2, the alarms only run while monitoring_enabled (persisted) is on.
state["skin"] = {"monitoring_enabled": False, "status": "NOT_CONNECTED",
                 "temp": None, "voltage": None, "resistance": None}

def load_config():
    """Reads config.json, returning {} if missing or unreadable.

    A corrupt config must never stop the service from starting -- the
    built-in defaults above are always a valid fallback.
    """
    if not os.path.exists(CONFIG_PATH):
        log.info("No config.json yet — using built-in defaults")
        return {}
    try:
        with open(CONFIG_PATH) as f:
            return json.load(f)
    except Exception as e:
        log.warning(f"[ERR] Could not read config.json ({e}) — using built-in defaults")
        return {}

def save_config():
    """Persists current operator settings to config.json.

    Written atomically (temp file + os.replace) so a power cut mid-write
    leaves the previous config intact, rather than a half-written file
    that would fail to parse on the next boot.

    Must NOT be called while holding `lock` -- this acquires `lock`
    itself, and `lock` is a plain non-reentrant Lock, so doing so would
    deadlock the request thread.
    """
    with lock:
        data = {
            "climate": {
                "target_temp": state["climate"]["target_temp"],
                "target_hum": state["climate"]["target_hum"],
                "control_enabled": state["climate"]["control_enabled"],
                "active_heater": state["climate"]["active_heater"],
            },
            "oxygen": {
                "target_percent": state["oxygen"]["target_percent"],
                "control_enabled": state["oxygen"]["control_enabled"],
            },
            "spo2": {
                "monitoring_enabled": state["spo2"]["monitoring_enabled"],
            },
            "skin": {
                "monitoring_enabled": state["skin"]["monitoring_enabled"],
            },
            "lid": {
                "position": state["lid"]["position"],
            },
            "calibration": {
                "cal_factors": CAL_FACTORS,
                "zero_offsets": ZERO_OFFSETS,
            },
            "alarm_limits": dict(alarm_limits),
        }
    try:
        tmp_path = CONFIG_PATH + ".tmp"
        with open(tmp_path, "w") as f:
            json.dump(data, f, indent=2)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_path, CONFIG_PATH)
    except Exception as e:
        log.error(f"[ERR] Could not save config.json: {e}")

def apply_config():
    """Overlays saved settings onto the defaults, one key at a time.

    Deliberately tolerant: any missing or malformed key leaves the
    built-in default in place rather than rejecting the whole file, so a
    partially written or hand-edited config still boots.

    Safe to touch `state` without `lock` because this runs at import
    time, before any background thread has been started.
    """
    global CAL_FACTORS, ZERO_OFFSETS
    cfg = load_config()
    if not cfg:
        return

    climate = cfg.get("climate", {})
    for key in ("target_temp", "target_hum"):
        if isinstance(climate.get(key), (int, float)):
            state["climate"][key] = float(climate[key])
    if isinstance(climate.get("control_enabled"), bool):
        state["climate"]["control_enabled"] = climate["control_enabled"]
    if climate.get("active_heater") in (1, 2):
        state["climate"]["active_heater"] = int(climate["active_heater"])

    oxygen = cfg.get("oxygen", {})
    if isinstance(oxygen.get("target_percent"), (int, float)):
        state["oxygen"]["target_percent"] = float(oxygen["target_percent"])
    if isinstance(oxygen.get("control_enabled"), bool):
        state["oxygen"]["control_enabled"] = oxygen["control_enabled"]

    spo2 = cfg.get("spo2", {})
    if isinstance(spo2.get("monitoring_enabled"), bool):
        state["spo2"]["monitoring_enabled"] = spo2["monitoring_enabled"]

    skin = cfg.get("skin", {})
    if isinstance(skin.get("monitoring_enabled"), bool):
        state["skin"]["monitoring_enabled"] = skin["monitoring_enabled"]

    lid = cfg.get("lid", {})
    if lid.get("position") in ("open", "closed"):
        state["lid"]["position"] = lid["position"]

    # Calibration is validated harder than the rest: a wrong-length or
    # non-numeric list would either crash weight_loop on an index error
    # or, worse, silently produce wrong weights. So it is all-or-nothing
    # per list, falling back to the built-in values on anything odd.
    calib = cfg.get("calibration", {})
    for name in ("cal_factors", "zero_offsets"):
        vals = calib.get(name)
        if vals is None:
            continue
        valid = (
            isinstance(vals, list)
            and len(vals) == len(DT_PINS)
            and all(isinstance(v, (int, float)) for v in vals)
        )
        if not valid:
            log.warning(f"[ERR] Ignoring malformed '{name}' in config.json — using built-in default")
            continue
        if name == "cal_factors":
            CAL_FACTORS = [float(v) for v in vals]
        else:
            ZERO_OFFSETS = [float(v) for v in vals]

    limits = cfg.get("alarm_limits", {})
    for key, val in limits.items():
        if key in alarm_limits and isinstance(val, (int, float)) and not isinstance(val, bool):
            alarm_limits[key] = float(val)
        elif key not in alarm_limits:
            log.warning(f"[ERR] Ignoring unknown alarm limit '{key}' in config.json")

    log.info(
        f"Loaded config.json — climate {state['climate']['target_temp']}C/"
        f"{state['climate']['target_hum']}% (auto={state['climate']['control_enabled']}), "
        f"oxygen {state['oxygen']['target_percent']}% (auto={state['oxygen']['control_enabled']})"
    )

apply_config()

# ============================================================
# VIDEO STREAMING (IMX708 CSI SENSOR)
# ============================================================

# ---- Camera: one rpicam-vid process, any number of viewers ----------------
#
# Previously every /video_feed request started its own rpicam-vid and killed
# the previous one, so only one viewer could watch at a time (the kiosk lost
# the picture whenever the public site connected, and vice versa). Now a
# single reader thread owns the camera and keeps the latest JPEG; each
# viewer's generator just waits for new frames and forwards them at its own
# rate. The process is started on demand and stopped a few seconds after the
# last viewer leaves, so the camera is not running when nobody is watching.
#
# Per-viewer frame rate matters on the public site: the browser multiplexes
# the video and every /status poll over ONE TCP connection to Cloudflare,
# and on a long/lossy path a full-rate stream backs up in that connection
# and delays the JSON replies behind it (seen as polls timing out while the
# Pi answered instantly). The web app asks for a lower fps when it is not
# the kiosk; see CameraStreamCard in the Flutter code.

_cam_lock = threading.Lock()
_cam_cond = threading.Condition(_cam_lock)
_cam_proc = None          # running rpicam-vid, or None
_cam_latest = None        # newest complete JPEG (bytes)
_cam_seq = 0              # increments per new frame
_cam_viewers = 0
_cam_last_viewer_left = 0.0
CAMERA_IDLE_STOP_S = 5.0
CAMERA_SOURCE_FPS = 20

_CAM_CMD = [
    'rpicam-vid', '-t', '0', '--width', '640', '--height', '480',
    '--framerate', str(CAMERA_SOURCE_FPS), '--codec', 'mjpeg', '--inline',
    '--nopreview', '--flush', '--denoise', 'cdn_off', '-o', '-'
]


def _camera_reader(proc):
    """Parses MJPEG from rpicam-vid stdout and publishes each frame."""
    global _cam_proc, _cam_latest, _cam_seq
    buffer = b""
    try:
        while True:
            chunk = proc.stdout.read(4096)
            if not chunk:
                break
            buffer += chunk
            while True:
                a = buffer.find(b'\xff\xd8')
                b = buffer.find(b'\xff\xd9', a + 2) if a != -1 else -1
                if a == -1 or b == -1:
                    if a > 0:
                        buffer = buffer[a:]   # drop junk before the next SOI
                    break
                jpg = buffer[a:b + 2]
                buffer = buffer[b + 2:]
                with _cam_cond:
                    _cam_latest = jpg
                    _cam_seq += 1
                    _cam_cond.notify_all()
    except Exception as e:
        log.error(f"Camera reader error: {e}")
    finally:
        with _cam_cond:
            if _cam_proc is proc:
                _cam_proc = None
            _cam_cond.notify_all()   # wake viewers so they can notice
        log.info("Camera reader stopped")


def _camera_start_locked():
    """Starts rpicam-vid + reader thread. Caller holds _cam_lock."""
    global _cam_proc
    log.info("Starting IMX708 Camera Stream...")
    proc = subprocess.Popen(_CAM_CMD, stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, preexec_fn=os.setsid)
    _cam_proc = proc
    threading.Thread(target=_camera_reader, args=(proc,), daemon=True).start()


def _camera_stop_locked():
    global _cam_proc
    proc = _cam_proc
    _cam_proc = None
    if proc is not None:
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
        except Exception:
            pass
        log.info("Camera stopped (no viewers)")


def _camera_idle_watch():
    """Stops the camera CAMERA_IDLE_STOP_S after the last viewer leaves."""
    while True:
        time.sleep(1.0)
        with _cam_cond:
            if (_cam_proc is not None and _cam_viewers == 0
                    and time.monotonic() - _cam_last_viewer_left > CAMERA_IDLE_STOP_S):
                _camera_stop_locked()


threading.Thread(target=_camera_idle_watch, daemon=True).start()


def gen_frames(max_fps=None):
    """Multipart MJPEG generator for one viewer. max_fps caps how many of
    the camera's frames this viewer receives (None = all of them)."""
    global _cam_viewers, _cam_last_viewer_left
    min_interval = (1.0 / max_fps) if max_fps and max_fps > 0 else 0.0
    with _cam_cond:
        _cam_viewers += 1
        if _cam_proc is None:
            _camera_start_locked()
    last_seq = -1
    last_sent = 0.0
    try:
        while True:
            with _cam_cond:
                _cam_cond.wait_for(lambda: _cam_seq != last_seq or _cam_proc is None,
                                   timeout=5.0)
                if _cam_proc is None and _cam_seq == last_seq:
                    break             # camera gone: end the stream, client shows error
                if _cam_seq == last_seq:
                    continue          # 5 s with no new frame; keep waiting
                frame = _cam_latest
                last_seq = _cam_seq
            now = time.monotonic()
            if now - last_sent < min_interval:
                continue              # skip this frame for this viewer
            last_sent = now
            yield (b'--frame\r\n'
                   b'Content-Type: image/jpeg\r\n'
                   b'Content-Length: ' + str(len(frame)).encode() + b'\r\n\r\n'
                   + frame + b'\r\n')
    except GeneratorExit:
        pass
    except Exception as e:
        log.error(f"Stream Error: {e}")
    finally:
        with _cam_cond:
            _cam_viewers -= 1
            if _cam_viewers == 0:
                _cam_last_viewer_left = time.monotonic()


@app.route('/video_feed')
def video_feed():
    # ?fps=N lets a viewer on a slow link (the public site) take fewer frames.
    try:
        fps = float(request.args.get('fps', 0))
    except ValueError:
        fps = 0
    fps = min(fps, CAMERA_SOURCE_FPS) if fps > 0 else None
    return Response(gen_frames(fps), mimetype='multipart/x-mixed-replace; boundary=frame')

# ============================================================
# BACKGROUND SENSOR LOOPS
# ============================================================

def read_ms8607_hum():
    if not ms8607_hum:
        return None
    try:
        with ms8607_hum as sensor:
            sensor.write(bytes([0xF5]))
        time.sleep(0.02)
        res = bytearray(3)
        with ms8607_hum as sensor:
            sensor.readinto(res)
        raw = (res[0] << 8) | res[1]
        return max(0.0, min(100.0, ((raw * 125.0) / 65536.0) - 6.0))
    except Exception as e:
        log.debug(f"MS8607 read failed: {e}")
        return None

def read_tof():
    """Returns distance in cm, or -1.0 if unavailable/no reading yet.

    BUG FIX: adafruit_vl53l4cd's `.distance` property already returns
    centimeters (it converts from the sensor's native millimeters
    internally). The old code divided by 10.0 again on top of that,
    silently shrinking every real reading by 10x (e.g. an actual 18cm
    reading was reported as 1.8), which pushed it far outside the
    DIST_UP/DOWN bounds and made the value look broken/missing.
    """
    if not tof:
        return -1.0
    try:
        for _ in range(5):
            if tof.data_ready:
                d = tof.distance  # already in cm — do not divide again
                tof.clear_interrupt()
                return d
            time.sleep(0.2)
        return -1.0
    except Exception as e:
        log.debug(f"ToF read failed: {e}")
        return -1.0

def weight_loop():
    while True:
        w = []
        for i in range(len(scales)):
            if scales[i]:
                try:
                    with scale_lock:
                        r = scales[i].get_raw_data(3)
                    v = [x for x in r if x is not None]
                    w.append(round((sum(v) / len(v) - ZERO_OFFSETS[i]) / CAL_FACTORS[i], 2) if v else 0)
                except Exception as e:
                    log.debug(f"Scale {i+1} read failed: {e}")
                    w.append(0)
            else:
                w.append(0)
        with lock:
            # BUG FIX: total weight is the SUM of the 4 load cells, not their
            # average. The original code divided by 4.0, which silently
            # underreported the true total weight by 4x.
            state["weight"]["total"] = round(sum(w), 2)
            state["weight"]["cells"] = w
        time.sleep(0.5)

def climate_loop():
    while True:
        try:
            ts, hs = [], []
            p = 0
            if tmp1:
                ts.append(tmp1.temperature)
            if tmp2:
                ts.append(tmp2.temperature)
            if bme:
                ts.append(bme.temperature)
                hs.append(bme.humidity)
                p = bme.pressure
            mh = read_ms8607_hum()
            if mh:
                hs.append(mh)
            at = sum(ts) / len(ts) if ts else 0
            ah = sum(hs) / len(hs) if hs else 0
            with lock:
                state["climate"].update({"temp": round(at, 2), "humidity": round(ah, 2), "pressure": round(p, 2)})
                # OK only if at least one temperature sensor actually replied;
                # with none, the averaged value is a meaningless 0, not a reading.
                state["climate"]["sensor_status"] = "OK" if ts else "ERROR"
                if state["climate"]["control_enabled"]:
                    tt, th = state["climate"]["target_temp"], state["climate"]["target_hum"]
                    state["climate"]["heater_on"] = at < (tt - TEMP_HYSTERESIS) if not state["climate"]["heater_on"] else at < (tt + TEMP_HYSTERESIS)
                    state["climate"]["humidifier_on"] = ah < (th - HUM_HYSTERESIS) if not state["climate"]["humidifier_on"] else ah < (th + HUM_HYSTERESIS)
                    ap = HEATER_PIN_A if state["climate"]["active_heater"] == 1 else HEATER_PIN_B
                    relay_write(ap, state["climate"]["heater_on"])
                    relay_write(HEATER_PIN_A if ap == HEATER_PIN_B else HEATER_PIN_B, False)
                    relay_write(HUMIDIFIER_PIN, state["climate"]["humidifier_on"])
                else:
                    for pin in [HEATER_PIN_A, HEATER_PIN_B, HUMIDIFIER_PIN]:
                        relay_write(pin, False)
        except Exception as e:
            log.error(f"climate_loop error: {e}")
        time.sleep(2)

def bed_monitor():
    while True:
        d = read_tof()
        with lock:
            # NEW: always reflect whether the sensor object exists, so
            # /status can distinguish "no sensor" from "reading is 0".
            state["bed"]["connected"] = tof is not None
            if d > 0:
                state["bed"]["distance"] = round(d, 2)
        time.sleep(0.2)

def oxygen_sensor_loop():
    """Reads the analog O2 cell via the ADS1115 and converts it to a
    percentage using a simple two-point (zero/air) linear calibration.
    Also drives automatic valve control when oxygen.control_enabled is
    on: a hysteresis band around target_percent, the same on/off pattern
    climate_loop() uses for the heater/humidifier, rather than a plain
    "open until target reached" threshold. With OXYGEN_HYSTERESIS = 1.5:
    inflow opens once the reading drops 1.5 points BELOW target, and
    stays open until it rises 1.5 points ABOVE target before closing --
    so it settles into a band around target rather than chattering the
    valve open/closed right at the exact target value. The valve is only
    ever driven fully open (level 7) or fully closed (level 0) here, same
    as the heater relay has no in-between power level."""
    while True:
        if o2_chan:
            try:
                with ads_lock:
                    voltage = o2_chan.voltage
                pct = O2_ZERO_PCT + O2_SLOPE * (voltage - O2_V_ZERO)
                pct = max(0.0, min(100.0, pct))
                with lock:
                    state["oxygen"]["voltage"] = round(voltage, 4)
                    state["oxygen"]["measured_percent"] = round(pct, 2)
                    state["oxygen"]["sensor_status"] = "OK"
                    control_enabled = state["oxygen"]["control_enabled"]
                    target = state["oxygen"]["target_percent"]
                    # Derived from the real current valve position, not a
                    # separately-tracked flag -- so a manual /oxygen/level
                    # command in between auto-control cycles can never
                    # leave this out of sync with reality.
                    inflow_on = state["oxygen"]["level"] > 0
                    already_moving = state["oxygen"]["moving"]

                if control_enabled and not already_moving:
                    new_inflow_on = (
                        (pct < target - OXYGEN_HYSTERESIS) if not inflow_on
                        else (pct < target + OXYGEN_HYSTERESIS)
                    )
                    if new_inflow_on != inflow_on:
                        with lock:
                            state["oxygen"]["moving"] = True
                        target_level = OXYGEN_LEVEL_MAX if new_inflow_on else 0
                        log.info(f"Auto oxygen control: moving valve to level {target_level} (inflow_on={new_inflow_on}, reading={pct:.2f}%, target={target}%)")
                        threading.Thread(target=do_oxygen_move, args=(target_level,), daemon=True).start()
            except Exception as e:
                log.debug(f"O2 sensor read failed: {e}")
                with lock:
                    state["oxygen"]["sensor_status"] = "ERROR"
        else:
            with lock:
                state["oxygen"]["sensor_status"] = "NOT_CONNECTED"
        time.sleep(1)


def _spo2_open():
    """Opens the oximeter's serial port raw at 115200 8N1. Returns (fd, path) or (None, path)."""
    ports = sorted(glob.glob(SPO2_PORT_GLOB))
    path = ports[0] if ports else SPO2_PORT_FALLBACK
    if not os.path.exists(path):
        return None, path
    fd = os.open(path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    a = termios.tcgetattr(fd)
    a[0] = 0                                                   # iflag: raw
    a[1] = 0                                                   # oflag: raw
    a[2] = termios.CS8 | termios.CREAD | termios.CLOCAL       # 8N1
    a[3] = 0                                                   # lflag: raw
    a[4] = a[5] = termios.B115200
    a[6][termios.VMIN] = 0
    a[6][termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, a)
    termios.tcflush(fd, termios.TCIOFLUSH)
    return fd, path

def _spo2_cmd(fd, code):
    os.write(fd, bytes([0x7D, 0x81, code, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80]))

def _spo2_decode(frame):
    """One 9-byte live frame -> dict. frame[1] carries bit 7 of each data byte."""
    hb = frame[1]
    d = [(frame[i + 2] & 0x7F) | (0x80 if hb & (1 << i) else 0) for i in range(7)]
    spo2, pulse = d[4], d[3]
    pi_raw = d[5] | (d[6] << 8)
    valid = (SPO2_VALID_RANGE[0] <= spo2 <= SPO2_VALID_RANGE[1]
             and PULSE_VALID_RANGE[0] <= pulse <= PULSE_VALID_RANGE[1])
    return {
        "valid": valid,
        "spo2": spo2, "pulse": pulse,
        "pi": (round(pi_raw / 100.0, 2) if pi_raw != 0xFFFF else None),
        "signal": d[0] & 0x0F,
        "pleth": d[1],
        "flags": [d[0], d[2]],
    }

def _spo2_publish(status, latest=None, pleth=None, updated=None):
    with lock:
        s = state["spo2"]
        s["status"] = status
        ok = status == "OK" and latest is not None
        s["spo2"] = latest["spo2"] if ok else None
        s["pulse"] = latest["pulse"] if ok else None
        s["pi"] = latest["pi"] if ok else None
        s["signal"] = latest["signal"] if latest is not None else 0
        s["flags"] = latest["flags"] if latest is not None else None
        s["pleth"] = list(pleth) if (pleth is not None and status in ("OK", "NO_FINGER")) else []
        s["updated"] = updated

def spo2_loop():
    """Reads the CMS60C over USB serial: sends the start command, decodes the
    60 frames/s, keeps the link alive, and reconnects if the cable is pulled or
    the stream stops. Publishes to state["spo2"] twice a second."""
    fd = None
    buf = bytearray()
    pleth = deque(maxlen=SPO2_PLETH_POINTS)
    latest = None
    last_frame = last_ka = last_pub = 0.0
    updated = None
    was_connected = False
    while True:
        try:
            if fd is None:
                fd, path = _spo2_open()
                if fd is None:
                    if was_connected:
                        log.warning("[ERR] SpO2: oximeter disconnected")
                        was_connected = False
                    _spo2_publish("NOT_CONNECTED")
                    time.sleep(2)
                    continue
                _spo2_cmd(fd, 0xA1)
                now = time.monotonic()
                last_frame = last_ka = now
                buf.clear(); pleth.clear(); latest = None
                if not was_connected:
                    log.info(f"[OK] SpO2: oximeter on {path}")
                    was_connected = True

            r, _, _ = select.select([fd], [], [], 0.2)
            now = time.monotonic()
            if r:
                chunk = os.read(fd, 4096)
                if not chunk:
                    raise OSError("serial port closed")
                buf += chunk
                while True:
                    i = buf.find(0x01)              # data bytes always have bit 7 set,
                    if i < 0:                       # so 0x01 can only start a frame
                        buf.clear(); break
                    if i:
                        del buf[:i]
                    if len(buf) < 9:
                        break
                    frame = bytes(buf[:9])
                    if all(b & 0x80 for b in frame[1:]):
                        latest = _spo2_decode(frame)
                        pleth.append(latest["pleth"])
                        last_frame = now
                        updated = time.time()
                        del buf[:9]
                    else:
                        del buf[:1]

            if now - last_ka >= SPO2_KEEPALIVE_S:
                _spo2_cmd(fd, 0xAF)
                last_ka = now

            silent = now - last_frame
            if silent > SPO2_REOPEN_S:
                log.warning("[ERR] SpO2: no data, reopening the port")
                os.close(fd); fd = None
                continue
            if silent > SPO2_NO_DATA_S and now - last_ka >= 1.0:
                _spo2_cmd(fd, 0xA1)                 # ask again for live data
                last_ka = now

            if now - last_pub >= 0.5:
                if silent > SPO2_NO_DATA_S or latest is None:
                    status = "NO_DATA"
                else:
                    status = "OK" if latest["valid"] else "NO_FINGER"
                _spo2_publish(status, latest, pleth, updated)
                last_pub = now
        except OSError as e:
            log.warning(f"[ERR] SpO2 serial error: {e}")
            if fd is not None:
                try:
                    os.close(fd)
                except OSError:
                    pass
            fd = None
            _spo2_publish("NOT_CONNECTED")
            time.sleep(2)
        except Exception as e:
            log.error(f"spo2_loop error: {e}")
            time.sleep(1)


# ============================================================
# ALARM ENGINE
# ============================================================
# Alarms are evaluated here on the Pi, not in the Flutter app, and that is
# deliberate. The app is a poller: if the kiosk browser dies, the tab is
# backgrounded, or Wi-Fi drops -- all of which have happened in practice --
# a client-side alarm goes quiet at exactly the moment it matters. This
# loop and the buzzer it drives keep running regardless of whether any
# client is connected at all.
#
# Four behaviours separate this from a plain threshold check:
#
#   onset delay  A condition must hold continuously for ALARM_ONSET_DELAY_S
#                before firing. The load cells and the O2 cell both jitter,
#                and a single noisy sample must not raise an alarm. Alarm
#                fatigue is a documented patient-safety hazard, not merely
#                an annoyance.
#   latching     An alarm that fires and then self-clears stays visible
#                until acknowledged, so a transient event is never missed
#                just because nobody was looking at the screen.
#   silence      Acknowledging silences the buzzer for ALARM_SILENCE_S and
#                then it sounds again if still active. Never a permanent
#                mute -- that is how alarms get defeated in practice.
#   priority     Drives both buzzer cadence and UI colour, following the
#                spirit of IEC 60601-1-8.
#
# Sensor-fault gating: if a sensor is not reporting OK, the threshold
# alarms that depend on it are suppressed and a sensor-fault alarm is
# raised instead. Otherwise a dead sensor reading 0 would fire a spurious
# "temperature low" on top of the real fault.

alarm_lock = threading.Lock()

_PRIORITY_ORDER = {"high": 3, "medium": 2, "low": 1}

def _highest_priority(priorities):
    best = None
    for p in priorities:
        if best is None or _PRIORITY_ORDER[p] > _PRIORITY_ORDER[best]:
            best = p
    return best

def _climate_ok(s):
    return s["climate"].get("sensor_status") == "OK"

def _oxygen_ok(s):
    return s["oxygen"].get("sensor_status") == "OK"

def _check_heater_runaway(s):
    # Heater stuck on: control is engaged and the air temp has climbed well
    # past where hysteresis should already have switched the heater off.
    c = s["climate"]
    if not (_climate_ok(s) and c["control_enabled"]):
        return False, c["temp"]
    return c["temp"] > c["target_temp"] + HEATER_RUNAWAY_MARGIN_C, c["temp"]

def _check_air_temp_high(s):
    v = s["climate"]["temp"]
    return (_climate_ok(s) and v > alarm_limits["air_temp_high"]), v

def _check_air_temp_low(s):
    v = s["climate"]["temp"]
    return (_climate_ok(s) and v < alarm_limits["air_temp_low"]), v

def _check_humidity_high(s):
    v = s["climate"]["humidity"]
    return (_climate_ok(s) and v > alarm_limits["humidity_high"]), v

def _check_humidity_low(s):
    v = s["climate"]["humidity"]
    return (_climate_ok(s) and v < alarm_limits["humidity_low"]), v

def _check_o2_high(s):
    v = s["oxygen"]["measured_percent"]
    return (_oxygen_ok(s) and v > alarm_limits["o2_high"]), v

def _check_o2_low(s):
    v = s["oxygen"]["measured_percent"]
    return (_oxygen_ok(s) and v < alarm_limits["o2_low"]), v

def _check_climate_fault(s):
    return not _climate_ok(s), s["climate"].get("sensor_status")

def _check_oxygen_fault(s):
    return not _oxygen_ok(s), s["oxygen"].get("sensor_status")

def _check_bed_fault(s):
    return not s["bed"].get("connected", False), s["bed"].get("distance")

def _check_weight_fault(s):
    return s["weight"].get("status") != "OK", s["weight"].get("status")

# SpO2 alarms only run while monitoring is switched on, and the threshold ones
# only while the oximeter has a valid reading (so an empty probe never reads as
# "SpO2 low"); a missing reading raises the probe alarm instead.
def _spo2_watch(s):
    return s["spo2"].get("monitoring_enabled", False)

def _spo2_valid(s):
    return s["spo2"].get("status") == "OK"

def _check_spo2_low(s):
    v = s["spo2"].get("spo2")
    return (_spo2_watch(s) and _spo2_valid(s) and v is not None and v < alarm_limits["spo2_low"]), v

def _check_spo2_high(s):
    v = s["spo2"].get("spo2")
    return (_spo2_watch(s) and _spo2_valid(s) and v is not None and v > alarm_limits["spo2_high"]), v

def _check_pulse_low(s):
    v = s["spo2"].get("pulse")
    return (_spo2_watch(s) and _spo2_valid(s) and v is not None and v < alarm_limits["pulse_low"]), v

def _check_pulse_high(s):
    v = s["spo2"].get("pulse")
    return (_spo2_watch(s) and _spo2_valid(s) and v is not None and v > alarm_limits["pulse_high"]), v

def _check_spo2_fault(s):
    st = s["spo2"].get("status")
    return (_spo2_watch(s) and st != "OK"), st

def smoke_loop():
    """Reads the smoke sensor's DO pin twice a second. Ignored during warm-up. A LOW pin means
    smoke -- or a sensor wire that has come off, because the divider then pulls the pin low."""
    t0 = time.monotonic()
    while True:
        try:
            left = SMOKE_WARMUP_S - (time.monotonic() - t0)
            if left > 0:
                status = "WARMING_UP"
            else:
                status = "SMOKE" if GPIO.input(SMOKE_PIN) == GPIO.LOW else "OK"
            with lock:
                state["smoke"]["status"] = status
                state["smoke"]["warmup_left"] = max(0, int(left))
        except Exception as e:
            log.error(f"smoke_loop error: {e}")
        time.sleep(0.5)

def skin_temp_from_resistance(r):
    """YSI-400 resistance (ohm) to degrees C, Steinhart-Hart."""
    ln = math.log(r)
    return 1.0 / (SKIN_SH_A + SKIN_SH_B * ln + SKIN_SH_C * ln ** 3) - 273.15

def skin_loop():
    """Reads the skin probe once a second: the median of SKIN_SAMPLES conversions, turned into
    the probe's resistance by the divider formula, then into a temperature."""
    global skin_chan
    while True:
        status, temp, volts, res = "NOT_CONNECTED", None, None, None
        try:
            if skin_chan is None and ads is not None:
                skin_chan = AnalogIn(ads, SKIN_CHANNEL)
            if skin_chan is not None:
                with ads_lock:
                    v = sorted(skin_chan.voltage for _ in range(SKIN_SAMPLES))[SKIN_SAMPLES // 2]
                    vdd = SKIN_VDD
                    if SKIN_VDD_CHANNEL is not None:
                        measured = AnalogIn(ads, SKIN_VDD_CHANNEL).voltage
                        if 3.0 <= measured <= 3.6:
                            vdd = measured
                volts = round(v, 4)
                if v >= vdd * 0.97:
                    status = "PROBE_OFF"          # pulled up to the supply: nothing in the jack
                else:
                    res = SKIN_R_REF * max(v, 0.0) / (vdd - v)
                    if res < SKIN_R_SHORT:
                        status = "SHORT"
                    else:
                        t = skin_temp_from_resistance(res)
                        if SKIN_RANGE_C[0] <= t <= SKIN_RANGE_C[1]:
                            status, temp = "OK", round(t, 2)
                        else:
                            status = "RANGE"
                    res = round(res, 1)
        except Exception as e:
            log.debug(f"skin probe read failed: {e}")
            status, temp, volts, res = "NOT_CONNECTED", None, None, None
        with lock:
            sk = state["skin"]
            sk["status"], sk["temp"], sk["voltage"], sk["resistance"] = status, temp, volts, res
        time.sleep(1)

# Skin alarms follow the SpO2 pattern: only while monitoring is on, and the threshold ones only
# with a valid reading; a missing probe raises the probe alarm instead.
def _skin_watch(s):
    return s["skin"].get("monitoring_enabled", False)

def _skin_valid(s):
    return s["skin"].get("status") == "OK"

def _check_skin_high(s):
    v = s["skin"].get("temp")
    return (_skin_watch(s) and _skin_valid(s) and v is not None and v > alarm_limits["skin_temp_high"]), v

def _check_skin_low(s):
    v = s["skin"].get("temp")
    return (_skin_watch(s) and _skin_valid(s) and v is not None and v < alarm_limits["skin_temp_low"]), v

def _check_skin_fault(s):
    st = s["skin"].get("status")
    return (_skin_watch(s) and st != "OK"), st

def _check_smoke(s):
    st = s["smoke"].get("status")
    return st == "SMOKE", st

# id, priority, label, check function
ALARM_SPECS = [
    ("heater_runaway",       "high",   "Heater runaway - air temp far above target", _check_heater_runaway),
    ("air_temp_high",        "high",   "Air temperature high",                       _check_air_temp_high),
    ("air_temp_low",         "high",   "Air temperature low",                        _check_air_temp_low),
    ("o2_high",              "high",   "Oxygen concentration high",                  _check_o2_high),
    ("o2_low",               "high",   "Oxygen concentration low",                   _check_o2_low),
    ("smoke",                "high",   "Smoke detected (or smoke sensor wire off)",  _check_smoke),
    ("skin_temp_high",       "high",   "Skin temperature high",                      _check_skin_high),
    ("skin_temp_low",        "high",   "Skin temperature low",                       _check_skin_low),
    ("spo2_low",             "high",   "SpO2 low",                                   _check_spo2_low),
    ("pulse_low",            "high",   "Pulse rate low",                             _check_pulse_low),
    ("pulse_high",           "high",   "Pulse rate high",                            _check_pulse_high),
    ("spo2_high",            "medium", "SpO2 high",                                  _check_spo2_high),
    ("spo2_probe_fault",     "medium", "SpO2 probe off or oximeter not connected",   _check_spo2_fault),
    ("skin_probe_fault",     "medium", "Skin temperature probe off or wire fault",   _check_skin_fault),
    ("humidity_high",        "medium", "Humidity high",                              _check_humidity_high),
    ("humidity_low",         "medium", "Humidity low",                               _check_humidity_low),
    ("climate_sensor_fault", "medium", "Climate sensors not responding",             _check_climate_fault),
    ("oxygen_sensor_fault",  "medium", "Oxygen sensor not responding",               _check_oxygen_fault),
    ("bed_sensor_fault",     "low",    "Bed distance sensor not responding",         _check_bed_fault),
    ("weight_sensor_fault",  "low",    "Weight sensors not responding",              _check_weight_fault),
]

# pending_since / ack_at use time.monotonic() (immune to wall-clock jumps);
# `since` uses time.time() because it is shown to a human.
_alarm_runtime = {
    aid: {
        "pending_since": None,
        "active": False,
        "latched": False,
        "acknowledged": False,
        "ack_at": None,
        "since": None,
        "value": None,
    }
    for aid, _p, _l, _c in ALARM_SPECS
}

state["alarms"] = {"items": [], "highest_priority": None,
                   "sounding": False, "sounding_priority": None}

# SOS: a call for help raised by hand from any screen. Kept apart from the
# threshold alarms because it is not a condition the Pi can evaluate -- it
# stays on until someone cancels it, and acknowledging alarms does not
# silence it.
state["sos"] = {"active": False, "since": None, "raised_from": None}

def evaluate_alarms():
    with lock:
        snapshot = copy.deepcopy(state)

    now = time.monotonic()
    items = []
    sounding_priorities = []

    with alarm_lock:
        for aid, priority, label, check in ALARM_SPECS:
            rt = _alarm_runtime[aid]
            try:
                breached, value = check(snapshot)
            except Exception as e:
                # A broken check must never take down the whole alarm loop.
                log.debug(f"Alarm check '{aid}' failed: {e}")
                continue
            rt["value"] = value

            if breached:
                if rt["pending_since"] is None:
                    rt["pending_since"] = now
                if not rt["active"] and (now - rt["pending_since"]) >= ALARM_ONSET_OVERRIDE_S.get(aid, ALARM_ONSET_DELAY_S):
                    rt["active"] = True
                    rt["latched"] = True
                    rt["acknowledged"] = False
                    rt["ack_at"] = None
                    rt["since"] = time.time()
                    log.warning(f"ALARM [{priority}] {label} (value={value})")
            else:
                rt["pending_since"] = None
                if rt["active"]:
                    rt["active"] = False
                    log.info(f"ALARM CLEARED: {label}")

            # Silence expires and the alarm sounds again if still active.
            if rt["acknowledged"] and rt["ack_at"] is not None \
                    and (now - rt["ack_at"]) >= ALARM_SILENCE_S:
                rt["acknowledged"] = False
                rt["ack_at"] = None
                if rt["active"]:
                    log.info(f"ALARM re-sounding after silence expired: {label}")

            # An acknowledged alarm whose condition has cleared is done --
            # drop the latch so it leaves the display.
            if rt["acknowledged"] and not rt["active"]:
                rt["latched"] = False

            if rt["active"] or rt["latched"]:
                items.append({
                    "id": aid,
                    "priority": priority,
                    "label": label,
                    "value": rt["value"],
                    "active": rt["active"],
                    "acknowledged": rt["acknowledged"],
                    "since": rt["since"],
                })
                if rt["active"] and not rt["acknowledged"]:
                    sounding_priorities.append(priority)

    items.sort(key=lambda i: (-_PRIORITY_ORDER[i["priority"]], i["id"]))
    sounding_priority = _highest_priority(sounding_priorities)

    with lock:
        state["alarms"] = {
            "items": items,
            "highest_priority": _highest_priority([i["priority"] for i in items]),
            "sounding": sounding_priority is not None,
            "sounding_priority": sounding_priority,
        }

def alarm_loop():
    while True:
        try:
            evaluate_alarms()
        except Exception as e:
            log.error(f"alarm_loop error: {e}")
        time.sleep(1)

def buzzer_loop():
    """Drives the buzzer independently of the evaluation loop, so a slow
    evaluation cycle can never stretch or break the audible cadence."""
    while True:
        try:
            with lock:
                a = state.get("alarms", {})
                sounding = a.get("sounding", False)
                priority = a.get("sounding_priority")
                sos = state.get("sos", {}).get("active", False)
            if sos:
                # A steady tone, distinct from every alarm cadence, until
                # the SOS is cancelled.
                GPIO.output(BUZZER_PIN, GPIO.HIGH)
                time.sleep(0.2)
                continue
            pattern = BUZZER_PATTERNS.get(priority) if sounding else None
            if pattern is None:
                GPIO.output(BUZZER_PIN, GPIO.LOW)
                time.sleep(0.2)
                continue
            on_s, off_s = pattern
            GPIO.output(BUZZER_PIN, GPIO.HIGH)
            time.sleep(on_s)
            GPIO.output(BUZZER_PIN, GPIO.LOW)
            time.sleep(off_s)
        except Exception as e:
            log.error(f"buzzer_loop error: {e}")
            time.sleep(1)

# ============================================================
# API ENDPOINTS
# ============================================================

@app.route("/status")
def get_status():
    with lock:
        return jsonify(state)

@app.route("/weight/tare", methods=["POST"])
def tare_weight():
    for s in scales:
        if s:
            s.tare()
    return jsonify({"message": "Tared"})

@app.route("/weight/restart", methods=["POST"])
def restart_weight_sensors():
    """Re-initializes all 4 HX711 load cell scales from scratch. For when a
    cell is stuck/unresponsive after a wiring hiccup or power blip, without
    needing to restart the whole service (which would also drop the camera
    stream and bed/climate control loops)."""
    global scales
    log.info("Restarting weight scales...")
    new_scales = []
    ok_count = 0
    for i, dt in enumerate(DT_PINS):
        try:
            s = HX711(dt, SCK_PIN)
            s.reset()
            new_scales.append(s)
            ok_count += 1
            log.info(f"[OK] Scale {i+1} restarted")
        except Exception as e:
            new_scales.append(None)
            log.warning(f"[ERR] Scale {i+1} restart failed: {e}")
    with lock:
        scales = new_scales
        state["weight"]["status"] = "OK" if ok_count > 0 else "ERROR"
    return jsonify({"status": "restarted", "scales_ok": ok_count, "scales_total": len(DT_PINS)})

@app.route("/climate/settings", methods=["POST"])
def set_climate():
    data = request.json or {}
    with lock:
        if "target_temp" in data:
            state["climate"]["target_temp"] = float(data["target_temp"])
        if "target_hum" in data:
            state["climate"]["target_hum"] = float(data["target_hum"])
        if "active_heater" in data:
            state["climate"]["active_heater"] = int(data["active_heater"])
        if "enabled" in data:
            state["climate"]["control_enabled"] = bool(data["enabled"])
    save_config()  # outside the lock — save_config takes it itself
    return jsonify({"status": "updated"})

@app.route("/climate/restart", methods=["POST"])
def restart_climate_sensors():
    """Re-initializes the TMP117 (x2), BME68x, and MS8607 climate sensors
    from scratch. For when a reading is stuck/missing after a wiring
    hiccup, without needing to restart the whole service (which would
    also drop the camera stream and bed/oxygen loops)."""
    global tmp1, tmp2, bme, ms8607_hum
    log.info("Restarting climate sensors...")
    ok_count = 0

    try:
        tmp1 = adafruit_tmp117.TMP117(i2c, address=0x48)
        ok_count += 1
        log.info("[OK] TMP117 #1 restarted")
    except Exception as e:
        tmp1 = None
        log.warning(f"[ERR] TMP117 #1 restart failed: {e}")

    try:
        tmp2 = adafruit_tmp117.TMP117(i2c, address=0x49)
        ok_count += 1
        log.info("[OK] TMP117 #2 restarted")
    except Exception as e:
        tmp2 = None
        log.warning(f"[ERR] TMP117 #2 restart failed: {e}")

    try:
        try:
            bme = adafruit_bme680.Adafruit_BME680_I2C(i2c, address=0x77)
        except Exception:
            bme = adafruit_bme680.Adafruit_BME680_I2C(i2c, address=0x76)
        ok_count += 1
        log.info("[OK] BME68x restarted")
    except Exception as e:
        bme = None
        log.warning(f"[ERR] BME68x restart failed: {e}")

    try:
        ms8607_hum = I2CDevice(i2c, 0x40)
        ok_count += 1
        log.info("[OK] MS8607 restarted")
    except Exception as e:
        ms8607_hum = None
        log.warning(f"[ERR] MS8607 restart failed: {e}")

    return jsonify({"status": "restarted", "sensors_ok": ok_count, "sensors_total": 4})

def do_move(direction, target, pin_on, pin_off, is_up):
    """Drive the bed motor toward `target` distance, with a hard timeout
    and guaranteed motor shutoff even on error (both were missing before)."""
    start_time = time.monotonic()
    with lock:
        state["bed"]["status"] = f"moving_{direction}"
        state["bed"]["moving"] = True
    try:
        while True:
            if time.monotonic() - start_time > BED_MOVE_TIMEOUT_S:
                log.warning(f"Bed move '{direction}' timed out after {BED_MOVE_TIMEOUT_S}s — stopping motor")
                break
            d = read_tof()
            if d < 0 or (is_up and d >= target) or (not is_up and d <= target):
                break
            GPIO.output(pin_on, GPIO.HIGH)
            GPIO.output(pin_off, GPIO.LOW)
            time.sleep(0.1)
    finally:
        # BUG FIX: motor is now always stopped, even if an exception is
        # raised mid-loop (e.g. a sensor read error propagating up).
        GPIO.output(pin_on, GPIO.LOW)
        GPIO.output(pin_off, GPIO.LOW)
        with lock:
            state["bed"]["status"] = "idle"
            state["bed"]["moving"] = False

@app.route("/bed/move", methods=["POST"])
def move_bed():
    direction = (request.json or {}).get("direction")
    if direction not in ("up", "down"):
        return jsonify({"status": "error", "message": "direction must be 'up' or 'down'"}), 400

    with lock:
        already_moving = state["bed"]["moving"]
        curr_dist = state["bed"]["distance"]
        connected = state["bed"]["connected"]

    if not connected:
        return jsonify({"status": "error", "message": "bed distance sensor not connected"}), 503

    # BUG FIX: guard against a second move command being issued while the
    # bed is already in motion, which could previously drive both motor
    # relays from overlapping threads.
    if already_moving:
        return jsonify({"status": "error", "message": "bed is already moving"}), 409

    if direction == "up" and DIST_UP_MIN <= curr_dist <= DIST_UP_MAX:
        threading.Thread(target=do_move, args=("up", DIST_UP_TARGET, MOTOR_UP_PIN, MOTOR_DOWN_PIN, True), daemon=True).start()
        return jsonify({"status": "command_sent"})
    elif direction == "down" and DIST_DOWN_MIN <= curr_dist <= DIST_DOWN_MAX:
        threading.Thread(target=do_move, args=("down", DIST_DOWN_TARGET, MOTOR_DOWN_PIN, MOTOR_UP_PIN, False), daemon=True).start()
        return jsonify({"status": "command_sent"})
    else:
        # BUG FIX: previously this silently returned "command_sent" even
        # when the current distance was out of bounds and nothing happened.
        return jsonify({"status": "error", "message": f"current distance {curr_dist} out of bounds for '{direction}'"}), 400

@app.route("/bed/restart", methods=["POST"])
def restart_bed_sensor():
    """Re-initializes the VL53L4CD time-of-flight distance sensor. For when
    the bed distance reading is stuck/missing after a wiring hiccup, without
    needing to restart the whole service."""
    global tof
    log.info("Restarting bed distance sensor...")
    # Detach the old object FIRST so bed_monitor() (which polls read_tof()
    # every 0.2 s) stops talking to the chip, then give it a moment to
    # notice. Re-initialising while another thread's I2C transactions were
    # interleaved with the chip's soft-reset sequence produced
    # "[Errno 5] Input/output error" and could leave the sensor wedged until
    # power-cycled.
    old = tof
    tof = None
    time.sleep(0.5)
    if old is not None:
        try:
            old.stop_ranging()
        except Exception:
            pass
        time.sleep(0.2)
    last_err = None
    for attempt in range(3):
        try:
            new = adafruit_vl53l4cd.VL53L4CD(i2c)
            new.start_ranging()
            tof = new
            with lock:
                state["bed"]["connected"] = True
            log.info(f"[OK] VL53L4CD restarted (attempt {attempt + 1})")
            return jsonify({"status": "restarted"})
        except Exception as e:
            last_err = e
            log.warning(f"[ERR] VL53L4CD restart attempt {attempt + 1} failed: {e}")
            time.sleep(0.5)
    with lock:
        state["bed"]["connected"] = False
    log.warning("[ERR] VL53L4CD restart failed; sensor may need a power cycle")
    return jsonify({"status": "error", "message": str(last_err)}), 500

def do_oxygen_move(level):
    """Move the oxygen valve servo to the angle for `level`, off the request thread."""
    angle = oxygen_level_to_angle(level)
    try:
        with oxygen_lock:
            set_servo_angle(angle)
        with lock:
            state["oxygen"]["level"] = level
            state["oxygen"]["angle"] = angle
    except Exception as e:
        log.error(f"Oxygen valve move failed: {e}")
    finally:
        with lock:
            state["oxygen"]["moving"] = False

@app.route("/oxygen/level", methods=["POST"])
def set_oxygen_level():
    data = request.json or {}
    if "level" not in data:
        return jsonify({"status": "error", "message": "level is required"}), 400
    try:
        level = int(data["level"])
    except (TypeError, ValueError):
        return jsonify({"status": "error", "message": "level must be an integer"}), 400
    if not (OXYGEN_LEVEL_MIN <= level <= OXYGEN_LEVEL_MAX):
        return jsonify({"status": "error", "message": f"level must be between {OXYGEN_LEVEL_MIN} and {OXYGEN_LEVEL_MAX}"}), 400

    with lock:
        if state["oxygen"]["moving"]:
            return jsonify({"status": "error", "message": "oxygen valve is already moving"}), 409
        state["oxygen"]["moving"] = True

    threading.Thread(target=do_oxygen_move, args=(level,), daemon=True).start()
    return jsonify({"status": "command_sent", "level": level})

@app.route("/oxygen/settings", methods=["POST"])
def set_oxygen_settings():
    """Configures automatic inflow control -- target O2 percentage and
    whether the hysteresis loop in oxygen_sensor_loop() is allowed to
    drive the valve. Independent of manual /oxygen/level commands, which
    still work either way; auto-control will simply override them on its
    next hysteresis-triggered transition, the same relationship climate
    control has to nothing manually overriding the heater."""
    data = request.json or {}
    with lock:
        if "target_percent" in data:
            state["oxygen"]["target_percent"] = float(data["target_percent"])
        if "enabled" in data:
            state["oxygen"]["control_enabled"] = bool(data["enabled"])
    save_config()  # outside the lock — save_config takes it itself
    return jsonify({"status": "updated"})

@app.route("/oxygen/reading")
def get_oxygen_reading():
    """Standalone endpoint for just the live O2 sensor reading, in case the
    app wants to poll this more/less often than the full /status payload."""
    with lock:
        return jsonify({
            "voltage": state["oxygen"]["voltage"],
            "measured_percent": state["oxygen"]["measured_percent"],
            "sensor_status": state["oxygen"]["sensor_status"]
        })

@app.route("/oxygen/restart", methods=["POST"])
def restart_oxygen_sensor():
    """Re-initializes the ADS1115 O2 concentration sensor (the analog
    reading channel -- NOT the valve servo, which has its own separate
    move mechanism via /oxygen/level). For when the reading is stuck at
    an old value or the sensor_status shows NOT_CONNECTED/ERROR after a
    wiring hiccup, without needing to restart the whole service."""
    global ads, o2_chan, skin_chan
    log.info("Restarting oxygen sensor...")
    try:
        ads = ADS1115(i2c, address=OXYGEN_SENSOR_ADDRESS)
        o2_chan = AnalogIn(ads, OXYGEN_SENSOR_CHANNEL)
        skin_chan = None          # skin_loop() re-opens it on the new ADS1115 object
        with lock:
            state["oxygen"]["sensor_status"] = "OK"
        log.info("[OK] ADS1115 O2 Sensor restarted")
        return jsonify({"status": "restarted"})
    except Exception as e:
        ads, o2_chan = None, None
        with lock:
            state["oxygen"]["sensor_status"] = "NOT_CONNECTED"
        log.warning(f"[ERR] ADS1115 O2 Sensor restart failed: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route("/spo2/settings", methods=["POST"])
def spo2_settings():
    """{"monitoring_enabled": true/false} -- switches SpO2 alarms on or off.
    Live readings are shown either way."""
    data = request.json or {}
    val = data.get("monitoring_enabled")
    if not isinstance(val, bool):
        return jsonify({"status": "error", "message": "monitoring_enabled must be true or false"}), 400
    with lock:
        state["spo2"]["monitoring_enabled"] = val
    save_config()
    log.info(f"SpO2 monitoring {'ON' if val else 'OFF'}")
    return jsonify({"status": "updated", "monitoring_enabled": val})

@app.route("/skin/settings", methods=["POST"])
def skin_settings():
    """{"monitoring_enabled": true/false} -- switches skin temperature alarms on or off.
    The live reading is shown either way."""
    data = request.json or {}
    val = data.get("monitoring_enabled")
    if not isinstance(val, bool):
        return jsonify({"status": "error", "message": "monitoring_enabled must be true or false"}), 400
    with lock:
        state["skin"]["monitoring_enabled"] = val
    save_config()
    log.info(f"Skin temperature monitoring {'ON' if val else 'OFF'}")
    return jsonify({"status": "updated", "monitoring_enabled": val})

@app.route("/alarms")
def get_alarms():
    """Alarm detail. Also included in /status, so the app gets it on its
    existing 1s poll without a second request -- this endpoint exists for
    debugging and for any client that wants alarms alone."""
    with lock:
        return jsonify(state["alarms"])

@app.route("/alarms/acknowledge", methods=["POST"])
def acknowledge_alarms():
    """Silences the buzzer for ALARM_SILENCE_S. Pass {"id": "..."} for one
    alarm, or {} / {"all": true} for every currently raised alarm.

    Acknowledging does NOT clear an alarm whose condition is still true --
    it only silences it, and it will sound again when the silence expires.
    An alarm whose condition has already cleared is dismissed outright.
    """
    data = request.json or {}
    target = data.get("id")
    now = time.monotonic()
    acknowledged = []
    with alarm_lock:
        for aid, rt in _alarm_runtime.items():
            if target is not None and aid != target:
                continue
            if rt["active"] or rt["latched"]:
                rt["acknowledged"] = True
                rt["ack_at"] = now
                acknowledged.append(aid)
    if target is not None and not acknowledged:
        return jsonify({"status": "error", "message": f"no raised alarm with id '{target}'"}), 404
    log.info(f"Alarms acknowledged: {acknowledged or 'none raised'}")
    return jsonify({"status": "acknowledged", "acknowledged": acknowledged})

def _lid_run(pin, seconds, final_position):
    other = LID_EXTEND_PIN if pin == LID_RETRACT_PIN else LID_RETRACT_PIN
    try:
        GPIO.output(other, GPIO.LOW)
        GPIO.output(pin, GPIO.HIGH)
        time.sleep(seconds)
    finally:
        GPIO.output(LID_RETRACT_PIN, GPIO.LOW)
        GPIO.output(LID_EXTEND_PIN, GPIO.LOW)
        with lock:
            state["lid"]["moving"] = None
            state["lid"]["position"] = final_position
        save_config()
        log.info(f"Lid stopped, now {final_position}")

@app.route("/lid/move", methods=["POST"])
def lid_move():
    """{"action": "open"} retracts the actuator for LID_OPEN_S; {"action": "close"}
    extends it for LID_CLOSE_S. Open is refused while the lid is open (close first),
    and any command is refused while the lid is moving."""
    action = (request.json or {}).get("action")
    if action not in ("open", "close"):
        return jsonify({"status": "error", "message": "action must be 'open' or 'close'"}), 400
    with lock:
        if state["lid"]["moving"]:
            return jsonify({"status": "error", "message": "lid is already moving"}), 409
        if action == "open" and state["lid"]["position"] == "open":
            return jsonify({"status": "error", "message": "lid is already open - close it first"}), 409
        state["lid"]["moving"] = "opening" if action == "open" else "closing"
        if action == "open":
            state["lid"]["position"] = "open"
    save_config()
    if action == "open":
        threading.Thread(target=_lid_run, args=(LID_RETRACT_PIN, LID_OPEN_S, "open"), daemon=True).start()
        secs = LID_OPEN_S
    else:
        threading.Thread(target=_lid_run, args=(LID_EXTEND_PIN, LID_CLOSE_S, "closed"), daemon=True).start()
        secs = LID_CLOSE_S
    log.info(f"Lid {action} for {secs}s")
    return jsonify({"status": "moving", "action": action, "seconds": secs})

@app.route("/photo", methods=["POST"])
def photo_light():
    """{"on": true/false} -- switches the phototherapy light's relay."""
    val = (request.json or {}).get("on")
    if not isinstance(val, bool):
        return jsonify({"status": "error", "message": "on must be true or false"}), 400
    relay_write(PHOTO_PIN, val)
    with lock:
        state["photo"]["on"] = val
    log.info(f"Phototherapy light {'ON' if val else 'OFF'}")
    return jsonify({"status": "updated", "on": val})

@app.route("/sos", methods=["POST"])
def sos_endpoint():
    """Raises or cancels SOS: {"active": true|false, "from": "kiosk"|...}.

    While raised, the buzzer sounds continuously and every client shows the
    SOS banner (it rides along in /status). Raising it again while already
    raised keeps the original `since` time.
    """
    data = request.json or {}
    val = data.get("active")
    if not isinstance(val, bool):
        return jsonify({"status": "error", "message": "active must be true or false"}), 400
    source = str(data.get("from", "unknown"))[:20]
    with lock:
        was = state["sos"]["active"]
        if val and not was:
            state["sos"] = {"active": True, "since": time.time(), "raised_from": source}
        elif not val:
            state["sos"] = {"active": False, "since": None, "raised_from": None}
        current = dict(state["sos"])
    if val and not was:
        log.warning(f"SOS RAISED from {source}")
    elif was and not val:
        log.info(f"SOS cancelled from {source}")
    return jsonify({"status": "updated", "sos": current})

@app.route("/alarms/limits", methods=["GET", "POST"])
def alarm_limits_endpoint():
    """GET returns current thresholds; POST updates any subset of them.

    Unknown keys are rejected rather than silently ignored, so a typo in a
    limit name fails loudly instead of leaving the old threshold quietly
    in force on a safety control.
    """
    if request.method == "GET":
        with alarm_lock:
            return jsonify(dict(alarm_limits))

    data = request.json or {}
    unknown = [k for k in data if k not in alarm_limits]
    if unknown:
        return jsonify({"status": "error", "message": f"unknown limit(s): {unknown}"}), 400
    bad = [k for k, v in data.items() if not isinstance(v, (int, float)) or isinstance(v, bool)]
    if bad:
        return jsonify({"status": "error", "message": f"limit(s) must be numeric: {bad}"}), 400

    with alarm_lock:
        for key, val in data.items():
            alarm_limits[key] = float(val)
        current = dict(alarm_limits)
    save_config()
    log.info(f"Alarm limits updated: {data}")
    return jsonify({"status": "updated", "limits": current})

@app.route("/system/exit_kiosk", methods=["POST"])
def exit_kiosk():
    """Closes the on-screen kiosk Chromium instance, exposing the Pi's own
    desktop underneath. Lets an operator reach system settings (e.g.
    Wi-Fi) directly from the touchscreen, via a hidden long-press gesture
    on the app's header icon (lib/widgets/custom_header.dart) -- without
    needing a keyboard or a remote SSH session. Chromium runs as the same
    user as this Flask process, so no elevated privileges are needed to
    close it. Does not relaunch it -- see the "Return to Syncubator
    Kiosk" icon on the Pi's own desktop for that."""
    try:
        subprocess.run(
            ["pkill", "-f", "chromium --force-renderer"],
            timeout=5, check=False
        )
        return jsonify({"status": "ok", "message": "Kiosk exited"})
    except Exception as e:
        log.error(f"exit_kiosk failed: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500

# Background sensor loops must start unconditionally, not just under
# `python3 app.py`. Gunicorn imports this file as a module (app:app)
# rather than executing it as a script, so __name__ is "app", not
# "__main__" — the old code only started these threads in the latter case.
t1 = threading.Thread(target=weight_loop, daemon=True)
t2 = threading.Thread(target=climate_loop, daemon=True)
t3 = threading.Thread(target=bed_monitor, daemon=True)
t4 = threading.Thread(target=oxygen_sensor_loop, daemon=True)
t5 = threading.Thread(target=alarm_loop, daemon=True)
t6 = threading.Thread(target=buzzer_loop, daemon=True)
t7 = threading.Thread(target=spo2_loop, daemon=True)
t8 = threading.Thread(target=init_scales, daemon=True)
t9 = threading.Thread(target=smoke_loop, daemon=True)
t10 = threading.Thread(target=skin_loop, daemon=True)
t1.start(); t2.start(); t3.start(); t4.start(); t5.start(); t6.start(); t7.start(); t8.start(); t9.start(); t10.start()
log.info("Background loops started (weight, climate, bed, oxygen sensor, alarms, buzzer, SpO2, smoke, skin probe)")

if __name__ == "__main__":
    log.info("SYNCUBATOR SERVER STARTING ON PORT 5000 (dev server)")
    try:
        app.run(host="0.0.0.0", port=5000, threaded=True)
    finally:
        oxygen_servo.stop()
        relay_write(PHOTO_PIN, False)
        GPIO.cleanup()
