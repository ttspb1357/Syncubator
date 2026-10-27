"""HTTP API: status shape, settings, the lid rule, the phototherapy relay, input validation."""
import json

from conftest import gpio, wait_for, status


def test_status_has_a_section_for_every_subsystem(client):
    body = status(client)
    for section in ("weight", "climate", "bed", "oxygen", "spo2", "skin", "smoke", "lid", "photo", "alarms", "sos"):
        assert section in body, section


def test_climate_settings_are_applied_and_saved_to_disk(client, config_file):
    assert client.post("/climate/settings", json={"target_temp": 33.5, "target_hum": 55, "enabled": True}).status_code == 200
    climate = status(client)["climate"]
    assert climate["target_temp"] == 33.5 and climate["control_enabled"] is True
    saved = json.loads(config_file.read_text())
    assert saved["climate"]["target_temp"] == 33.5
    client.post("/climate/settings", json={"enabled": False})


def test_dead_band_heater_control_follows_the_air_temperature(app_module, client):
    from conftest import env
    client.post("/climate/settings", json={"target_temp": 30.0, "enabled": True})
    env.air_temp = 25.0                                                  # well below target minus the dead band
    assert wait_for(lambda: status(client)["climate"]["heater_on"] is True)
    assert gpio.levels[app_module.HEATER_PIN_A] == gpio.LOW              # relay board is active low
    env.air_temp = 34.0                                                  # above target plus the dead band
    assert wait_for(lambda: status(client)["climate"]["heater_on"] is False)
    client.post("/climate/settings", json={"enabled": False})
    assert wait_for(lambda: gpio.levels[app_module.HEATER_PIN_A] == gpio.HIGH)


def test_oxygen_level_is_validated(client):
    assert client.post("/oxygen/level", json={}).status_code == 400
    assert client.post("/oxygen/level", json={"level": "high"}).status_code == 400
    assert client.post("/oxygen/level", json={"level": 99}).status_code == 400


def test_bed_direction_is_validated(client):
    assert client.post("/bed/move", json={"direction": "sideways"}).status_code == 400


# ---- lid --------------------------------------------------------------------------------------

def _reset_lid(app_module):
    with app_module.lock:
        app_module.state["lid"].update({"position": "closed", "moving": None})


def test_lid_cannot_be_opened_twice_without_closing(app_module, client, monkeypatch):
    monkeypatch.setattr(app_module, "LID_OPEN_S", 0.3)
    monkeypatch.setattr(app_module, "LID_CLOSE_S", 0.3)
    _reset_lid(app_module)

    assert client.post("/lid/move", json={"action": "sideways"}).status_code == 400
    assert client.post("/lid/move", json={"action": "open"}).status_code == 200
    assert client.post("/lid/move", json={"action": "close"}).status_code == 409        # busy moving
    assert wait_for(lambda: status(client)["lid"]["moving"] is None)
    assert status(client)["lid"]["position"] == "open"
    assert client.post("/lid/move", json={"action": "open"}).status_code == 409         # locked until Close

    assert client.post("/lid/move", json={"action": "close"}).status_code == 200
    assert wait_for(lambda: status(client)["lid"]["moving"] is None)
    assert status(client)["lid"]["position"] == "closed"
    assert client.post("/lid/move", json={"action": "open"}).status_code == 200        # unlocked again
    assert wait_for(lambda: status(client)["lid"]["moving"] is None)
    _reset_lid(app_module)


def test_lid_motor_is_stopped_after_every_move(app_module, client, monkeypatch):
    monkeypatch.setattr(app_module, "LID_CLOSE_S", 0.2)
    _reset_lid(app_module)
    with app_module.lock:
        app_module.state["lid"]["position"] = "open"
    client.post("/lid/move", json={"action": "close"})
    assert wait_for(lambda: status(client)["lid"]["moving"] is None)
    assert gpio.levels[app_module.LID_RETRACT_PIN] == gpio.LOW
    assert gpio.levels[app_module.LID_EXTEND_PIN] == gpio.LOW


# ---- phototherapy light -----------------------------------------------------------------------

def test_phototherapy_light_starts_off_and_switches_the_relay(app_module, client):
    assert gpio.modes[app_module.PHOTO_PIN] == gpio.OUT
    assert client.post("/photo", json={"on": "yes"}).status_code == 400
    assert client.post("/photo", json={"on": True}).status_code == 200
    assert status(client)["photo"]["on"] is True
    assert gpio.levels[app_module.PHOTO_PIN] == gpio.LOW                  # active low: LOW is relay on
    assert client.post("/photo", json={"on": False}).status_code == 200
    assert status(client)["photo"]["on"] is False
    assert gpio.levels[app_module.PHOTO_PIN] == gpio.HIGH


def test_phototherapy_state_is_not_saved_so_it_is_off_after_a_restart(client, config_file):
    client.post("/photo", json={"on": True})
    client.post("/climate/settings", json={"enabled": False})            # any change makes the app save its settings
    assert '"photo"' not in config_file.read_text()
    client.post("/photo", json={"on": False})


def test_spo2_monitoring_switch_is_validated(client):
    assert client.post("/spo2/settings", json={"monitoring_enabled": 1}).status_code == 400
    assert client.post("/spo2/settings", json={"monitoring_enabled": False}).status_code == 200
