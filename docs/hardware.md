# Hardware

All pin numbers are **BCM** numbers. Relay boards are **active low**: the pin is driven HIGH for "off" and LOW for "on"
(`RELAY_ACTIVE_LOW = True` in `app.py`).

## Sensors

| Measurement | Part | Interface | Address / pin |
|---|---|---|---|
| Air temperature | 2 x TMP117 (averaged with the BME680) | I2C | `0x48`, `0x49` |
| Temperature, humidity, pressure | BME680 | I2C | `0x77` (fallback `0x76`) |
| Humidity (second source) | MS8607 | I2C | `0x40` |
| Oxygen concentration | Electrochemical O2 cell + ADS1115 | I2C, channel **A0** | `0x4A` |
| Skin temperature | YSI-400 probe, divider into the ADS1115 | I2C, channel **A3** | `0x4A` |
| Baby weight | 4 load cells with HX711 amplifiers | GPIO | DT `22, 5, 19, 21`; shared SCK `17` |
| Mattress height | VL53L4CD time-of-flight | I2C | `0x29` |
| SpO2 and pulse | Contec CMS60C oximeter | USB serial, 115200 8N1 | USB |
| Smoke | MQ-2 module, digital output through a divider | GPIO | `9` |
| Video | IMX708 camera (MJPEG stream via `rpicam-vid`) | CSI | - |

## Actuators

| Function | Driver | Pin | Notes |
|---|---|---|---|
| Heater A / Heater B | Relay module | `23`, `24` | Redundant pair; one is active, the other forced off |
| Humidifier | Relay module | `16` | Same dead-band rule as the heaters |
| Phototherapy light | Relay module | `4` | Starts off; not saved across restarts |
| Bed motor (up / down) | L298N channel A, IN1 / IN2 | `25`, `26` | Gated by the time-of-flight sensor, 20 s time-out |
| Lid linear actuator | L298N channel B, IN3 / IN4 | `12`, `20` | 12 V, 50 mm stroke; timed moves. **ENB must be held high.** |
| Oxygen valve | Servo (PWM) | `18` | Angle = 65 + 10 x level, level 0 to 7 |
| Buzzer | Two-pin buzzer | `27` | Rhythm depends on alarm priority |

I2C uses SDA = GPIO 2 and SCL = GPIO 3 (enable I2C in `raspi-config`).

## Wiring notes

### ADS1115

Address `0x4A` (ADDR tied to SDA). VDD to 3.3 V, GND to ground, SDA/SCL to the Pi. A0 is the oxygen cell, A3 is the skin
probe. With VDD at 3.3 V no input can exceed the supply.

### Skin probe (YSI-400)

The probe is a thermistor of 2252 ohm at 25 degrees C, read as half of a divider:

```
3.3 V ──► R_ref (five 2.2 kΩ in series, about 11 kΩ) ──► A3 ◄── probe (jack tip) ──► GND (jack sleeve)
```

The probe resistance from the voltage `V` at A3 and the supply `Vdd`:

```
R_probe = R_ref × V / (Vdd − V)
```

It is converted with the Steinhart-Hart equation `1/T = A + B·ln R + C·(ln R)³`, with
`A = 1.468e-3`, `B = 2.383e-4`, `C = 1.007e-7` (T in kelvin). This reproduces the probe's table: 2252 ohm = 25.0 °C,
1355 ohm = 37.0 °C, 7355 ohm = 0 °C (checked by `tests/test_skin.py`). Set `SKIN_R_REF` in `app.py` to the **measured**
resistance of your resistor string. Expected voltage at A3: about 0.56 V at 25 °C and 0.36 V at 37 °C.

| Status | Meaning | Rule |
|---|---|---|
| `OK` | Valid reading | 5 to 60 °C |
| `PROBE_OFF` | Nothing in the jack | Voltage at or above 97 % of the supply |
| `SHORT` | Lead shorted | Resistance below 150 ohm |
| `RANGE` | Not a skin temperature | Outside 5 to 60 °C |
| `NOT_CONNECTED` | ADS1115 not answering | I2C error |

### Phototherapy light

Switched on the low side by a relay: supply, then buck converter OUT+, then the light (red wire). The light's black wire
goes to the relay **COM** and the converter's OUT- goes to the relay **NO**. Normally open means the light is off whenever
the relay is off. Set the converter's output voltage to the light's rated voltage with a multimeter before connecting
the light. Check the relay board's **DC** rating against the light's current.

### Lid actuator and bed motor

Both run from 12 V through an L298N (channel A bed, channel B lid). Tie the lid channel's ENB high. Driven through the
L298N, the actuator sees a few volts less than from a direct supply.

### Smoke sensor

The MQ-2 module's DO output swings to 5 V, so it goes through a resistor divider to GPIO 9. A wire that comes off pulls
the pin low and raises the alarm, so a broken wire is never silent. The sensor heats for about two minutes before its
output means anything (`WARMING_UP`).

### Relays and mains

Relay outputs are rated for the usual 10 A relays. Every mains load needs its own fuse and an enclosure that cannot be
touched.
