"""Skin temperature: the YSI-400 curve and the probe reading loop."""
import pytest

from conftest import env, wait_for, status

# (resistance in ohm, temperature in C) from the YSI 400 table
YSI_400_POINTS = [(7355, 0.0), (2252, 25.0), (1355, 37.0), (1200, 40.0)]


@pytest.mark.parametrize("ohm, celsius", YSI_400_POINTS)
def test_curve_matches_the_ysi_table(app_module, ohm, celsius):
    assert app_module.skin_temp_from_resistance(ohm) == pytest.approx(celsius, abs=0.15)


def _volts_for(app_module, celsius_ohm):
    """Voltage at A3 for a probe of this resistance in the 3.3 V / R_ref divider."""
    vdd, rref = app_module.SKIN_VDD, app_module.SKIN_R_REF
    return vdd * celsius_ohm / (rref + celsius_ohm)


def test_probe_on_the_skin_reads_37_degrees(app_module, client):
    env.volts[3] = _volts_for(app_module, 1355)          # about 0.36 V
    assert wait_for(lambda: status(client)["skin"]["status"] == "OK")
    assert status(client)["skin"]["temp"] == pytest.approx(37.0, abs=0.3)


def test_unplugged_probe_is_reported_as_probe_off(app_module, client):
    env.volts[3] = app_module.SKIN_VDD                   # pulled up to the supply
    assert wait_for(lambda: status(client)["skin"]["status"] == "PROBE_OFF")
    assert status(client)["skin"]["temp"] is None


def test_shorted_lead_is_reported_as_short(app_module, client):
    env.volts[3] = 0.001
    assert wait_for(lambda: status(client)["skin"]["status"] == "SHORT")


def test_skin_monitoring_switch_is_validated_and_saved(client, config_file):
    assert client.post("/skin/settings", json={"monitoring_enabled": "yes"}).status_code == 400
    assert client.post("/skin/settings", json={"monitoring_enabled": True}).status_code == 200
    assert status(client)["skin"]["monitoring_enabled"] is True
    assert '"skin"' in config_file.read_text()
    client.post("/skin/settings", json={"monitoring_enabled": False})
