# Raspberry Pi backend

The incubator's controller: one Python program (`app.py`) that reads the sensors, runs the control loops and the alarm
engine, and serves the HTTP API that the Flutter app uses.

| Path | Contents |
|---|---|
| `app.py` | Hardware drivers, sensor threads, control loops, alarm engine, Flask API |
| `requirements.txt` | Packages for the Raspberry Pi |
| `requirements-test.txt` | Packages for running the tests on any computer |
| `deploy/` | Nginx config, systemd unit, kiosk autostart file, Cloudflare offline-page Worker |
| `sample_data/` | Real example responses from the backend (`/status`, with and without an alarm; the saved settings) |
| `tests/` | The pytest suite (32 tests, runs against fake sensors) |

* Set-up on a Raspberry Pi: [../docs/deployment.md](../docs/deployment.md)
* Wiring and pin map: [../docs/hardware.md](../docs/hardware.md)
* API reference: [../docs/api.md](../docs/api.md)
* Alarm behaviour: [../docs/alarms.md](../docs/alarms.md)
* Tests: [../docs/testing.md](../docs/testing.md)

```bash
pip install -r requirements-test.txt
pytest tests
```

## Adding a sensor or actuator

Follow the existing pattern in `app.py`: initialise the device inside `init_hardware()` in a `try/except` (so one missing
device never stops the program), write a read function, start a background loop thread at module level, and give it its
own section in `state`. Background loops are started at module level, not under `if __name__ == "__main__":`, because
Gunicorn imports the module instead of running it as a script.
