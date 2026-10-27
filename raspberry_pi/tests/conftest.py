"""Test harness: runs the real app.py on any computer by faking the hardware libraries.

app.py talks to GPIO, I2C sensors, an ADC and load-cell amplifiers. Here those libraries are
replaced by small fakes whose readings the tests control through the `env` object, so a test can
say "the air is 40 degrees" and watch the sensor thread, the alarm engine and the API react.
"""
import json
import pathlib
import sys
import time
import types

import pytest

APP_DIR = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(APP_DIR))


class Env:
    """What the fake sensors currently measure. Tests change these values."""

    def __init__(self):
        self.air_temp = 34.0          # TMP117 x2 and BME680, degrees C
        self.humidity = 60.0          # BME680, % RH
        self.pressure = 1000.0        # hPa
        self.bed_cm = 18.0            # VL53L4CD distance
        self.volts = {0: 1.4, 3: 3.3}  # ADS1115: A0 oxygen cell (1.4 V is room air), A3 skin probe (3.3 V = unplugged)


env = Env()


class FakeGPIO:
    BCM, OUT, IN, HIGH, LOW = "BCM", "OUT", "IN", 1, 0

    def __init__(self):
        self.levels, self.modes = {}, {}

    def setwarnings(self, flag): pass
    def setmode(self, mode): pass
    def cleanup(self, *args): pass

    def setup(self, pin, mode, initial=None, **kwargs):
        self.modes[pin] = mode
        if initial is not None:
            self.levels[pin] = initial

    def output(self, pin, level):
        self.levels[pin] = level

    def input(self, pin):
        return self.levels.get(pin, self.HIGH)

    class PWM:
        def __init__(self, pin, freq): pass
        def start(self, duty): pass
        def ChangeDutyCycle(self, duty): pass
        def stop(self): pass


gpio = FakeGPIO()


def _install_fakes():
    def module(name, **attrs):
        m = types.ModuleType(name)
        m.__dict__.update(attrs)
        sys.modules[name] = m
        return m

    rpi = module("RPi")
    rpi.GPIO = gpio
    sys.modules["RPi.GPIO"] = gpio

    module("board", SCL="SCL", SDA="SDA")
    module("busio", I2C=lambda *a, **k: object())

    class HX711:
        def __init__(self, dout, sck): pass
        def reset(self): pass
        def tare(self): pass
        def get_raw_data(self, n): return [0] * n

    module("hx711", HX711=HX711)

    class TMP117:
        def __init__(self, i2c, address=0x48): pass
        @property
        def temperature(self): return env.air_temp

    module("adafruit_tmp117", TMP117=TMP117)

    class BME680:
        def __init__(self, i2c, address=0x77): pass
        temperature = property(lambda self: env.air_temp)
        humidity = property(lambda self: env.humidity)
        pressure = property(lambda self: env.pressure)

    module("adafruit_bme680", Adafruit_BME680_I2C=BME680)

    class VL53L4CD:
        def __init__(self, i2c): pass
        def start_ranging(self): pass
        def clear_interrupt(self): pass
        data_ready = property(lambda self: True)
        distance = property(lambda self: env.bed_cm)

    module("adafruit_vl53l4cd", VL53L4CD=VL53L4CD)

    class I2CDevice:                     # stands in for the MS8607 humidity channel
        def __init__(self, i2c, address): pass
        def __enter__(self): return self
        def __exit__(self, *a): return False
        def write(self, data): pass
        def readinto(self, buf): pass    # leaves zeros: the loop ignores a zero reading

    module("adafruit_bus_device")
    module("adafruit_bus_device.i2c_device", I2CDevice=I2CDevice)

    class ADS1115:
        def __init__(self, i2c, address=0x48): pass

    class AnalogIn:
        def __init__(self, ads, channel): self.channel = channel
        @property
        def voltage(self): return env.volts.get(self.channel, 0.0)

    module("adafruit_ads1x15")
    module("adafruit_ads1x15.ads1115", ADS1115=ADS1115)
    module("adafruit_ads1x15.analog_in", AnalogIn=AnalogIn)

    try:
        import termios  # noqa: F401  (Linux only; the oximeter serial code uses it)
    except ImportError:
        module("termios")


_install_fakes()
import app as backend  # noqa: E402  (must come after the fakes are installed)


@pytest.fixture(scope="session")
def app_module(tmp_path_factory):
    """The real app module, with its settings file redirected to a temporary folder."""
    backend.CONFIG_PATH = str(tmp_path_factory.mktemp("config") / "config.json")
    return backend


@pytest.fixture()
def client(app_module):
    return app_module.app.test_client()


@pytest.fixture()
def fast_alarms(app_module, monkeypatch):
    """Alarms fire after 0.5 s instead of 10 s so tests stay quick."""
    monkeypatch.setattr(app_module, "ALARM_ONSET_DELAY_S", 0.5)
    return app_module


@pytest.fixture()
def config_file(app_module):
    return pathlib.Path(app_module.CONFIG_PATH)


def wait_for(predicate, timeout=12.0, interval=0.1):
    """Polls until predicate() is true (the sensor threads run once a second or so)."""
    end = time.time() + timeout
    while time.time() < end:
        if predicate():
            return True
        time.sleep(interval)
    return False


def status(client):
    return json.loads(client.get("/status").data)
