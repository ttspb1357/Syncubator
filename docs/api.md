# HTTP API

Served by the Flask app behind Nginx at `https://<incubator>/`. Request and response bodies are JSON. Errors return
`{"status": "error", "message": "..."}` with the status code shown below. Real example responses are in
[`raspberry_pi/sample_data/`](../raspberry_pi/sample_data/).

## Read

| Method | Path | Returns |
|---|---|---|
| GET | `/status` | The whole state: `weight`, `climate`, `bed`, `oxygen`, `spo2`, `skin`, `smoke`, `lid`, `photo`, `alarms`, `sos` |
| GET | `/alarms` | The `alarms` section on its own |
| GET | `/oxygen/reading` | `voltage`, `measured_percent`, `sensor_status` of the O2 cell |
| GET | `/alarms/limits` | The operator-editable alarm limits |
| GET | `/video_feed` | Live camera, an MJPEG multipart stream (must be decoded frame by frame) |

The app polls `/status` once a second. Every section carries the data its card needs; for example

```json
"skin":  {"monitoring_enabled": true, "status": "OK", "temp": 37.0, "voltage": 0.3619, "resistance": 1355.0},
"lid":   {"position": "closed", "moving": null},
"photo": {"on": false},
"alarms": {"items": [{"id": "humidity_high", "priority": "medium", "label": "Humidity high",
                      "active": true, "acknowledged": false, "value": 92.0, "since": 1793123034.6}],
           "highest_priority": "medium", "sounding": true, "sounding_priority": "medium"}
```

## Control

| Method | Path | Body | Notes |
|---|---|---|---|
| POST | `/climate/settings` | any of `target_temp`, `target_hum`, `active_heater` (1 or 2), `enabled` | Saved to disk. `enabled: false` forces every climate relay off |
| POST | `/oxygen/level` | `{"level": 0-7}` | Moves the valve. `400` if out of range, `409` if already moving |
| POST | `/oxygen/settings` | `{"target_percent": 25.0, "enabled": true}` | Automatic inflow control (dead band of 1.5 points) |
| POST | `/bed/move` | `{"direction": "up" \| "down"}` | `400` if the height is out of range for that direction, `409` if moving, `503` if the sensor is missing |
| POST | `/lid/move` | `{"action": "open" \| "close"}` | Timed move. `409` if moving, or if `open` is sent while the lid is already open |
| POST | `/photo` | `{"on": true \| false}` | Phototherapy light relay. Always off after a restart |
| POST | `/weight/tare` | - | Zeroes the load cells (platform empty) |
| POST | `/spo2/settings` | `{"monitoring_enabled": true \| false}` | Switches SpO2, pulse and probe alarms on or off |
| POST | `/skin/settings` | `{"monitoring_enabled": true \| false}` | Switches skin-temperature and probe alarms on or off |
| POST | `/alarms/acknowledge` | `{}` or `{"id": "humidity_high"}` | Silences the buzzer for 120 s. `404` for an unknown id |
| POST | `/alarms/limits` | any alarm limit key and a number | Unknown keys and non-numbers return `400`. Saved to disk |
| POST | `/sos` | `{"active": true \| false, "from": "kiosk"}` | Sounds the buzzer continuously and shows a banner on every client |

Alarm limit keys: `air_temp_low`, `air_temp_high`, `humidity_low`, `humidity_high`, `o2_low`, `o2_high`, `spo2_low`,
`spo2_high`, `pulse_low`, `pulse_high`, `skin_temp_low`, `skin_temp_high`.

## Maintenance

| Method | Path | Purpose |
|---|---|---|
| POST | `/weight/restart`, `/climate/restart`, `/bed/restart`, `/oxygen/restart` | Re-initialise one sensor driver without restarting the service |
| POST | `/system/exit_kiosk` | Close the kiosk browser so the Pi desktop is visible |

## Lid rule

The lid has no position sensor. `open` retracts the actuator for a fixed time and `close` extends it for the same time.
`open` is refused until `close` has been used, so the lid can only ever be opened one step. The position is saved and
survives a restart.
