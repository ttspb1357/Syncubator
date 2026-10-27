# Alarm system

The alarm engine runs **on the incubator**, in `app.py`, not in the app. An alarm in a client goes quiet exactly when it
matters, when the browser crashes or the Wi-Fi drops; this one keeps working with no network and no app. It follows the
low, medium and high priorities of IEC 60601-1-8.

## Behaviour

1. **Onset delay.** A condition must hold continuously for 10 s before it fires (1 s for smoke), so a single noisy
   sample cannot raise an alarm.
2. **Latching.** An alarm that clears by itself stays on screen until it is acknowledged.
3. **Acknowledge.** Silences the buzzer for 120 s. If the condition is still true when the silence ends, the buzzer
   sounds again. An acknowledged alarm whose condition has cleared leaves the list.
4. **Buzzer rhythm by priority** (on / off): high 0.15 s / 0.15 s, medium 0.30 s / 0.70 s, low 0.25 s / 3.0 s.
5. **Sensor faults.** If a sensor stops answering, the alarms that depend on it are suppressed in favour of one
   sensor-fault alarm, so a zero reading can never raise a false "temperature low".
6. **Monitoring switches.** SpO2 and skin-temperature alarms run only while the operator has switched monitoring on for
   that card, so an empty probe does not raise an alarm.
7. **SOS.** A separate call that sounds the buzzer continuously and shows a banner on every client until cancelled.

## Alarm list

| Priority | Id | Raised when |
|---|---|---|
| High | `heater_runaway` | Air temperature is far above the set point while control is on |
| High | `air_temp_high` / `air_temp_low` | Air temperature leaves the set range |
| High | `o2_high` / `o2_low` | Oxygen concentration leaves the set range |
| High | `smoke` | The smoke sensor triggers (or its wire comes off) |
| High | `skin_temp_high` / `skin_temp_low` | Skin temperature leaves the set range |
| High | `spo2_low`, `pulse_low`, `pulse_high` | SpO2 or pulse leaves the set range |
| Medium | `spo2_high` | SpO2 above the set range |
| Medium | `humidity_high` / `humidity_low` | Humidity leaves the set range |
| Medium | `spo2_probe_fault`, `skin_probe_fault` | No valid reading while monitoring is on |
| Medium | `climate_sensor_fault`, `oxygen_sensor_fault` | The sensors do not answer |
| Low | `bed_sensor_fault`, `weight_sensor_fault` | The sensors are absent or not OK |

The ranges are the operator-editable `alarm_limits` (read and change them with `GET`/`POST /alarms/limits`, or in the
app's Alarm Limits sheet). They are saved to `config.json`. The heater-runaway margin and the fault rules are fixed in
`app.py`.

## Where to look in the code

* `ALARM_SPECS` in `raspberry_pi/app.py` lists every alarm: id, priority, label and its check function.
* `evaluate_alarms()` applies the onset delay, latching and acknowledge rules once a second.
* `buzzer_loop()` drives the buzzer from the highest sounding priority.
* `raspberry_pi/tests/test_alarms.py` tests each rule and the whole lifecycle.
