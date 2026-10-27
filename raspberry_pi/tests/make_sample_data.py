"""Regenerates the files in ../sample_data/ from the running backend (with fake sensors).

    cd raspberry_pi
    python tests/make_sample_data.py

Run it after the API gains a field; tests/test_sample_data.py fails when the samples are out of date.
"""
import json
import pathlib
import sys
import tempfile
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from conftest import backend, env  # noqa: E402  (importing conftest installs the hardware fakes)

OUT = pathlib.Path(__file__).resolve().parent.parent / "sample_data"
WEIGHT = {"total": 3120.0, "cells": [780.5, 779.0, 781.2, 779.3]}


def dump(name, data):
    (OUT / name).write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("wrote", name)


def main():
    tmp = pathlib.Path(tempfile.mkdtemp())
    backend.CONFIG_PATH = str(tmp / "config.json")
    backend.ALARM_ONSET_DELAY_S = 0.5
    client = backend.app.test_client()
    get = lambda: json.loads(client.get("/status").data)

    # a baby on the scale, skin probe at about 37 C, air a little under the set point
    env.air_temp, env.humidity, env.bed_cm = 33.4, 62.0, 18.2
    env.volts[0] = 1.4
    env.volts[3] = backend.SKIN_VDD * 1355 / (backend.SKIN_R_REF + 1355)
    client.post("/climate/settings", json={"target_temp": 33.5, "target_hum": 60, "enabled": True})
    client.post("/oxygen/settings", json={"target_percent": 25.0, "enabled": False})
    client.post("/skin/settings", json={"monitoring_enabled": True})
    time.sleep(3.5)
    OUT.mkdir(exist_ok=True)
    normal = get()
    normal["weight"].update(WEIGHT)
    dump("status_example.json", normal)

    # the same incubator with a humidity alarm raised
    env.humidity = 92.0
    deadline = time.time() + 12
    while time.time() < deadline and not get()["alarms"]["items"]:
        time.sleep(0.2)
    time.sleep(1.2)
    alarm = get()
    alarm["weight"].update(WEIGHT)
    dump("status_with_alarm_example.json", alarm)

    dump("config.example.json", json.loads((tmp / "config.json").read_text()))


if __name__ == "__main__":
    main()
