"""Alarm engine: thresholds, the onset delay, latching, acknowledge and sensor faults."""
import copy

from conftest import env, wait_for, status


def alarm_ids(client):
    return {a["id"]: a for a in status(client)["alarms"]["items"]}


def _snapshot(app_module, **climate):
    snap = copy.deepcopy(app_module.state)
    snap["climate"].update({"sensor_status": "OK", **climate})
    return snap


# ---- the individual rules (pure functions of a state snapshot) ---------------------------------

def test_air_temperature_rules_use_the_operator_limits(app_module):
    high = app_module.alarm_limits["air_temp_high"]
    low = app_module.alarm_limits["air_temp_low"]
    assert app_module._check_air_temp_high(_snapshot(app_module, temp=high + 1))[0]
    assert not app_module._check_air_temp_high(_snapshot(app_module, temp=high - 1))[0]
    assert app_module._check_air_temp_low(_snapshot(app_module, temp=low - 1))[0]
    assert not app_module._check_air_temp_low(_snapshot(app_module, temp=low + 1))[0]


def test_a_dead_sensor_never_raises_a_temperature_alarm(app_module):
    snap = _snapshot(app_module, temp=0, sensor_status="ERROR")        # a dead sensor reads 0
    assert not app_module._check_air_temp_low(snap)[0]
    assert app_module._check_climate_fault(snap)[0]                    # it raises a sensor fault instead


def test_heater_runaway_needs_control_on_and_a_large_overshoot(app_module):
    margin = app_module.HEATER_RUNAWAY_MARGIN_C
    on = _snapshot(app_module, control_enabled=True, target_temp=34.0, temp=34.0 + margin + 0.5)
    off = _snapshot(app_module, control_enabled=False, target_temp=34.0, temp=34.0 + margin + 0.5)
    assert app_module._check_heater_runaway(on)[0]
    assert not app_module._check_heater_runaway(off)[0]


def test_skin_and_spo2_alarms_only_run_while_monitoring_is_on(app_module):
    snap = copy.deepcopy(app_module.state)
    snap["skin"].update({"status": "OK", "temp": app_module.alarm_limits["skin_temp_high"] + 1, "monitoring_enabled": False})
    assert not app_module._check_skin_high(snap)[0]
    snap["skin"]["monitoring_enabled"] = True
    assert app_module._check_skin_high(snap)[0]
    snap["skin"]["status"] = "PROBE_OFF"
    assert app_module._check_skin_fault(snap)[0]
    assert not app_module._check_skin_high(snap)[0]                    # no valid reading, so only the fault


def test_smoke_alarm_follows_the_sensor_status(app_module):
    snap = copy.deepcopy(app_module.state)
    snap["smoke"]["status"] = "SMOKE"
    assert app_module._check_smoke(snap)[0]
    snap["smoke"]["status"] = "OK"
    assert not app_module._check_smoke(snap)[0]


def test_smoke_fires_faster_than_the_other_alarms(app_module):
    assert app_module.ALARM_ONSET_OVERRIDE_S["smoke"] < app_module.ALARM_ONSET_DELAY_S


# ---- the running engine (sensor thread -> state -> alarm engine -> API) -------------------------

def test_alarm_lifecycle_raise_latch_acknowledge_clear(fast_alarms, client):
    env.humidity = 95.0                                                 # above the humidity limit
    assert wait_for(lambda: "humidity_high" in alarm_ids(client)), "alarm should fire after the onset delay"
    item = alarm_ids(client)["humidity_high"]
    assert item["priority"] == "medium" and item["active"] and not item["acknowledged"]
    assert status(client)["alarms"]["sounding"] is True

    reply = client.post("/alarms/acknowledge", json={"id": "humidity_high"})
    assert reply.status_code == 200
    assert wait_for(lambda: alarm_ids(client).get("humidity_high", {}).get("acknowledged") is True)
    assert wait_for(lambda: status(client)["alarms"]["sounding"] is False)   # silenced, but still listed
    assert "humidity_high" in alarm_ids(client)

    env.humidity = 60.0                                                 # condition clears
    assert wait_for(lambda: "humidity_high" not in alarm_ids(client)), "acknowledged and cleared alarms leave the list"


def test_a_short_breach_does_not_raise_an_alarm(app_module, client, monkeypatch):
    monkeypatch.setattr(app_module, "ALARM_ONSET_DELAY_S", 8.0)
    env.humidity = 95.0
    assert wait_for(lambda: status(client)["climate"]["humidity"] > 90)
    env.humidity = 60.0
    assert wait_for(lambda: status(client)["climate"]["humidity"] < 70)
    assert "humidity_high" not in alarm_ids(client)


def test_acknowledging_an_unknown_alarm_is_a_404(client):
    assert client.post("/alarms/acknowledge", json={"id": "no_such_alarm"}).status_code == 404


def test_alarm_limits_can_be_read_edited_and_are_validated(app_module, client, config_file):
    limits = client.get("/alarms/limits").get_json()
    assert "air_temp_high" in limits
    assert client.post("/alarms/limits", json={"not_a_limit": 1}).status_code == 400
    assert client.post("/alarms/limits", json={"air_temp_high": "hot"}).status_code == 400
    original = limits["air_temp_high"]
    assert client.post("/alarms/limits", json={"air_temp_high": original + 1}).status_code == 200
    assert client.get("/alarms/limits").get_json()["air_temp_high"] == original + 1
    assert "alarm_limits" in config_file.read_text()
    client.post("/alarms/limits", json={"air_temp_high": original})


def test_sos_call_can_be_raised_and_cancelled(client):
    assert client.post("/sos", json={"active": "yes"}).status_code == 400
    assert client.post("/sos", json={"active": True, "from": "test"}).status_code == 200
    assert status(client)["sos"]["active"] is True
    assert client.post("/sos", json={"active": False}).status_code == 200
    assert status(client)["sos"]["active"] is False
