# Testing

Two test suites, both runnable on any computer with no incubator attached.

## Backend: `raspberry_pi/tests/` (pytest, 32 tests)

```bash
cd raspberry_pi
python -m venv .venv && source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r requirements-test.txt
pytest tests
```

The tests import the **real** `app.py`. `tests/conftest.py` replaces the hardware libraries (`RPi.GPIO`, the Adafruit
I2C drivers, the ADS1115, the HX711) with small fakes. A test sets what the fake sensors measure (for example
`env.humidity = 95`), and the real sensor threads, alarm engine and API react exactly as they would on the incubator.
The fake GPIO records every pin level, so tests can check relay outputs.

| File | What it checks |
|---|---|
| `test_skin.py` | The YSI-400 curve against its table (0, 25, 37, 40 °C); the probe reading as `OK` at about 37 °C, `PROBE_OFF` when unplugged and `SHORT` when shorted; the monitoring switch |
| `test_alarms.py` | Each alarm rule (air temperature, dead-sensor suppression, heater runaway, skin and SpO2 monitoring, smoke); the whole lifecycle through the running engine (raise after the onset delay, latch, acknowledge, silence, clear); a short breach that must not fire; limit editing and validation; SOS |
| `test_api.py` | `/status` shape; climate settings saved to disk; dead-band heater control and the active-low relay; oxygen and bed validation; the lid one-step rule and that the lid motor is stopped after every move; the phototherapy relay and that its state is not saved |
| `test_sample_data.py` | The JSON files in `sample_data/` match the shape of the live API |

Some tests wait a few seconds for the sensor threads (which run once a second or so), so the suite takes about
20 seconds.

### Sample data

`raspberry_pi/sample_data/` holds real responses from the backend. If the API gains a field, `test_sample_data.py`
fails; regenerate the files with `python tests/make_sample_data.py`.

## App: `test/` (flutter test, 6 tests)

```bash
flutter pub get
flutter test
```

Widget tests run in the app's demo mode (simulated data, no network): the lid card follows the Open-then-Close lock
rule, the skin card shows the reading and alarm state, the phototherapy button switches on and off, the SOS button needs
a 2 s hold to raise and to cancel, and the app starts without errors.

`flutter analyze` reports no errors or warnings.

## Hardware checks

A few things can only be checked on a real incubator. Useful commands on the Pi:

```bash
i2cdetect -y 1                                  # expect 0x29, 0x40, 0x48, 0x49, 0x4a, 0x77
curl -sk https://127.0.0.1/status | python3 -m json.tool
journalctl -u syncubator.service -f             # live log
```

* **Load cells:** zero on the empty platform, then scale against a known mass (`CAL_FACTORS`, `ZERO_OFFSETS`).
* **Oxygen cell:** two-point calibration, 0 V is 0 % and 1.4 V is 20.9 % (`O2_V_ZERO`, `O2_V_AIR`); room air should read
  about 21 %.
* **Relays:** with the relay board powered, link one IN pin to 3.3 V. The relay must stay off. Link it to GND and it must
  click on.
* **Alarm timing:** hold a condition for 5 s (must stay silent) and for longer (must fire at the onset delay);
  acknowledge must silence the buzzer and keep the alarm listed.
